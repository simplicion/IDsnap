import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:engine_security/src/vault/vault_format.dart';
import 'package:flutter_test/flutter_test.dart';

VaultKey _key([int seed = 1, int id = 1]) => VaultKey(
  id: id,
  bytes: Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 7 + seed) & 255),
  ),
);

Uint8List _bytes(int n, [int seed = 3]) {
  final r = Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/// 4 KiB chunks so multi-chunk cases stay small.
final _small = VaultStreamCipher(DartAesGcm.with256bits(), chunkLog2: 12);
const _chunk = 4096;
const _per = _chunk + VaultFormat.tagLength;

Future<Uint8List> _enc(Uint8List plain, [VaultKey? key]) async {
  final out = BytesBuilder();
  await _small.encrypt(key ?? _key(), MemorySource(plain), (b) async {
    out.add(b);
  });
  return out.takeBytes();
}

Future<Uint8List> _dec(Uint8List sealed, [VaultKey? key]) async {
  final out = BytesBuilder();
  await _small.decrypt(key ?? _key(), MemorySource(sealed), (b) async {
    out.add(b);
  });
  return out.takeBytes();
}

final _fails = throwsA(isA<VaultIntegrityException>());

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};
  bool failReads = false;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('keystore locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  group('IDSV format', () {
    for (final n in [0, 1, _chunk - 1, _chunk, _chunk + 1, 3 * _chunk, 20000]) {
      test('round trip $n bytes', () async {
        final plain = _bytes(n);
        final sealed = await _enc(plain);
        expect(VaultFormat.isEncrypted(sealed), isTrue);
        final chunks = n == 0 ? 1 : (n + _chunk - 1) ~/ _chunk;
        expect(
          sealed.length,
          VaultFormat.headerLength + n + chunks * VaultFormat.tagLength,
        );
        expect(await _dec(sealed), plain);
      });
    }

    test(
      'same plaintext encrypts differently (fresh file key + nonces)',
      () async {
        final plain = _bytes(100);
        expect(await _enc(plain), isNot(await _enc(plain)));
      },
    );

    test('a flipped bit in any chunk fails that chunk', () async {
      final sealed = await _enc(_bytes(3 * _chunk + 10));
      for (final offset in [
        VaultFormat.headerLength, // chunk 0 data
        VaultFormat.headerLength + _chunk + 3, // chunk 0 tag
        VaultFormat.headerLength + _per + 100, // chunk 1
        VaultFormat.headerLength + 2 * _per + 5, // chunk 2
        sealed.length - 1, // last chunk tag
      ]) {
        final bad = Uint8List.fromList(sealed);
        bad[offset] ^= 0x01;
        await expectLater(_dec(bad), _fails, reason: 'offset $offset');
      }
    });

    test('any header change is detected', () async {
      final sealed = await _enc(_bytes(5000));
      for (var offset = 8; offset < VaultFormat.headerLength; offset++) {
        final bad = Uint8List.fromList(sealed);
        bad[offset] ^= 0x80;
        await expectLater(_dec(bad), _fails, reason: 'offset $offset');
      }
    });

    test('truncation at a chunk boundary is detected', () async {
      final sealed = await _enc(_bytes(3 * _chunk));
      final cut = Uint8List.sublistView(
        sealed,
        0,
        VaultFormat.headerLength + 2 * _per,
      );
      await expectLater(_dec(Uint8List.fromList(cut)), _fails);
    });

    test('truncation inside a chunk, a missing body and appended bytes '
        'are detected', () async {
      final sealed = await _enc(_bytes(2 * _chunk + 50));
      await expectLater(
        _dec(Uint8List.sublistView(sealed, 0, sealed.length - 7)),
        _fails,
      );
      await expectLater(
        _dec(Uint8List.sublistView(sealed, 0, VaultFormat.headerLength)),
        _fails,
      );
      await expectLater(_dec(Uint8List.fromList([...sealed, 0, 0, 0])), _fails);
    });

    test('reordered chunks are detected', () async {
      final sealed = await _enc(_bytes(3 * _chunk));
      const h = VaultFormat.headerLength;
      final swapped = Uint8List.fromList(sealed)
        ..setRange(h, h + _per, sealed.sublist(h + _per, h + 2 * _per))
        ..setRange(h + _per, h + 2 * _per, sealed.sublist(h, h + _per));
      await expectLater(_dec(swapped), _fails);
    });

    test('the wrong key or key id is rejected', () async {
      final sealed = await _enc(_bytes(100));
      await expectLater(_dec(sealed, _key(2)), _fails);
      await expectLater(_dec(sealed, _key(1, 2)), _fails);
    });

    test('plain documents are never mistaken for vault files', () {
      expect(VaultFormat.isEncrypted('%PDF-1.7'.codeUnits), isFalse);
      expect(VaultFormat.isEncrypted([0xFF, 0xD8, 0xFF, 0xE0]), isFalse);
      expect(VaultFormat.isEncrypted('SQLite format 3\x00'.codeUnits), isFalse);
      expect(VaultFormat.isEncrypted(const []), isFalse);
    });

    test('plaintextLength matches the default chunk size', () {
      const c = 1 << VaultFormat.defaultChunkLog2;
      for (final n in [0, 1, c, c + 1, 3 * c + 7]) {
        final chunks = n == 0 ? 1 : (n + c - 1) ~/ c;
        final len = VaultFormat.headerLength + n + chunks * 16;
        expect(VaultFormat.plaintextLength(len), n, reason: '$n');
      }
    });
  });

  group('VaultFileCipher', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vault_cipher'));
    tearDown(() => dir.deleteSync(recursive: true));

    String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

    test('file round trip across several default-size chunks', () async {
      final cipher = VaultFileCipher(_key(), aes: DartAesGcm.with256bits());
      final plain = _bytes(600 * 1024);
      File(path('a.pdf')).writeAsBytesSync(plain);
      await cipher.encryptFile(path('a.pdf'), path('a.enc'));
      final sealed = File(path('a.enc')).readAsBytesSync();
      expect(cipher.isEncrypted(sealed), isTrue);
      expect(cipher.plaintextLength(sealed.length), plain.length);
      await cipher.decryptFile(path('a.enc'), path('a.out'));
      expect(File(path('a.out')).readAsBytesSync(), plain);
      expect(await cipher.decryptFileToBytes(path('a.enc')), plain);
      expect(
        await cipher.decryptBytes(await cipher.encryptBytes(plain)),
        plain,
      );
      expect(File(path('a.enc.part')).existsSync(), isFalse);
    });

    test('runs in a background isolate', () async {
      final cipher = VaultFileCipher(_key());
      final plain = _bytes(70000);
      File(path('b.bin')).writeAsBytesSync(plain);
      await cipher.encryptFile(path('b.bin'), path('b.enc'));
      expect(await cipher.decryptFileToBytes(path('b.enc')), plain);
    });

    test('a failed decrypt leaves no output behind', () async {
      final cipher = VaultFileCipher(_key(), aes: DartAesGcm.with256bits());
      File(path('c.bin')).writeAsBytesSync(_bytes(1000));
      await cipher.encryptFile(path('c.bin'), path('c.enc'));
      final bad = File(path('c.enc')).readAsBytesSync();
      bad[bad.length - 3] ^= 1;
      File(path('c.enc')).writeAsBytesSync(bad);
      await expectLater(
        cipher.decryptFile(path('c.enc'), path('c.out')),
        _fails,
      );
      expect(File(path('c.out')).existsSync(), isFalse);
      expect(File(path('c.out.part')).existsSync(), isFalse);
    });
  });

  group('AesGcmVaultCrypto', () {
    const crypto = AesGcmVaultCrypto(pureDart: true, runInIsolate: false);

    test('subkeys are deterministic and separated by purpose', () async {
      final a = await crypto.deriveKey(_key(), 'sqlcipher/v1');
      expect(a, hasLength(32));
      expect(await crypto.deriveKey(_key(), 'sqlcipher/v1'), a);
      expect(await crypto.deriveKey(_key(), 'other'), isNot(a));
      expect(await crypto.deriveKey(_key(9), 'sqlcipher/v1'), isNot(a));
    });

    test('key check is a short fingerprint that differs per key', () async {
      final kcv = await crypto.keyCheck(_key());
      expect(kcv, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(await crypto.keyCheck(_key()), kcv);
      expect(await crypto.keyCheck(_key(5)), isNot(kcv));
    });

    test('the key never shows up in toString', () {
      expect(_key().toString(), 'VaultKey(id: 1)');
    });
  });

  group('SecureStorageVaultKeyStore', () {
    test('create stores a 256-bit key that reads back', () async {
      final secrets = _MemorySecrets();
      final store = SecureStorageVaultKeyStore(secrets);
      expect(await store.read(), isNull);
      final key = await store.create();
      expect(key.bytes, hasLength(32));
      expect((await store.read())!.bytes, key.bytes);
      expect(secrets.values.keys, [SecureStorageVaultKeyStore.storageKey]);
      final other = await SecureStorageVaultKeyStore(_MemorySecrets()).create();
      expect(other.bytes, isNot(key.bytes));
    });

    test('a corrupt or unreadable entry fails closed', () async {
      final secrets = _MemorySecrets()
        ..values[SecureStorageVaultKeyStore.storageKey] = '{"v":1,"key":"x"}';
      final store = SecureStorageVaultKeyStore(secrets);
      await expectLater(
        store.read(),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.secretUnavailable,
          ),
        ),
      );
      secrets.failReads = true;
      await expectLater(store.read(), throwsA(isA<AppFailure>()));
    });

    test('delete removes the key', () async {
      final store = SecureStorageVaultKeyStore(_MemorySecrets());
      await store.create();
      await store.delete();
      expect(await store.read(), isNull);
    });
  });
}
