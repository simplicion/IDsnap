import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_ocr/engine_ocr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockImages extends Mock implements ImageProcessor {}

class _Files implements FileStore {
  final data = <String, Uint8List>{};
  var _n = 0;

  @override
  Future<Uint8List> read(String absolutePath) async {
    final d = data[absolutePath];
    if (d == null) throw StateError('missing');
    return d;
  }

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async {
    final p = 'tmp${_n++}.$extension';
    data[p] = bytes;
    return p;
  }

  @override
  Future<void> delete(String absoluteOrRelativePath) async =>
      data.remove(absoluteOrRelativePath);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal JPEG: SOI + APP1 Exif (TIFF, one IFD entry) + EOI.
Uint8List _jpegWithOrientation(int orientation, {bool little = true}) {
  List<int> u16(int v) => little ? [v & 0xFF, v >> 8] : [v >> 8, v & 0xFF];
  List<int> u32(int v) => little
      ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]
      : [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  final tiff = <int>[
    ...(little ? [0x49, 0x49] : [0x4D, 0x4D]),
    ...u16(42),
    ...u32(8),
    ...u16(1),
    ...u16(0x0112),
    ...u16(3),
    ...u32(1),
    ...u16(orientation),
    0,
    0,
    ...u32(0),
  ];
  final app1 = [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  final len = app1.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    len >> 8,
    len & 0xFF,
    ...app1,
    0xFF,
    0xD9,
  ]);
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const ImageCompressionOptions());
    registerFallbackValue(NRect.full);
    registerFallbackValue(const PageEdits());
    registerFallbackValue(QualityPreset.balanced);
  });

  group('exifOrientation', () {
    test('reads the tag in both byte orders', () {
      expect(exifOrientation(_jpegWithOrientation(6)), 6);
      expect(exifOrientation(_jpegWithOrientation(3, little: false)), 3);
    });

    test('defaults to 1 for non-JPEG, truncated or odd data', () {
      expect(exifOrientation(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), 1);
      expect(exifOrientation(Uint8List.fromList([0xFF, 0xD8])), 1);
      final cut = _jpegWithOrientation(6);
      expect(exifOrientation(Uint8List.sublistView(cut, 0, 20)), 1);
      expect(exifOrientation(_jpegWithOrientation(42)), 1);
    });
  });

  group('ImagingOcrPreparer', () {
    late _MockImages images;
    late _Files files;
    late ImagingOcrPreparer prep;

    setUp(() {
      images = _MockImages();
      files = _Files();
      prep = ImagingOcrPreparer(images: images, files: files);
    });

    test('upright, reasonably sized images are used as is', () async {
      files.data['in.png'] = Uint8List.fromList([1, 2, 3]);
      when(() => images.inspect(any())).thenAnswer(
        (_) async =>
            const Ok(ImageDetails(width: 1200, height: 1600, sizeBytes: 3)),
      );
      final r = (await prep.normalize('in.png')).valueOrNull!;
      expect(r.path, 'in.png');
      expect(r.temporary, isFalse);
      verifyNever(() => images.compress(any(), any()));
      await prep.release(r);
      expect(files.data, contains('in.png'));
    });

    test(
      'EXIF-rotated or huge images are re-encoded upright and capped',
      () async {
        files.data['in.jpg'] = _jpegWithOrientation(6);
        when(() => images.inspect(any())).thenAnswer(
          (_) async =>
              const Ok(ImageDetails(width: 4000, height: 3000, sizeBytes: 9)),
        );
        when(() => images.compress(any(), any())).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: Uint8List.fromList([9]),
              width: 3000,
              height: 4000,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );
        final r = (await prep.normalize('in.jpg')).valueOrNull!;
        expect(r.temporary, isTrue);
        expect((r.width, r.height), (3000, 4000));
        final opts =
            verify(() => images.compress(any(), captureAny())).captured.single
                as ImageCompressionOptions;
        expect(opts.maxDimension, 4096);
        await prep.release(r);
        expect(files.data.keys, ['in.jpg']);
      },
    );

    test('missing and empty files map to typed failures', () async {
      expect(
        (await prep.normalize('nope.jpg')).failureOrNull?.code,
        FailureCode.notFound,
      );
      files.data['empty.jpg'] = Uint8List(0);
      expect(
        (await prep.normalize('empty.jpg')).failureOrNull?.code,
        FailureCode.emptyFile,
      );
    });

    test('decode failures are passed through typed', () async {
      files.data['x.heic'] = Uint8List.fromList([1]);
      when(() => images.inspect(any())).thenAnswer(
        (_) async => const Err(AppFailure(FailureCode.unsupportedFormat)),
      );
      when(() => images.compress(any(), any())).thenAnswer(
        (_) async => const Err(AppFailure(FailureCode.unsupportedFormat)),
      );
      expect(
        (await prep.normalize('x.heic')).failureOrNull?.code,
        FailureCode.unsupportedFormat,
      );
    });

    test(
      'rotation + scale variant goes through crop on the rotated width',
      () async {
        files.data['base.jpg'] = Uint8List.fromList([1]);
        when(
          () => images.crop(
            any(),
            any(),
            outputWidth: any(named: 'outputWidth'),
            quarterTurns: any(named: 'quarterTurns'),
            quality: any(named: 'quality'),
          ),
        ).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: Uint8List.fromList([2]),
              width: 2000,
              height: 1500,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );
        final r = await prep.variant(
          const OcrImage(path: 'base.jpg', width: 750, height: 1000),
          const OcrVariant(quarterTurns: 1, scale: 2),
        );
        expect(r.valueOrNull!.width, 2000);
        verify(
          () => images.crop(
            any(),
            NRect.full,
            outputWidth: 2000,
            quarterTurns: 1,
          ),
        ).called(1);
      },
    );

    test('enhanced variant uses the Auto enhance render', () async {
      files.data['base.jpg'] = Uint8List.fromList([1]);
      when(
        () => images.renderPage(any(), any(), preset: any(named: 'preset')),
      ).thenAnswer((_) async => Ok(Uint8List.fromList([3])));
      when(() => images.inspect(any())).thenAnswer(
        (_) async =>
            const Ok(ImageDetails(width: 1000, height: 800, sizeBytes: 1)),
      );
      final r = await prep.variant(
        const OcrImage(path: 'base.jpg', width: 800, height: 1000),
        const OcrVariant(quarterTurns: 3, enhance: true),
      );
      expect(r.valueOrNull!.width, 1000);
      final edits =
          verify(
                () => images.renderPage(
                  any(),
                  captureAny(),
                  preset: any(named: 'preset'),
                ),
              ).captured.single
              as PageEdits;
      expect(edits.filter, EnhancementFilter.enhanced);
      expect(edits.quarterTurns, 3);
    });
  });
}
