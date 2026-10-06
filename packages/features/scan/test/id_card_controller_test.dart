import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'id_card_fakes.dart';

void main() {
  late IdCardFakes fakes;
  late ProviderContainer container;

  IdCardFlowController flow() => container.read(idCardFlowProvider.notifier);
  IdCardFlowState state() => container.read(idCardFlowProvider);

  setUp(() {
    fakes = IdCardFakes();
    container = ProviderContainer(overrides: fakes.overrides)
      ..listen(idCardFlowProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('front → back → preview with the platform scanner', () async {
    fakes.scanner.next = const Ok(['/cache/front.jpg']);
    expect(state().step, IdCardStep.front);
    expect(await flow().captureWithCamera(IdSide.front), isNull);
    expect(state().step, IdCardStep.back);
    expect(state().front, isNotNull);
    // Platform scans are already cropped: no detection, no quad.
    expect(fakes.cardImages.renders.single.quad, isNull);
    expect(fakes.cardImages.renders.single.filter, EnhancementFilter.enhanced);

    fakes.scanner.next = const Ok(['/cache/back.jpg']);
    expect(await flow().captureWithCamera(IdSide.back), isNull);
    expect(state().step, IdCardStep.preview);
    expect(state().canSave, isTrue);
    expect(fakes.files.imported, ['/cache/front.jpg', '/cache/back.jpg']);
  });

  test('cancelled scan is a silent no-op', () async {
    fakes.scanner.next = const Err(AppFailure(FailureCode.captureCancelled));
    expect(await flow().captureWithCamera(IdSide.front), isNull);
    expect(state().step, IdCardStep.front);
    expect(state().front, isNull);
    expect(state().busy, isNull);
  });

  test('scanner errors are returned as typed failures', () async {
    fakes.scanner.next = const Err(AppFailure(FailureCode.cameraUnavailable));
    final f = await flow().captureWithCamera(IdSide.front);
    expect(f?.code, FailureCode.cameraUnavailable);
    expect(state().busy, isNull);
  });

  test(
    'gallery photo runs detection; unsure detection flags the side',
    () async {
      fakes.cardImages.detection = const Ok(DetectedQuad(Quad.full, 0.3));
      await flow().captureFromPhotos(IdSide.front);
      final front = state().front!;
      expect(front.lowConfidence, isTrue);
      expect(front.needsCheck, isTrue);
    },
  );

  test('non card-shaped render asks to check corners', () async {
    fakes.cardImages
      ..renderWidth = 1000
      ..renderHeight = 1000;
    await flow().captureWithCamera(IdSide.front);
    expect(state().front!.needsCheck, isTrue);
  });

  test('retake returns to that step and keeps the other side', () async {
    await flow().captureWithCamera(IdSide.front);
    await flow().captureWithCamera(IdSide.back);
    flow().retake(IdSide.front);
    expect(state().step, IdCardStep.front);
    expect(state().back, isNotNull);
    await flow().captureWithCamera(IdSide.front);
    // Back already present → straight to preview.
    expect(state().step, IdCardStep.preview);
    // The replaced front original is deleted.
    expect(fakes.files.deleted, contains('/app/originals/0.jpg'));
  });

  test('setQuad re-renders the side with the new corners', () async {
    await flow().captureWithCamera(IdSide.front);
    const q = Quad(
      NPoint(0.1, 0.1),
      NPoint(0.9, 0.1),
      NPoint(0.9, 0.8),
      NPoint(0.1, 0.8),
    );
    expect(await flow().setQuad(IdSide.front, q), isNull);
    expect(fakes.cardImages.renders.last.quad, q);
    expect(state().front!.quad, q);
  });

  group('save', () {
    Future<void> captureBoth() async {
      await flow().captureWithCamera(IdSide.front);
      await flow().captureWithCamera(IdSide.back);
    }

    test('builds 2-image sheet, commits 1 page, no legacy category', () async {
      flow().start(slot: 'driving_licence');
      await captureBoth();
      flow()
        ..setWatermark(enabled: true)
        ..setPurpose('bank KYC');
      await flow().save(now: DateTime(2026, 9, 25));

      final (images, w, h, mark) = fakes.sheet.calls.single;
      expect(images, hasLength(2));
      expect(w, PdfPageSize.a4.widthPt);
      expect(h, PdfPageSize.a4.heightPt);
      expect(mark, 'COPY — for bank KYC only');

      final out = fakes.commit.outputs.single;
      expect(out.expectedPages, 1);
      expect(out.format, DocumentFormat.pdf);
      expect(out.suggestedName, 'ID card — 2026-09-25');
      // Nothing is filed under the old hard-coded categories any more.
      expect(fakes.recordingRepo.updates, isEmpty);
      expect(fakes.commit.folderIds.single, isNull);
      expect(state().save, isA<IdCardSaved>());
      // Originals cleaned up after a successful save.
      expect(
        fakes.files.deleted,
        containsAll(['/app/originals/0.jpg', '/app/originals/1.jpg']),
      );
    });

    test('saves into the "Save to" folder', () async {
      final folders = FakeFolders([testFolder('f1', 'Family')]);
      final c = ProviderContainer(
        overrides: [
          ...fakes.overrides,
          folderRepositoryProvider.overrideWithValue(folders),
        ],
      )..listen(idCardFlowProvider, (_, _) {});
      addTearDown(c.dispose);
      c.read(saveFolderProvider(idCardSaveFlow).notifier).start('f1');
      final f = c.read(idCardFlowProvider.notifier);
      await f.captureWithCamera(IdSide.front);
      await f.captureWithCamera(IdSide.back);
      await f.save();
      expect(fakes.commit.folderIds.single, 'f1');
      final saved = c.read(idCardFlowProvider).save as IdCardSaved;
      expect(saved.document.folderId, 'f1');
    });

    test('a folder deleted meanwhile saves to the top level', () async {
      final c = ProviderContainer(
        overrides: [
          ...fakes.overrides,
          folderRepositoryProvider.overrideWithValue(FakeFolders(const [])),
        ],
      )..listen(idCardFlowProvider, (_, _) {});
      addTearDown(c.dispose);
      c.read(saveFolderProvider(idCardSaveFlow).notifier).choose('gone');
      final f = c.read(idCardFlowProvider.notifier);
      await f.captureWithCamera(IdSide.front);
      await f.captureWithCamera(IdSide.back);
      await f.save();
      expect(fakes.commit.folderIds.single, isNull);
    });

    test('commit failure is surfaced, nothing filed', () async {
      await captureBoth();
      fakes.commit.failWith = const AppFailure(
        FailureCode.outputValidationFailed,
      );
      await flow().save();
      final s = state().save;
      expect(s, isA<IdCardSaveFailed>());
      expect(
        (s as IdCardSaveFailed).failure.code,
        FailureCode.outputValidationFailed,
      );
      expect(fakes.recordingRepo.updates, isEmpty);
    });

    test('builder failure is surfaced before any commit', () async {
      await captureBoth();
      fakes.sheet.next = const Err(AppFailure(FailureCode.conversionFailed));
      await flow().save();
      expect(state().save, isA<IdCardSaveFailed>());
      expect(fakes.commit.outputs, isEmpty);
    });

    test('cannot save with only one side', () async {
      await flow().captureWithCamera(IdSide.front);
      expect(state().canSave, isFalse);
      await flow().save();
      expect(fakes.sheet.calls, isEmpty);
    });
  });
}
