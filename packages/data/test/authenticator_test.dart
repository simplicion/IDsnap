import 'dart:convert';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2 schema exactly as Drift created it before the authenticator migration.
const _v2Documents =
    'CREATE TABLE documents (id TEXT NOT NULL, name TEXT NOT NULL, '
    'format TEXT NOT NULL, relative_path TEXT NOT NULL, '
    'size_bytes INTEGER NOT NULL, page_count INTEGER NULL, '
    'folder_id TEXT NULL, favorite INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("favorite" IN (0, 1)), thumbnail_path TEXT NULL, '
    'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
    'category TEXT NULL, expires_at INTEGER NULL, slot TEXT NULL, '
    'PRIMARY KEY (id))';
const _v2Folders =
    'CREATE TABLE folders (id TEXT NOT NULL, name TEXT NOT NULL, '
    'created_at INTEGER NOT NULL, system_key TEXT NULL UNIQUE, '
    'PRIMARY KEY (id))';
const _v2Document =
    "INSERT INTO documents VALUES ('d1', 'Passport', 'pdf', "
    "'documents/p.pdf', 99, 1, NULL, 0, NULL, 1700000000, 1700000000, "
    "'ids', 1900000000, 'passport')";
const _v2 = <String>[
  _v2Documents,
  _v2Folders,
  _v2Document,
  "INSERT INTO folders VALUES ('f1', 'Work', 1700000000, NULL)",
  'PRAGMA user_version = 2',
];

/// In-memory [SecretStore] that records every call.
class FakeSecretStore implements SecretStore {
  final values = <String, String>{};
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keystore unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('keystore unavailable');
    values.remove(key);
  }

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

