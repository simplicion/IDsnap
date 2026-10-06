import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/signature/signature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Pdf extends Mock implements PdfEngine {}

class _Plain implements PlainFileAccess {
  final decrypted = <String>[];
  final released = <String>[];

  @override
  Future<String> decryptToTemp(String path, {String? fileName}) async {
    decrypted.add(path);
    return '/cache/view/plain.pdf';
  }

  @override
  Future<void> releaseTemp(
    String path, {
    Duration grace = Duration.zero,
  }) async => released.add(path);
}

Uint8List _png(int seed) => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List.filled(24, seed),
]);

void main() {
  group('SignatureBackupSection', () {
    late Directory tmp;
    late FileSignatureLibrary library;
    late SignatureBackupSection section;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sig_backup');
      library = FileSignatureLibrary('${tmp.path}/signatures');
      section = SignatureBackupSection(library);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'export → erase → restore brings signatures and default back',
      () async {
        await library.add(_png(1), width: 300, height: 100);
        final second = (await library.add(
          _png(2),
          width: 200,
          height: 80,
        )).valueOrNull!;
        await library.setDefault(second.id);

        final data = (await section.export())!;
        expect(data.count, 2);

        await section.erase();
        expect((await library.list()).valueOrNull, isEmpty);
        expect(await section.export(), isNull);

        expect(await section.restore(data.data, version: data.version), 2);
        final restored = (await library.list()).valueOrNull!;
        expect(restored, hasLength(2));
        final def = restored.singleWhere((s) => s.isDefault);
        expect((def.width, def.height), (200, 80));
        expect((await library.load(def.id)).valueOrNull, _png(2));

        // Idempotent, and junk is ignored.
        expect(await section.restore(data.data, version: 1), 0);
        expect(await section.restore('junk', version: 1), 0);
        expect((await library.list()).valueOrNull, hasLength(2));
      },
    );

    test('restore stops at the library capacity', () async {
      final items = [
        for (var i = 0; i < SignatureLibrary.capacity + 2; i++) _png(10 + i),
      ];
      final data = [
        for (final p in items)
          {'png': base64Encode(p), 'width': 10, 'height': 10},
      ];
      expect(
        await section.restore(data, version: 1),
        SignatureLibrary.capacity,
      );
    });
  });

  test(
    'vault PDF thumbnail renders a decrypted copy and shreds it (L-11)',
    () async {
      final pdf = _Pdf();
      final plain = _Plain();
      when(
        () => pdf.renderPage(
          any(),
          any(),
          targetWidth: any(named: 'targetWidth'),
        ),
      ).thenAnswer((_) async => Ok(Uint8List.fromList([1, 2, 3])));
      final container = ProviderContainer(
        overrides: [
          pdfEngineProvider.overrideWithValue(pdf),
          plainFileAccessProvider.overrideWithValue(plain),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        vaultPdfThumbProvider('/vault/documents/a.pdf'),
        (_, _) {},
      );
      final bytes = await container.read(
        vaultPdfThumbProvider('/vault/documents/a.pdf').future,
      );
      sub.close();
      expect(bytes, [1, 2, 3]);
      expect(plain.decrypted, ['/vault/documents/a.pdf']);
      // PDFium got the plaintext copy, never the ciphertext path.
      verify(
        () => pdf.renderPage('/cache/view/plain.pdf', 0, targetWidth: 320),
      ).called(1);
      expect(plain.released, ['/cache/view/plain.pdf']);
    },
  );

  test('the copy is shredded when rendering fails too', () async {
    final pdf = _Pdf();
    final plain = _Plain();
    when(
      () =>
          pdf.renderPage(any(), any(), targetWidth: any(named: 'targetWidth')),
    ).thenAnswer((_) async => const Err(AppFailure(FailureCode.corruptFile)));
    final container = ProviderContainer(
      overrides: [
        pdfEngineProvider.overrideWithValue(pdf),
        plainFileAccessProvider.overrideWithValue(plain),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(vaultPdfThumbProvider('/v/b.pdf'), (_, _) {});
    await expectLater(
      container.read(vaultPdfThumbProvider('/v/b.pdf').future),
      throwsA(isA<AppFailure>()),
    );
    sub.close();
    expect(plain.released, ['/cache/view/plain.pdf']);
  });
}
