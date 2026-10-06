import 'dart:convert';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/database.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart';

/// [AuthenticatorRepository] on Drift (metadata) + a [SecretStore] (secrets
/// and recovery codes). SQLite never sees a secret: rows only hold the
/// secure-storage key.
///
/// Secret validation and decoding go through [OtpCodec] so this layer has no
/// OTP maths of its own.
class DriftAuthenticatorRepository implements AuthenticatorRepository {
  DriftAuthenticatorRepository(
    this._db, {
    required SecretStore secrets,
    required OtpCodec codec,
    DateTime Function() now = DateTime.now,
    String Function() newKey = newId,
    RedactedLogger? logger,
  }) : _secrets = secrets,
       _codec = codec,
       _now = now,
       _newKey = newKey,
       _log = logger ?? RedactedLogger('authenticator');

  /// Prefix of every secure-storage key this repository owns.
  static const keyPrefix = 'otp.';
  static const recoverySuffix = '.recovery';

  final AppDatabase _db;
  final SecretStore _secrets;
  final OtpCodec _codec;
  final DateTime Function() _now;
  final String Function() _newKey;
  final RedactedLogger _log;

  static String recoveryKey(String secretKeyId) =>
      '$secretKeyId$recoverySuffix';

  @override
  Stream<List<OtpAccount>> watchAccounts() {
    final q = _db.select(_db.totpAccounts)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return q.watch().map((rows) => rows.map(_toAccount).toList());
  }

  @override
  Future<Result<OtpAccount>> add(NewOtpAccount account) async {
    final label = account.label.trim();
    if (label.isEmpty) {
      return const Err(
        AppFailure(FailureCode.invalidOtpUri, detail: 'Enter an account name.'),
      );
    }
    if (!NewOtpAccount.supportedDigits.contains(account.digits) ||
        account.period < 1) {
      return const Err(
        AppFailure(
          FailureCode.invalidOtpUri,
          detail: 'Codes must have 6 or 8 digits and a positive period.',
        ),
      );
    }
    final normalized = _codec.normalizeSecret(account.secret);
    if (normalized case Err(:final failure)) return Err(failure);
    final secret = normalized.valueOrNull!;

    final keyId = '$keyPrefix${_newKey()}';
    final issuer = account.issuer?.trim();
    try {
      // Secret first: a row must never point at a missing key.
      await _secrets.write(keyId, secret);
    } on Object catch (e, st) {
      _log.warn('secret_write_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(FailureCode.secretUnavailable, cause: e, stackTrace: st),
      );
    }
    final result = await guard(
      () => _db.transaction(() async {
        final maxOrder = _db.totpAccounts.sortOrder.max();
        final last = await (_db.selectOnly(
          _db.totpAccounts,
        )..addColumns([maxOrder])).map((r) => r.read(maxOrder)).getSingle();
        final row = TotpAccountsCompanion.insert(
          id: newId(),
          label: label,
          issuer: Value(issuer == null || issuer.isEmpty ? null : issuer),
          secretKeyId: keyId,
          digits: Value(account.digits),
          period: Value(account.period),
          algorithm: Value(account.algorithm.name),
          type: Value(account.type.name),
          counter: Value(account.counter),
          sortOrder: Value((last ?? -1) + 1),
          createdAt: _now(),
        );
        await _db.into(_db.totpAccounts).insert(row);
        final inserted = await (_db.select(
          _db.totpAccounts,
        )..where((t) => t.secretKeyId.equals(keyId))).getSingle();
        return _toAccount(inserted);
      }),
    );
    if (!result.isOk) await _safeDelete(keyId);
    return result;
  }

  @override
  Future<Result<void>> rename(
    String id, {
    required String label,
    String? issuer,
  }) => guard(() async {
    final l = label.trim();
    if (l.isEmpty) {
      throw const AppFailure(
        FailureCode.invalidOtpUri,
        detail: 'Enter an account name.',
      );
    }
    final i = issuer?.trim();
    final n =
        await (_db.update(
          _db.totpAccounts,
        )..where((t) => t.id.equals(id))).write(
          TotpAccountsCompanion(
            label: Value(l),
            issuer: Value(i == null || i.isEmpty ? null : i),
          ),
        );
    if (n == 0) throw const AppFailure(FailureCode.notFound);
  });