const _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  test('v2 → v3 migration keeps rows and adds totp_accounts', () async {
    var seeded = false;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          if (seeded) return;
          seeded = true;
          _v2.forEach(raw.execute);
        },
      ),
    );
    addTearDown(db.close);

    final doc = await DriftDocumentRepository(db).byId('d1');
    expect(doc?.name, 'Passport');
    expect(doc?.category, DocumentCategory.ids);
    expect(doc?.slot, 'passport');

    final repo = DriftAuthenticatorRepository(
      db,
      secrets: FakeSecretStore(),
      codec: const OtpCodecImpl(),
    );
    expect(await repo.watchAccounts().first, isEmpty);
    final added = await repo.add(
      const NewOtpAccount(label: 'me', secret: _secret),
    );
    expect(added.isOk, isTrue);

    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, db.schemaVersion);
    final columns = await db
        .customSelect('PRAGMA table_info(totp_accounts)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(
      columns,
      containsAll(<String>[
        'id',
        'label',
        'issuer',
        'secret_key_id',
        'digits',
        'period',
        'algorithm',
        'type',
        'counter',
        'sort_order',
        'created_at',
      ]),
    );
    expect(columns, isNot(contains('secret')));
  });

  group('DriftAuthenticatorRepository', () {
    late AppDatabase db;
    late FakeSecretStore secrets;
    late DriftAuthenticatorRepository repo;
    var keySeq = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      secrets = FakeSecretStore();
      keySeq = 0;
      repo = DriftAuthenticatorRepository(
        db,
        secrets: secrets,
        codec: const OtpCodecImpl(),
        now: () => DateTime(2026, 9, 25),
        newKey: () => 'k${keySeq++}',
      );
    });

    tearDown(() => db.close());

    Future<OtpAccount> add(NewOtpAccount a) async =>
        (await repo.add(a)).valueOrNull!;

    test('add stores the secret in secure storage only', () async {
      final a = await add(
        const NewOtpAccount(
          label: ' alice@example.com ',
          issuer: 'GitHub',
          secret: 'jbsw y3dp ehpk 3pxp',
          algorithm: OtpAlgorithm.sha256,
          digits: 8,
          period: 60,
        ),
      );
      expect(a.label, 'alice@example.com');
      expect(a.issuer, 'GitHub');
      expect(a.secretKeyId, 'otp.k0');
      expect(a.algorithm, OtpAlgorithm.sha256);
      expect(a.digits, 8);
      expect(a.period, 60);
      expect(secrets.values, {'otp.k0': _secret});

      // No column of any row contains the secret.
      final dump = await db
          .customSelect('SELECT * FROM totp_accounts')
          .map((r) => r.data.values.join('|'))
          .get();
      expect(dump.single.contains(_secret), isFalse);

      final bytes = (await repo.readSecret(a)).valueOrNull!;
      expect(Base32.encode(bytes), _secret);
    });

    test('rejects an invalid secret without writing anything', () async {
      final r = await repo.add(
        const NewOtpAccount(label: 'x', secret: 'not base32!'),
      );
      expect(r.failureOrNull?.code, FailureCode.invalidSecretKey);
      expect(secrets.values, isEmpty);
      expect(await repo.watchAccounts().first, isEmpty);
    });

    test('rejects empty labels and unsupported digits', () async {
      expect(
        (await repo.add(
          const NewOtpAccount(label: '  ', secret: _secret),
        )).failureOrNull?.detail,
        'Enter an account name.',
      );
      expect(
        (await repo.add(
          const NewOtpAccount(label: 'x', secret: _secret, digits: 7),
        )).isOk,
        isFalse,
      );
    });

    test('keystore failure is a typed failure and inserts no row', () async {
      secrets.failWrites = true;
      final r = await repo.add(
        const NewOtpAccount(label: 'x', secret: _secret),
      );
      expect(r.failureOrNull?.code, FailureCode.secretUnavailable);
      expect(await repo.watchAccounts().first, isEmpty);
    });

    test('accounts are listed in insertion order', () async {
      await add(const NewOtpAccount(label: 'b', secret: _secret));
      await add(const NewOtpAccount(label: 'a', secret: _secret));
      final list = await repo.watchAccounts().first;
      expect(list.map((a) => a.label), ['b', 'a']);
      expect(list.map((a) => a.sortOrder), [0, 1]);
    });

    test('rename updates label and clears a blank issuer', () async {
      final a = await add(
        const NewOtpAccount(label: 'x', issuer: 'Old', secret: _secret),
      );
      expect((await repo.rename(a.id, label: 'y', issuer: ' ')).isOk, isTrue);
      final back = (await repo.watchAccounts().first).single;
      expect(back.label, 'y');
      expect(back.issuer, isNull);
      expect(
        (await repo.rename('missing', label: 'z')).failureOrNull?.code,
        FailureCode.notFound,
      );
      expect(
        (await repo.rename(a.id, label: '')).failureOrNull?.code,
        FailureCode.invalidOtpUri,
      );
    });

    test('HOTP counter increments and persists', () async {
      final a = await add(
        const NewOtpAccount(
          label: 'h',
          secret: _secret,
          type: OtpType.hotp,
          counter: 5,
        ),
      );
      expect((await repo.incrementCounter(a.id)).valueOrNull, 6);
      expect((await repo.incrementCounter(a.id)).valueOrNull, 7);
      expect((await repo.watchAccounts().first).single.counter, 7);
      expect(
        (await repo.incrementCounter('nope')).failureOrNull?.code,
        FailureCode.notFound,
      );
    });

    test('recovery codes round-trip through secure storage', () async {
      final a = await add(const NewOtpAccount(label: 'x', secret: _secret));
      expect((await repo.readRecoveryCodes(a)).valueOrNull, isEmpty);
      const codes = [
        RecoveryCode('1111-2222'),
        RecoveryCode('3333', used: true),
      ];
      expect((await repo.saveRecoveryCodes(a, codes)).isOk, isTrue);
      expect((await repo.readRecoveryCodes(a)).valueOrNull, codes);
      final stored = secrets.values['otp.k0.recovery']!;
      expect(jsonDecode(stored), isA<List<dynamic>>());
      final dump = await db
          .customSelect('SELECT * FROM totp_accounts')
          .map((r) => r.data.values.join('|'))
          .get();
      expect(dump.single.contains('1111-2222'), isFalse);

      expect((await repo.saveRecoveryCodes(a, const [])).isOk, isTrue);
      expect(secrets.values.containsKey('otp.k0.recovery'), isFalse);
    });

    test('corrupt recovery data is a typed failure', () async {
      final a = await add(const NewOtpAccount(label: 'x', secret: _secret));
      secrets.values['otp.k0.recovery'] = '{not json';
      expect(
        (await repo.readRecoveryCodes(a)).failureOrNull?.code,
        FailureCode.secretUnavailable,
      );
    });

    test('remove wipes the row, the secret and the recovery codes', () async {
      final a = await add(const NewOtpAccount(label: 'x', secret: _secret));
      final b = await add(const NewOtpAccount(label: 'y', secret: _secret));
      await repo.saveRecoveryCodes(a, const [RecoveryCode('c')]);
      expect((await repo.remove(a.id)).isOk, isTrue);
      expect(secrets.values.keys, ['otp.k1']);
      expect((await repo.watchAccounts().first).single.id, b.id);
      expect(
        (await repo.remove(a.id)).failureOrNull?.code,
        FailureCode.notFound,
      );
    });

    test('remove keeps the row when the keystore fails', () async {
      final a = await add(const NewOtpAccount(label: 'x', secret: _secret));
      secrets.failDeletes = true;
      expect(
        (await repo.remove(a.id)).failureOrNull?.code,
        FailureCode.secretUnavailable,
      );
      expect(await repo.watchAccounts().first, hasLength(1));
    });

    test('missing or corrupt secret is secretUnavailable', () async {
      final a = await add(const NewOtpAccount(label: 'x', secret: _secret));
      secrets.values['otp.k0'] = '!!';
      expect(
        (await repo.readSecret(a)).failureOrNull?.code,
        FailureCode.secretUnavailable,
      );
      secrets.values.remove('otp.k0');
      expect(
        (await repo.readSecret(a)).failureOrNull?.code,
        FailureCode.secretUnavailable,
      );
    });

    test('purgeOrphanSecrets removes only unreferenced otp keys', () async {
      await add(const NewOtpAccount(label: 'x', secret: _secret));
      secrets.values
        ..['otp.orphan'] = _secret
        ..['otp.orphan.recovery'] = '[]'
        ..['otp.k0.recovery'] = '[]'
        ..['unrelated'] = 'keep';
      expect((await repo.purgeOrphanSecrets()).valueOrNull, 2);
      expect(secrets.values.keys.toSet(), {
        'otp.k0',
        'otp.k0.recovery',
        'unrelated',
      });
    });
  });
}
