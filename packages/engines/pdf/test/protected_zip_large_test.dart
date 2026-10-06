import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

// Own file so the test process's peak RSS reflects only this test.

void main() {
  test('streams a large file without loading it into memory', () async {
    final dir = await Directory.systemTemp.createTemp('zip_large');
    addTearDown(() => dir.delete(recursive: true));
    const mib = 1 << 20;
    const sizeMib = 96;
    final input = File('${dir.path}/video.mp4');
    final sink = input.openSync(mode: FileMode.write);
    final block = Uint8List(mib);
    for (var i = 0; i < sizeMib; i++) {
      block.fillRange(0, 16, i); // distinct blocks
      sink.writeFromSync(block);
    }
    sink.closeSync();

    final before = ProcessInfo.currentRss;
    final progress = <double>[];
    final out = '${dir.path}/big.zip';
    final r = await PdfEngineImpl().writeProtectedZip(
      [ZipSource(path: input.path, fileName: 'video.mp4')],
      'Large-File-1',
      outputPath: out,
      onProgress: progress.add,
    );
    expect(r.failureOrNull, isNull);
    // Stored (already-compressed type): 96 MiB + salt, verifier, MAC and
    // headers.
    expect(File(out).lengthSync(), greaterThan(sizeMib * mib));
    expect(progress, isNotEmpty);
    final grown = ProcessInfo.maxRss - before;
    // Loading the file whole would add ≥ 2 × 96 MiB (input + output).
    expect(grown, lessThan(64 * mib), reason: 'RSS grew by $grown bytes');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
