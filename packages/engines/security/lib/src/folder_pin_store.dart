import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

/// [FolderPinStore] on a [SecretStore] (the platform keystore in the app).
///
/// - Only a PBKDF2-HMAC-SHA256 hash is stored ([defaultIterations] rounds,
///   a random 16-byte salt per PIN), under `folder_pin.<folderId>`. The PIN
///   itself is never stored and nothing is written to SQLite.
/// - Wrong PINs are throttled: after [freeAttempts] failures each further
///   attempt waits [baseDelay], doubling per failure up to [maxDelay]. The
///   counter lives in the keystore too, so restarting the app doesn't reset
///   it. A correct PIN resets it.
/// - Comparison is constant-time.
///
/// A 4–8 digit PIN is a convenience gate, not encryption: someone who can
/// read the keystore could brute-force it offline. UI copy says so.
class KeystoreFolderPinStore implements FolderPinStore {
  KeystoreFolderPinStore(
    this._secrets, {
    this.iterations = defaultIterations,
    DateTime Function()? clock,
    Random? random,
    @visibleForTesting bool runInIsolate = true,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _isolate = runInIsolate;

  static const defaultIterations = 120000;
  static const freeAttempts = 5;
  static const baseDelay = Duration(seconds: 30);
  static const maxDelay = Duration(minutes: 30);
  static const keyPrefix = 'folder_pin.';
  static const attemptsPrefix = 'folder_pin_attempts.';

  final SecretStore _secrets;
  final int iterations;
  final DateTime Function() _clock;
  final Random _random;
  final bool _isolate;

  static String hashKey(String folderId) => '$keyPrefix$folderId';
  static String attemptsKey(String folderId) => '$attemptsPrefix$folderId';

  /// Delay after [failures] consecutive wrong PINs (none before the limit).
  static Duration? delayAfter(int failures) {
    if (failures < freeAttempts) return null;
    final doublings = min(failures - freeAttempts, 16);
    final seconds = baseDelay.inSeconds * (1 << doublings);
    return seconds >= maxDelay.inSeconds
        ? maxDelay
        : Duration(seconds: seconds);
  }

  @override
  Future<bool> hasPin(String folderId) async =>
      (await _secrets.read(hashKey(folderId))) != null;

  @override
  Future<Result<void>> setPin(String folderId, String pin) {
    if (!FolderPinStore.isValidPin(pin)) {
      return Future.value(
        const Err(
          AppFailure(
            FailureCode.unknown,
            heading: 'PIN must be 4 to 8 digits',
            message: 'Use 4 to 8 digits.',
            action: FailureAction.none,
          ),
        ),
      );
    }
    return guard(() async {
      final salt = Uint8List.fromList(
        List<int>.generate(16, (_) => _random.nextInt(256)),
      );
      final hash = await _derive(pin, salt, iterations);
      await _secrets.write(
        hashKey(folderId),
        jsonEncode({
          'v': 1,
          'alg': 'pbkdf2-sha256',
          'iter': iterations,
          'salt': base64Encode(salt),
          'hash': base64Encode(hash),
        }),
      );
      await _secrets.delete(attemptsKey(folderId));
    });
  }

  @override
  Future<Result<PinCheck>> verifyPin(String folderId, String pin) =>
      guard(() async {
        final wait = await retryAfter(folderId);
        if (wait != null) return PinThrottled(wait);
        final raw = await _secrets.read(hashKey(folderId));
        if (raw == null) {
          throw const AppFailure(
            FailureCode.secretUnavailable,
            message:
                "This folder's PIN is missing on this phone. Use Forgot PIN "
                'to set a new one.',
            action: FailureAction.none,
          );
        }
        final stored = jsonDecode(raw) as Map<String, dynamic>;
        final salt = base64Decode(stored['salt'] as String);
        final expected = base64Decode(stored['hash'] as String);
        final actual = FolderPinStore.isValidPin(pin)
            ? await _derive(pin, salt, stored['iter'] as int)
            : Uint8List(0);
        if (_constantTimeEquals(actual, expected)) {
          await _secrets.delete(attemptsKey(folderId));
          return const PinAccepted();
        }
        final failures = (await _attempts(folderId)).failures + 1;
        final delay = delayAfter(failures);
        await _secrets.write(
          attemptsKey(folderId),
          jsonEncode({
            'failures': failures,
            if (delay != null)
              'until': _clock().add(delay).millisecondsSinceEpoch,
          }),
        );
        return PinRejected(
          attemptsLeft: max(0, freeAttempts - failures),
          retryAfter: delay,
        );
      });

  @override
  Future<Duration?> retryAfter(String folderId) async {
    final until = (await _attempts(folderId)).until;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left > Duration.zero ? left : null;
  }

  @override
  Future<void> removePin(String folderId) async {
    await _secrets.delete(hashKey(folderId));
    await _secrets.delete(attemptsKey(folderId));
  }

  Future<({int failures, DateTime? until})> _attempts(String folderId) async {
    final raw = await _secrets.read(attemptsKey(folderId));
    if (raw == null) return (failures: 0, until: null);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final until = j['until'] as int?;
      return (
        failures: (j['failures'] as int?) ?? 0,
        until: until == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(until),
      );
    } on Object {
      // Corrupt counter: fail safe with the maximum delay.
      return (failures: freeAttempts + 16, until: _clock().add(maxDelay));
    }
  }

  Future<Uint8List> _derive(String pin, Uint8List salt, int rounds) => _isolate
      ? Isolate.run(() => pbkdf2(pin, salt, rounds))
      : pbkdf2(pin, salt, rounds);

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      diff |= (i < a.length ? a[i] : 0) ^ b[i];
    }
    return diff == 0;
  }
}

/// PBKDF2-HMAC-SHA256 → 32 bytes.
@visibleForTesting
Future<Uint8List> pbkdf2(String pin, List<int> salt, int iterations) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}
