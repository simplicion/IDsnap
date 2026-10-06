import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:engine_security/engine_security.dart';
import 'package:feature_qr/src/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cipher = const AesGcmVaultCrypto(
    pureDart: true,
    runInIsolate: false,
  ).fileCipher(VaultKey(id: 1, bytes: Uint8List(32)..[0] = 7));

  final state = QrHistoryState(
    includeSensitive: true,
    entries: [
      QrHistoryEntry(
        id: 'x',
        raw: 'WIFI:S:home;P:hunter2;;',
        symbology: CodeSymbology.qr,
        kind: CodeKind.wifi,
        summary: 'home',
        scannedAt: DateTime.utc(2026, 1, 2),
      ),
    ],
  );

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('qr_enc'));
  tearDown(() => dir.delete(recursive: true));

  test('history is encrypted at rest and reads back', () async {
    final store = JsonFileQrHistoryStore(
      File('${dir.path}/qr/history.json'),
      cipher: cipher,
    );
    await store.save(state);
    final raw = await store.file.readAsBytes();
    expect(cipher.isEncrypted(raw), isTrue);
    expect(latin1.decode(raw).contains('hunter2'), isFalse);
    expect((await store.load()).entries.single.raw, state.entries.single.raw);
  });

  test('a plaintext history from an older version is migrated', () async {
    final file = File('${dir.path}/history.json');
    await JsonFileQrHistoryStore(file).save(state); // Legacy, plaintext.
    expect(cipher.isEncrypted(await file.readAsBytes()), isFalse);
    final store = JsonFileQrHistoryStore(file, cipher: cipher);
    expect((await store.load()).entries.single.summary, 'home');
    expect(cipher.isEncrypted(await file.readAsBytes()), isTrue);
    expect((await store.load()).entries, hasLength(1));
  });
}
