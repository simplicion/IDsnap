import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/kits/kit_catalog.dart';
import 'package:feature_tools/src/kits/kit_controller.dart';
import 'package:feature_tools/src/kits/kit_pipeline.dart';
import 'package:feature_tools/src/kits/kit_screen.dart';
import 'package:feature_tools/src/tools_screen.dart' show ToolSection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

class MockPipeline extends Mock implements KitPipeline {}

class MockFaces extends Mock implements FaceLocator {}

ApplicationKit kit(String id) => kitCatalog.firstWhere((k) => k.id == id);

Uint8List bytesOf(int n) => Uint8List(n);

void main() {
  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(kit('us-visa').items.first);
    registerFallbackValue(kit('exam-portal').items[1]);
    registerFallbackValue(kit('exam-portal').items[2]);
    registerFallbackValue(<({String path, DocumentFormat format})>[]);
    registerFallbackValue(PdfCompressionLevel.light);
    registerFallbackValue(doc('fallback'));
    registerFallbackValue(kit('us-visa').items.first as PhotoItem);
  });

  group('catalog', () {
    test('ids unique, limits positive, sources and review dates present', () {
      final ids = kitCatalog.map((k) => k.id).toSet();
      expect(ids.length, kitCatalog.length);
      expect(ids.contains(customKitId), isFalse);
      for (final k in kitCatalog) {
        expect(k.source.trim(), isNotEmpty, reason: k.id);
        expect(DateTime.tryParse(k.reviewedOn), isNotNull, reason: k.id);
        expect(k.items, isNotEmpty, reason: k.id);
        final itemIds = k.items.map((i) => i.id).toSet();
        expect(itemIds.length, k.items.length, reason: k.id);
        for (final item in k.items) {
          switch (item) {
            case PhotoItem():
              expect(item.maxBytes, greaterThan(0));
              expect(item.outputWidth, greaterThan(0));
              expect(item.outputHeight, greaterThan(0));
              if (item.minPx != null) {
                expect(item.outputWidth, greaterThanOrEqualTo(item.minPx!));
              }
              if (item.maxPx != null) {
                expect(item.outputWidth, lessThanOrEqualTo(item.maxPx!));
              }
            case SignatureItem():
              expect(item.maxBytes, greaterThan(0));
              expect(item.width * item.height, greaterThan(0));
            case DocumentItem():
              expect(item.maxBytes, greaterThan(0));
          }
        }
      }
    });

    test('kit labels are term-specific, never country names', () {
      final country = RegExp(
        r'\b(US|USA|U\.S|UK|India|Canada|Schengen|China|EU|Green Card)\b',
      );
      for (final k in kitCatalog) {
        final texts = [
          k.label,
          k.description,
          k.source,
          for (final i in k.items) i.label,
        ];
        for (final t in texts) {
          expect(country.hasMatch(t), isFalse, reason: t);
        }
      }
    });

    test('Square 2 × 2 in photo kit matches published limits', () {
      final photo = kit('us-visa').items.single as PhotoItem;
      expect((photo.outputWidth, photo.outputHeight), (600, 600));
      expect(photo.maxBytes, 240 * 1024);
      expect(constraintLabels(photo), containsAll(['≤ 240 KB', 'JPG']));
    });
  });

  group('KitPipeline', () {
    late Harness h;
    late KitPipeline pipeline;

    setUp(() {
      h = Harness();
      pipeline = KitPipeline(files: h.files, images: h.images, pdf: h.pdf);
    });

    test(
      'photo: crop to exact pixels, then compress with targetBytes',
      () async {
        final item = kit('us-visa').items.single as PhotoItem;
        when(() => h.images.inspect(any())).thenAnswer((i) async {
          final b = i.positionalArguments.first as Uint8List;
          return b.length == 8
              ? const Ok(ImageDetails(width: 3000, height: 4000, sizeBytes: 8))
              : Ok(ImageDetails(width: 600, height: 600, sizeBytes: b.length));
        });
        when(
          () => h.images.crop(
            any(),
            any(),
            outputWidth: any(named: 'outputWidth'),
            outputHeight: any(named: 'outputHeight'),
            quality: any(named: 'quality'),
          ),
        ).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: bytesOf(500 * 1024),
              width: 600,
              height: 600,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );
        when(() => h.images.compress(any(), any())).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: bytesOf(200 * 1024),
              width: 600,
              height: 600,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );

        final r = await pipeline.photo(item, '/in/photo.jpg');
        expect(r.failureOrNull, isNull);
        final out = r.valueOrNull!;
        expect(out.allPassed, isTrue);
        expect((out.width, out.height), (600, 600));

        final cropCall = verify(
          () => h.images.crop(
            any(),
            captureAny(),
            outputWidth: 600,
            outputHeight: 600,
            quality: any(named: 'quality'),
          ),
        )..called(1);
        final rect = cropCall.captured.single as NRect;
        // Square crop centered in a 3:4 portrait photo.
        expect(rect.width * 3000, closeTo(rect.height * 4000, 1));
        final options =
            verify(() => h.images.compress(any(), captureAny())).captured.single
                as ImageCompressionOptions;
        expect(options.targetBytes, 240 * 1024);
      },
    );

    test(
      'photo: auto-frames on the detected face for portrait presets',
      () async {
        final faces = MockFaces();
        when(
          () => faces.locateLargestFace(any()),
        ).thenAnswer((_) async => const Ok(NRect(0.1, 0.1, 0.2, 0.15)));
        pipeline = KitPipeline(
          files: h.files,
          images: h.images,
          pdf: h.pdf,
          faces: faces,
        );
        when(() => h.images.inspect(any())).thenAnswer(
          (_) async =>
              const Ok(ImageDetails(width: 3000, height: 4000, sizeBytes: 8)),
        );
        when(
          () => h.images.crop(
            any(),
            any(),
            outputWidth: any(named: 'outputWidth'),
            outputHeight: any(named: 'outputHeight'),
            quality: any(named: 'quality'),
          ),
        ).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: bytesOf(10),
              width: 600,
              height: 600,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );
        when(() => h.images.compress(any(), any())).thenAnswer(
          (_) async => Ok(
            EncodedImage(
              bytes: bytesOf(10),
              width: 600,
              height: 600,
              format: ImageOutputFormat.jpeg,
            ),
          ),
        );
        await pipeline.photo(
          kit('us-visa').items.single as PhotoItem,
          '/in/p.jpg',
        );
        final rect =
            verify(
                  () => h.images.crop(
                    any(),
                    captureAny(),
                    outputWidth: any(named: 'outputWidth'),
                    outputHeight: any(named: 'outputHeight'),
                    quality: any(named: 'quality'),
                  ),
                ).captured.single
                as NRect;
        // Face center x = 0.2 → crop must be pulled toward the left side.
        expect(rect.left + rect.width / 2, lessThan(0.4));
      },
    );

    DocumentItem examDocs() => kit('exam-portal').items[2] as DocumentItem;

    void stubMergedPdf(int size) {
      when(() => h.pdf.merge(any())).thenAnswer((_) async => Ok(bytesOf(size)));
      when(
        () => h.files.writeTemp(any(), any()),
      ).thenAnswer((_) async => '/tmp/merged.pdf');
      when(() => h.files.delete(any())).thenAnswer((_) async {});
      when(() => h.pdf.pageCount(any())).thenAnswer((_) async => const Ok(3));
    }

    test(
      'document: escalates compression and refuses when unreachable',
      () async {
        stubMergedPdf(900 * 1024);
        when(
          () => h.pdf.compress(any(), any()),
        ).thenAnswer((_) async => Ok(bytesOf(400 * 1024)));

        final r = await pipeline.document(examDocs(), [
          (path: '/a.pdf', format: DocumentFormat.pdf),
          (path: '/b.pdf', format: DocumentFormat.pdf),
        ]);
        final failure = r.failureOrNull!;
        expect(failure.code, FailureCode.targetSizeUnreachable);
        expect(
          failure.recovery,
          "Can't reach 300 KB without making text unreadable. Try fewer pages.",
        );
        verifyInOrder([
          () => h.pdf.compress(any(), PdfCompressionLevel.light),
          () => h.pdf.compress(any(), PdfCompressionLevel.recommended),
          () => h.pdf.compress(any(), PdfCompressionLevel.strong),
        ]);
        verify(() => h.files.delete('/tmp/merged.pdf')).called(1);
      },
    );

    test('document: stops at the first level that fits', () async {
      stubMergedPdf(900 * 1024);
      when(
        () => h.pdf.compress(any(), PdfCompressionLevel.light),
      ).thenAnswer((_) async => Ok(bytesOf(500 * 1024)));
      when(
        () => h.pdf.compress(any(), PdfCompressionLevel.recommended),
      ).thenAnswer((_) async => Ok(bytesOf(250 * 1024)));

      final r = await pipeline.document(examDocs(), [
        (path: '/a.pdf', format: DocumentFormat.pdf),
        (path: '/b.pdf', format: DocumentFormat.pdf),
      ]);
      final out = r.valueOrNull!;
      expect(out.compressedPdf, isTrue);
      expect(out.bytes.length, 250 * 1024);
      expect(out.allPassed, isTrue);
      verifyNever(() => h.pdf.compress(any(), PdfCompressionLevel.strong));
    });

    test('document: too many pages is a clear notice, not an error', () async {
      stubMergedPdf(10);
      when(() => h.pdf.pageCount(any())).thenAnswer((_) async => const Ok(14));
      final r = await pipeline.document(examDocs(), [
        (path: '/a.pdf', format: DocumentFormat.pdf),
        (path: '/b.pdf', format: DocumentFormat.pdf),
      ]);
      expect(
        (r.failureOrNull! as NoticeFailure).message,
        contains('up to 10 pages; you selected 14'),
      );
    });
  });

  group('KitController.saveAll', () {
    late Harness h;
    late MockPipeline pipeline;
    late ProviderContainer container;

    KitOutput output(DocumentFormat f) => KitOutput(
      bytes: bytesOf(10),
      format: f,
      pageCount: f == DocumentFormat.pdf ? 2 : null,
      checks: const [KitCheck('ok', passed: true)],
    );

    setUp(() {
      h = Harness();
      pipeline = MockPipeline();
      when(
        () => pipeline.photo(any(), any()),
      ).thenAnswer((_) async => Ok(output(DocumentFormat.jpeg)));
      when(
        () => pipeline.signature(any(), any()),
      ).thenAnswer((_) async => Ok(output(DocumentFormat.jpeg)));
      when(
        () => pipeline.document(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Ok(output(DocumentFormat.pdf)));
      when(() => h.repo.update(any())).thenAnswer((_) async => const Ok(null));
      when(() => h.repo.remove(any())).thenAnswer((_) async => const Ok(null));
      when(() => h.files.delete(any())).thenAnswer((_) async {});
      container = ProviderContainer(
        overrides: [
          ...h.overrides,
          kitPipelineProvider.overrideWithValue(pipeline),
          folderRepositoryProvider.overrideWithValue(familyFolders),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<KitController> prepareExam() async {
      final sub = container.listen(
        kitControllerProvider('exam-portal'),
        (_, _) {},
      );
      addTearDown(sub.close);
      final c = container.read(kitControllerProvider('exam-portal').notifier);
      final exam = kit('exam-portal');
      const file = PickedFile(path: '/p.jpg', name: 'p.jpg');
      await c.processPhoto(exam.items[0] as PhotoItem, file);
      await c.processSignature(exam.items[1] as SignatureItem, file);
      await c.processDocuments(exam.items[2] as DocumentItem, [
        const PickedFile(path: '/d.pdf', name: 'd.pdf'),
      ]);
      return c;
    }

    test('commits every item (no legacy category), then succeeds', () async {
      var n = 0;
      when(() => h.commit(any())).thenAnswer(
        (_) async => Ok(doc('d${n++}', format: DocumentFormat.jpeg)),
      );
      final c = await prepareExam();
      expect(
        container.read(kitControllerProvider('exam-portal')).readyIds,
        hasLength(3),
      );

      await c.saveAll();
      final save = container.read(kitControllerProvider('exam-portal')).save;
      expect(save, isA<KitSaved>());
      final docs = (save as KitSaved).documents;
      expect(docs, hasLength(3));
      expect(docs.every((d) => d.category == null), isTrue);
      final outs = verify(
        () => h.commit(captureAny()),
      ).captured.cast<OutputFile>();
      expect(outs, hasLength(3));
      expect(outs.last.format, DocumentFormat.pdf);
      expect(outs.last.expectedPages, 2);
      expect(outs.first.suggestedName, 'Exam/portal upload kit · Photograph');
      verifyNever(() => h.repo.update(any()));
    });

    test('"Save all" commits every item into the chosen folder', () async {
      var n = 0;
      when(() => h.commit(any(), folderId: any(named: 'folderId'))).thenAnswer(
        (_) async => Ok(doc('d${n++}', format: DocumentFormat.jpeg)),
      );
      container
          .read(saveFolderProvider(kitSaveFlow('exam-portal')).notifier)
          .choose('fam');
      final c = await prepareExam();
      await c.saveAll();
      expect(
        container.read(kitControllerProvider('exam-portal')).save,
        isA<KitSaved>(),
      );
      verify(() => h.commit(any(), folderId: 'fam')).called(3);
    });

    test(
      'a failed commit rolls back earlier items and reports failure',
      () async {
        var n = 0;
        when(() => h.commit(any())).thenAnswer((_) async {
          n++;
          return n == 2
              ? const Err(AppFailure(FailureCode.outputValidationFailed))
              : Ok(doc('d$n', format: DocumentFormat.jpeg));
        });
        final c = await prepareExam();
        await c.saveAll();
        final save = container.read(kitControllerProvider('exam-portal')).save;
        expect(save, isA<KitSaveFailed>());
        expect(
          (save as KitSaveFailed).failure.code,
          FailureCode.outputValidationFailed,
        );
        verify(() => h.repo.remove('d1')).called(1);
        verify(() => h.files.delete('documents/d1.jpg')).called(1);
      },
    );

    test('pipeline notices surface as item notices, not failures', () async {
      when(
        () => pipeline.document(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const Err(NoticeFailure('Too big')));
      final sub = container.listen(
        kitControllerProvider('exam-portal'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container
          .read(kitControllerProvider('exam-portal').notifier)
          .processDocuments(kit('exam-portal').items[2] as DocumentItem, [
            const PickedFile(path: '/d.pdf', name: 'd.pdf'),
          ]);
      final s = container
          .read(kitControllerProvider('exam-portal'))
          .of('documents');
      expect(s, isA<KitItemNotice>());
    });
  });

  group('screens', () {
    testWidgets('kit screen shows each item with its constraint chips', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, const KitScreen(kitId: 'exam-portal'));
      expect(find.text('Step 1 · Photograph'), findsOneWidget);
      expect(find.text('Step 2 · Signature'), findsOneWidget);
      expect(find.text('Step 3 · Certificates / marksheets'), findsOneWidget);
      expect(find.text('≤ 50 KB'), findsOneWidget);
      expect(find.text('280×120 px'), findsOneWidget);
      expect(find.text('≤ 300 KB'), findsOneWidget);
      expect(
        find.text('Check the latest official requirements'),
        findsOneWidget,
      );
      expect(find.textContaining('Last reviewed: 2026-09-01'), findsOneWidget);
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNull, reason: 'nothing prepared yet');
    });

    testWidgets('unknown kit shows a friendly empty state', (tester) async {
      final h = Harness();
      await h.pump(tester, const KitScreen(kitId: 'nope'));
      expect(find.text('Kit not found'), findsOneWidget);
    });

    testWidgets('Tools → kits hub → kit via the router', (tester) async {
      final h = Harness();
      final rootKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: rootKey,
        initialLocation: Routes.tools,
        routes: [
          GoRoute(
            path: Routes.tools,
            builder: (_, _) => const ToolsScreen(),
            routes: toolRoutes(rootKey),
          ),
        ],
      );
      tester.view
        ..physicalSize = const Size(1200, 4000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(ToolSection.kits.title), findsOneWidget);
      await tester.tap(find.text('Photo, exam & job kits'));
      await tester.pumpAndSettle();
      expect(find.text('Application kits'), findsOneWidget);
      expect(find.text('Custom kit'), findsOneWidget);
      await tester.tap(find.text('Square photo (2 × 2 in)'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 · Square photo'), findsOneWidget);
      expect(find.text('≤ 240 KB'), findsOneWidget);
    });
  });
}
