import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

class _Keys implements VaultKeyStore {
  VaultKey? key;

  @override
  Future<VaultKey> create() async => key = VaultKey(
    id: 1,
    bytes: Uint8List.fromList(List.generate(32, (i) => 200 - i)),
  );

  @override
  Future<void> delete() async => key = null;

  @override
  Future<VaultKey?> read() async => key;
}

/// The encrypted vault with the REAL PDF engine: outputs are committed as
/// ciphertext, thumbnails still render, and PDFium opens the decrypted
/// cache copy (ADR-0010).
void main() {
  setUpAll(pdfrxInitialize);

  test('commit → encrypted on disk → view through a decrypted copy', () async {
    final root = await Directory.systemTemp.createTemp('docscan_enc_e2e');
    final data = await openDataLayer(
      rootOverride: '${root.path}/vault',
      cacheOverride: '${root.path}/cache',
      executor: NativeDatabase.memory(),
      security: VaultSecurity(
        keys: _Keys(),
        crypto: const AesGcmVaultCrypto(pureDart: true, runInIsolate: false),
      ),
    );
    addTearDown(() async {
      await data.close();
      await root.delete(recursive: true);
    });
    final pdf = PdfEngineImpl();
    const images = ImagingEngine();
    final commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: pdf,
      images: images,
    );

    final bytes = (await pdf.fromText(
      'Passport number X1234567\nSecond line',
      const TextPdfOptions(),
    )).valueOrNull!;
    final doc = (await commit(
      OutputFile(
        bytes: bytes,
        format: DocumentFormat.pdf,
        suggestedName: 'Passport',
      ),
    )).valueOrNull!;

    final stored = File(data.files.absolute(doc.relativePath));
    expect(VaultFormat.isEncrypted(stored.readAsBytesSync()), isTrue);
    // PDFium can't open the ciphertext by path…
    expect((await pdf.pageCount(stored.path)).isOk, isFalse);
    // …the thumbnail was rendered before encryption and is encrypted too…
    final thumb = File(data.files.absolute(doc.thumbnailPath!));
    expect(VaultFormat.isEncrypted(thumb.readAsBytesSync()), isTrue);
    expect(
      (await data.files.read(doc.thumbnailPath!)).length,
      greaterThan(100),
    );
    // …and readers get plaintext through the store.
    expect(await data.files.read(doc.relativePath), bytes);
    final plain = await data.files.decryptToTemp(doc.relativePath);
    expect((await pdf.pageCount(plain)).valueOrNull, doc.pageCount);
    await data.files.releaseTemp(plain);
    expect(File(plain).existsSync(), isFalse);

    // No plaintext work file is left in the cache after the commit.
    final leftovers = Directory(
      '${root.path}/cache',
    ).listSync(recursive: true).whereType<File>();
    expect(leftovers, isEmpty);
  });
}