  @override
  Future<Result<int>> incrementCounter(String id) => guard(
    () => _db.transaction(() async {
      final row = await (_db.select(
        _db.totpAccounts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) throw const AppFailure(FailureCode.notFound);
      final next = row.counter + 1;
      await (_db.update(_db.totpAccounts)..where((t) => t.id.equals(id))).write(
        TotpAccountsCompanion(counter: Value(next)),
      );
      return next;
    }),
  );

  @override
  Future<Result<void>> remove(String id) async {
    final row = await (_db.select(
      _db.totpAccounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return const Err(AppFailure(FailureCode.notFound));
    // Wipe the secrets first: if that fails the account stays visible and the
    // user can retry, instead of leaving an invisible secret behind.
    try {
      await _secrets.delete(row.secretKeyId);
      await _secrets.delete(recoveryKey(row.secretKeyId));
    } on Object catch (e, st) {
      _log.warn('secret_delete_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(FailureCode.secretUnavailable, cause: e, stackTrace: st),
      );
    }
    final deleted = await guard(
      () => (_db.delete(_db.totpAccounts)..where((t) => t.id.equals(id))).go(),
    );
    return deleted.map((_) {});
  }

  @override
  Future<Result<Uint8List>> readSecret(OtpAccount account) async {
    final String? value;
    try {
      value = await _secrets.read(account.secretKeyId);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.secretUnavailable, cause: e, stackTrace: st),
      );
    }
    if (value == null) {
      return const Err(AppFailure(FailureCode.secretUnavailable));
    }
    final decoded = _codec.decodeSecret(value);
    return decoded.isOk
        ? decoded
        : const Err(AppFailure(FailureCode.secretUnavailable));
  }

  @override
  Future<Result<List<RecoveryCode>>> readRecoveryCodes(
    OtpAccount account,
  ) async {
    try {
      final raw = await _secrets.read(recoveryKey(account.secretKeyId));
      if (raw == null || raw.isEmpty) return const Ok([]);
      final list = jsonDecode(raw) as List<dynamic>;
      return Ok([
        for (final e in list)
          RecoveryCode.fromJson((e as Map).cast<String, dynamic>()),
      ]);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.secretUnavailable, cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<void>> saveRecoveryCodes(
    OtpAccount account,
    List<RecoveryCode> codes,
  ) async {
    final key = recoveryKey(account.secretKeyId);
    try {
      if (codes.isEmpty) {
        await _secrets.delete(key);
      } else {
        await _secrets.write(
          key,
          jsonEncode([for (final c in codes) c.toJson()]),
        );
      }
      return const Ok(null);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.secretUnavailable, cause: e, stackTrace: st),
      );
    }
  }

  /// Deletes secure-storage entries left behind by an interrupted delete or
  /// add (keys with [keyPrefix] that no row references). Returns the count.
  Future<Result<int>> purgeOrphanSecrets() => guard(() async {
    final used = (await _db.select(_db.totpAccounts).get())
        .map((r) => r.secretKeyId)
        .toSet();
    var purged = 0;
    for (final key in await _secrets.keys()) {
      if (!key.startsWith(keyPrefix)) continue;
      final base = key.endsWith(recoverySuffix)
          ? key.substring(0, key.length - recoverySuffix.length)
          : key;
      if (used.contains(base)) continue;
      await _secrets.delete(key);
      purged++;
    }
    return purged;
  });

  // ── Full backup and erase (audit H-04, H-06) ────────────────────────────

  /// Every account with its secret (canonical Base32) and recovery codes,
  /// for the full backup. Accounts whose secret is missing from secure
  /// storage are skipped (nothing to restore them with). Throws an
  /// [AppFailure] (`secretUnavailable`) when the keystore can't be read.
  Future<List<Map<String, Object?>>> exportAccounts() async {
    final rows =
        await (_db.select(_db.totpAccounts)..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
            .get();
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final String? secret;
      final String? recovery;
      try {
        secret = await _secrets.read(r.secretKeyId);
        recovery = await _secrets.read(recoveryKey(r.secretKeyId));
      } on Object catch (e, st) {
        throw AppFailure(
          FailureCode.secretUnavailable,
          cause: e,
          stackTrace: st,
        );
      }
      if (secret == null || secret.isEmpty) continue;
      Object? codes;
      if (recovery != null && recovery.isNotEmpty) {
        try {
          codes = jsonDecode(recovery);
        } on FormatException {
          codes = null;
        }
      }
      out.add({
        'label': r.label,
        'issuer': r.issuer,
        'type': r.type,
        'algorithm': r.algorithm,
        'digits': r.digits,
        'period': r.period,
        'counter': r.counter,
        'createdAt': r.createdAt.toIso8601String(),
        'secret': secret,
        'recoveryCodes': codes is List ? codes : const <Object?>[],
      });
    }
    return out;
  }

  /// Restores accounts written by [exportAccounts]. Idempotent: an account
  /// with the same issuer, name and secret is skipped. Returns how many
  /// were added; unreadable entries are skipped.
  Future<int> restoreAccounts(Object? data) async {
    if (data is! List) return 0;
    final existing = <String>{};
    for (final r in await _db.select(_db.totpAccounts).get()) {
      final secret = await _secrets.read(r.secretKeyId);
      if (secret != null) existing.add(_identity(r.issuer, r.label, secret));
    }
    var added = 0;
    for (final item in data) {
      if (item is! Map) continue;
      final label = item['label'];
      final rawSecret = item['secret'];
      if (label is! String || rawSecret is! String) continue;
      final secret = _codec.normalizeSecret(rawSecret).valueOrNull;
      if (secret == null) continue;
      final issuer = item['issuer'] as String?;
      final identity = _identity(issuer, label, secret);
      if (existing.contains(identity)) continue;
      final digits = item['digits'];
      final period = item['period'];
      final counter = item['counter'];
      final result = await add(
        NewOtpAccount(
          label: label,
          issuer: issuer,
          secret: secret,
          type: OtpType.values.asNameMap()[item['type']] ?? OtpType.totp,
          algorithm:
              OtpAlgorithm.values.asNameMap()[item['algorithm']] ??
              OtpAlgorithm.sha1,
          digits: digits is int ? digits : 6,
          period: period is int ? period : 30,
          counter: counter is int ? counter : 0,
        ),
      );
      final account = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) =>
          failure.code == FailureCode.secretUnavailable
              ? throw failure
              : null, // Invalid entry: skip it, keep going.
      };
      if (account == null) continue;
      final codes = item['recoveryCodes'];
      if (codes is List && codes.isNotEmpty) {
        final parsed = [
          for (final c in codes)
            if (c is Map && c['code'] is String)
              RecoveryCode.fromJson(c.cast<String, dynamic>()),
        ];
        final saved = await saveRecoveryCodes(account, parsed);
        if (saved case Err(:final failure)) throw failure;
      }
      existing.add(identity);
      added++;
    }
    return added;
  }

  static String _identity(String? issuer, String label, String secret) =>
      '${(issuer ?? '').trim().toLowerCase()}|${label.trim()}|$secret';

  /// Deletes every account and every secret and recovery code this
  /// repository owns (keys starting with [keyPrefix]) — "Erase everything".
  Future<void> eraseAll() async {
    for (final key in await _secrets.keys()) {
      if (key.startsWith(keyPrefix)) await _secrets.delete(key);
    }
    await _db.delete(_db.totpAccounts).go();
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _secrets.delete(key);
    } on Object {
      // Best effort; purgeOrphanSecrets cleans up later.
    }
  }

  static OtpAccount _toAccount(TotpAccountRow r) => OtpAccount(
    id: r.id,
    label: r.label,
    issuer: r.issuer,
    secretKeyId: r.secretKeyId,
    type: OtpType.values.asNameMap()[r.type] ?? OtpType.totp,
    algorithm:
        OtpAlgorithm.values.asNameMap()[r.algorithm] ?? OtpAlgorithm.sha1,
    digits: r.digits,
    period: r.period,
    counter: r.counter,
    sortOrder: r.sortOrder,
    createdAt: r.createdAt,
  );
}
