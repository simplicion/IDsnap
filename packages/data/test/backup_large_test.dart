import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:engine_pdf/zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Own file so the process's peak RSS reflects only this test (audit H-05:
// the old export held 2–3× the vault in memory on the UI isolate).

void main() {
  test('a 300 MB vault exports and imports with bounded memory', () async {
    final tmp = await Directory.systemTemp.createTemp('docscan_large');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // Windows handle still closing.
      }
    });
    final data = await openDataLayer(
      rootOverride: p.join(tmp.path, 'a'),
      executor: NativeDatabase.memory(),
      archiveCodec: const ZipArchiveCodec(),
    );
    addTearDown(data.close);

    const mib = 1 << 20;
    const files = 6;
    const perFile = 50; // MiB → 300 MiB
    final block = Uint8List(mib);
    for (var f = 0; f < files; f++) {
      final rel = p.join('documents', 'big$f.jpg');
      final out = File(data.files.absolute(rel)).openSync(mode: FileMode.write);
      for (var i = 0; i < perFile; i++) {
        for (var k = 0; k < block.length; k += 4096) {
          block[k] = (i + k + f) & 0xFF;
        }
        block
          ..[0] = 0xFF
          ..[1] = 0xD8
          ..[2] = 0xFF;
        out.writeFromSync(block);
      }
      out.closeSync();
      final now = DateTime(2026);
      await data.documents.add(
        Document(
          id: newId(),
          name: 'Scan $f',
          format: DocumentFormat.jpeg,
          relativePath: rel,
          sizeBytes: perFile * mib,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final before = ProcessInfo.currentRss;
    final exported = await data.archiver.exportBackup(
      password: 'Large-Vault-1',
    );
    expect(exported.failureOrNull, isNull);
    final backup = exported.valueOrNull!;
    expect(backup.sizeBytes, greaterThan(files * perFile * mib));
    final afterExport = ProcessInfo.maxRss - before;

    final fresh = await openDataLayer(
      rootOverride: p.join(tmp.path, 'b'),
      executor: NativeDatabase.memory(),
      archiveCodec: const ZipArchiveCodec(),
    );
    addTearDown(fresh.close);
    final imported = await fresh.archiver.importBackup(
      backup.path,
      password: 'Large-Vault-1',
    );
    expect(imported.valueOrNull?.documents, files);
    final grown = ProcessInfo.maxRss - before;
    // Loading the vault whole would add ≥ 300 MiB (×2–3 before).
    expect(afterExport, lessThan(96 * mib), reason: 'export: $afterExport');
    expect(grown, lessThan(96 * mib), reason: 'export+import: $grown');
    final copy = (await fresh.documents.all()).first;
    expect(await fresh.files.size(copy.relativePath), perFile * mib);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
