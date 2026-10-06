import 'dart:convert';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

void main() {
  late _MemorySecrets secrets;
  late DateTime now;
  late KeystoreFolderPinStore store;

  setUp(() {
    secrets = _MemorySecrets();
    now = DateTime(2026, 9, 28, 12);
    store = KeystoreFolderPinStore(
      secrets,
      iterations: 1000, // Fast in tests; production uses defaultIterations.
      clock: () => now,
      runInIsolate: false,
    );
  });

  test('production cost is at least 100k PBKDF2 iterations', () {
    expect(
      KeystoreFolderPinStore.defaultIterations,
      greaterThanOrEqualTo(100000),
    );
    expect(KeystoreFolderPinStore(secrets).iterations, 120000);
  });

  test('PIN format: 4–8 digits only', () async {
    expect(FolderPinStore.isValidPin('1234'), isTrue);
    expect(FolderPinStore.isValidPin('12345678'), isTrue);
    expect(FolderPinStore.isValidPin('123'), isFalse);
    expect(FolderPinStore.isValidPin('123456789'), isFalse);
    expect(FolderPinStore.isValidPin('12a4'), isFalse);
    expect((await store.setPin('f', '12')).isOk, isFalse);
    expect(await store.hasPin('f'), isFalse);
  });

  test('stores only a salted hash in the keystore, never the PIN', () async {
    expect((await store.setPin('f1', '2468')).isOk, isTrue);
    expect((await store.setPin('f2', '2468')).isOk, isTrue);
    expect(await store.hasPin('f1'), isTrue);
    final raw1 = secrets.values[KeystoreFolderPinStore.hashKey('f1')]!;
    final raw2 = secrets.values[KeystoreFolderPinStore.hashKey('f2')]!;
    expect(raw1, isNot(contains('2468')));
    final j1 = jsonDecode(raw1) as Map<String, dynamic>;
    final j2 = jsonDecode(raw2) as Map<String, dynamic>;
    expect(j1['alg'], 'pbkdf2-sha256');
    expect(j1['iter'], 1000);
    expect(base64Decode(j1['salt'] as String), hasLength(16));
    expect(base64Decode(j1['hash'] as String), hasLength(32));
    // Different salts → different hashes for the same PIN.
    expect(j1['salt'], isNot(j2['salt']));
    expect(j1['hash'], isNot(j2['hash']));
  });

  test('pbkdf2 matches the RFC 7914 test vector', () async {
    // PBKDF2-HMAC-SHA256("passwd", "salt", 1, 64) — first 32 bytes.
    final out = await pbkdf2('passwd', utf8.encode('salt'), 1);
    expect(
      out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
    );
  });

  test('verify accepts the right PIN and rejects others', () async {
    await store.setPin('f', '135790');
    expect(
      (await store.verifyPin('f', '135790')).valueOrNull,
      isA<PinAccepted>(),
    );
    final wrong = (await store.verifyPin('f', '000000')).valueOrNull;
    expect(wrong, isA<PinRejected>());
    expect((wrong! as PinRejected).attemptsLeft, 4);
    // Invalid input is simply wrong, not an error.
    expect((await store.verifyPin('f', 'abc')).valueOrNull, isA<PinRejected>());
  });

  test('throttles after 5 failures with an increasing delay', () async {
    await store.setPin('f', '1111');
    for (var i = 0; i < 4; i++) {
      final r =
          (await store.verifyPin('f', '2222')).valueOrNull! as PinRejected;
      expect(r.retryAfter, isNull);
    }
    final fifth =
        (await store.verifyPin('f', '2222')).valueOrNull! as PinRejected;
    expect(fifth.attemptsLeft, 0);
    expect(fifth.retryAfter, const Duration(seconds: 30));

    // During the delay even the right PIN isn't checked.
    final blocked = (await store.verifyPin('f', '1111')).valueOrNull;
    expect(blocked, isA<PinThrottled>());
    expect(await store.retryAfter('f'), const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 31));
    final sixth =
        (await store.verifyPin('f', '2222')).valueOrNull! as PinRejected;
    expect(sixth.retryAfter, const Duration(minutes: 1));

    // A fresh store (app restart) still enforces the delay.
    final restarted = KeystoreFolderPinStore(
      secrets,
      iterations: 1000,
      clock: () => now,
      runInIsolate: false,
    );
    expect(
      (await restarted.verifyPin('f', '1111')).valueOrNull,
      isA<PinThrottled>(),
    );

    now = now.add(const Duration(minutes: 2));
    expect(
      (await store.verifyPin('f', '1111')).valueOrNull,
      isA<PinAccepted>(),
    );
    // Success resets the counter.
    final again =
        (await store.verifyPin('f', '2222')).valueOrNull! as PinRejected;
    expect(again.attemptsLeft, 4);
    expect(again.retryAfter, isNull);
  });

  test('delay doubles and is capped', () {
    expect(KeystoreFolderPinStore.delayAfter(4), isNull);
    expect(KeystoreFolderPinStore.delayAfter(5), const Duration(seconds: 30));
    expect(KeystoreFolderPinStore.delayAfter(7), const Duration(minutes: 2));
    expect(
      KeystoreFolderPinStore.delayAfter(50),
      KeystoreFolderPinStore.maxDelay,
    );
  });

  test('resetting the PIN (Forgot PIN) clears the throttle', () async {
    await store.setPin('f', '1111');
    for (var i = 0; i < 5; i++) {
      await store.verifyPin('f', '9999');
    }
    expect(await store.retryAfter('f'), isNotNull);
    await store.setPin('f', '4321');
    expect(await store.retryAfter('f'), isNull);
    expect(
      (await store.verifyPin('f', '4321')).valueOrNull,
      isA<PinAccepted>(),
    );
  });

  test(
    'removePin deletes hash and counter; missing PIN is a typed failure',
    () async {
      await store.setPin('f', '1111');
      await store.verifyPin('f', '0000');
      await store.removePin('f');
      expect(secrets.values, isEmpty);
      final r = await store.verifyPin('f', '1111');
      expect(r.failureOrNull?.code.name, 'secretUnavailable');
    },
  );

  test('runs in a background isolate by default', () async {
    final isolated = KeystoreFolderPinStore(secrets, iterations: 1000);
    await isolated.setPin('f', '1234');
    expect(
      (await isolated.verifyPin('f', '1234')).valueOrNull,
      isA<PinAccepted>(),
    );
  });
}
