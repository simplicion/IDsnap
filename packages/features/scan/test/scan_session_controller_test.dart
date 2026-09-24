import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Fakes fakes;
  late ProviderContainer container;

  ScanSessionController session() =>
      container.read(scanSessionProvider.notifier);
  List<ScanPage> pages() =>
      container.read(scanSessionProvider).value?.pages ?? const [];

  Future<void> start({
    ScanDraft? draft,
    AppSettings settings = const AppSettings(),
  }) async {
    fakes = Fakes(draft: draft, settings: settings);
    container = ProviderContainer.test(overrides: fakes.overrides);
    await container.read(scanSessionProvider.future);
  }

  test('camera pages are imported, defaulted and persisted', () async {
    await start(
      settings: const AppSettings(defaultFilter: EnhancementFilter.grayscale),
    );
    final result = await session().addFromCamera();

    expect(result.valueOrNull, 2);
    expect(fakes.files.imported, ['/cache/a.jpg', '/cache/b.jpg']);
    expect(
      pages().map((p) => p.edits.filter),
      everyElement(EnhancementFilter.grayscale),
    );
    // Platform scanner output is already cropped: no detection, no quad.
    expect(pages().every((p) => p.edits.quad == null), isTrue);
    expect(fakes.drafts.draft?.pages.length, 2);
  });

  test('cancelling the camera adds nothing and is not an error', () async {
    await start();
    fakes.scanner.next = const Err(AppFailure(FailureCode.captureCancelled));
    final result = await session().addFromCamera();
    expect(result.valueOrNull, 0);
    expect(pages(), isEmpty);
  });

  test('gallery photos get detected corners when confident', () async {
    await start();
    await session().addFromGallery();
    final page = pages().single;
    expect(page.autoDetected, isTrue);
    expect(page.edits.quad, isNotNull);
    expect(container.read(pagesNeedingReviewProvider), isEmpty);
  });

  test('uncertain detection leaves the photo uncropped and flags it', () async {
    await start();
    fakes.images.detection = const Ok(DetectedQuad(Quad.full, 0.2));
    await session().addFromGallery();
    final page = pages().single;
    expect(page.edits.quad, isNull);
    expect(container.read(pagesNeedingReviewProvider), contains(page.id));

    await session().setQuad(page.id, Quad.full);
    expect(container.read(pagesNeedingReviewProvider), isEmpty);
  });

  test('reorder, rotate, filter and duplicate persist every change', () async {
    await start(draft: draftWith(3));
    final savesBefore = fakes.drafts.saves;

    await session().reorder(0, 2);
    expect(pages().map((p) => p.id), ['p1', 'p2', 'p0']);

    await session().rotate('p1');
    await session().rotate('p1');
    expect(pages().first.edits.quarterTurns, 2);
    await session().rotate('p1', clockwise: false);
    expect(pages().first.edits.quarterTurns, 1);

    await session().setFilter('p2', EnhancementFilter.blackWhite);
    expect(pages()[1].edits.filter, EnhancementFilter.blackWhite);

    await session().applyToAll(EnhancementFilter.noShadow, brightness: 0.2);
    expect(
      pages().map((p) => p.edits.filter),
      everyElement(EnhancementFilter.noShadow),
    );
    expect(pages().map((p) => p.edits.brightness), everyElement(0.2));

    await session().duplicate('p0');
    expect(pages().length, 4);
    expect(pages()[3].originalPath, pages()[2].originalPath);

    expect(fakes.drafts.saves - savesBefore, 7);
    expect(
      fakes.drafts.draft?.pages.map((p) => p.id),
      pages().map((p) => p.id),
    );
  });

  test('delete can be undone; purge keeps shared originals', () async {
    await start(draft: draftWith(2));
    await session().duplicate('p0');
    final removed = await session().removePage('p0');
    expect(pages().length, 2);

    await session().restorePage(removed!.page, removed.index);
    expect(pages().first.id, 'p0');

    final again = await session().removePage('p0');
    await session().purge(again!.page);
    // The duplicate still uses the same original, so it must not be deleted.
    expect(fakes.files.deleted, isEmpty);

    final last = pages().firstWhere((p) => p.originalPath.endsWith('p0.jpg'));
    final gone = await session().removePage(last.id);
    await session().purge(gone!.page);
    expect(fakes.files.deleted, ['/app/originals/p0.jpg']);
  });

  test('setQuad stores corners and full frame clears correction', () async {
    await start(draft: draftWith(1));
    const quad = Quad(
      NPoint(0.2, 0.1),
      NPoint(0.8, 0.1),
      NPoint(0.9, 0.9),
      NPoint(0.1, 0.9),
    );
    await session().setQuad('p0', quad);
    expect(pages().single.edits.quad, quad);
    await session().setQuad('p0', Quad.full);
    expect(pages().single.edits.quad, isNull);
  });

  test('discard clears the stored draft', () async {
    await start(draft: draftWith(2));
    await session().discard();
    expect(container.read(scanSessionProvider).value, isNull);
    expect(fakes.drafts.clears, 1);
  });

  test('default scan name is readable and sortable', () {
    expect(
      defaultScanName(DateTime(2026, 3, 7, 9, 5)),
      'Scan 2026-03-07 09.05',
    );
  });
}
