import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The in-progress multi-page scan. Every change is persisted through
/// [DraftStore] so the draft survives backgrounding and process death
/// (PRD FR-04).
class ScanSessionController extends AsyncNotifier<ScanDraft?> {
  final _log = RedactedLogger('scan');

  @override
  Future<ScanDraft?> build() => ref.watch(draftStoreProvider).load();

  ScanDraft? get _draft => state.value;

  List<ScanPage> get pages => _draft?.pages ?? const [];

  // ── Capture ───────────────────────────────────────────────────────────────

  /// Opens the platform document camera and appends the captured pages.
  /// Returns the number of pages added (0 when the user cancelled).
  Future<Result<int>> addFromCamera({int maxPages = 50}) async {
    final scanned = await ref
        .read(documentScannerProvider)
        .scan(maxPages: maxPages);
    switch (scanned) {
      case Ok(:final value):
        return await _importAll(value, fromGallery: false);
      case Err(:final failure):
        return failure.code == FailureCode.captureCancelled
            ? const Ok(0)
            : Err(failure);
    }
  }

  /// Picks photos with the system photo picker and appends them.
  Future<Result<int>> addFromGallery() async {
    final picked = await ref.read(mediaPickerProvider).pickImages();
    switch (picked) {
      case Ok(:final value):
        return await _importAll([
          for (final f in value) f.path,
        ], fromGallery: true);
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// Replaces the image of [pageId] (retake), keeping its position.
  Future<Result<bool>> replacePage(
    String pageId, {
    required ScanSource source,
  }) async {
    final Result<List<String>> paths;
    if (source == ScanSource.gallery) {
      final picked = await ref
          .read(mediaPickerProvider)
          .pickImages(multiple: false);
      paths = picked.map((files) => [for (final f in files) f.path]);
    } else {
      paths = await ref.read(documentScannerProvider).scan(maxPages: 1);
    }
    if (paths case Err(:final failure)) {
      return failure.code == FailureCode.captureCancelled
          ? const Ok(false)
          : Err(failure);
    }
    final list = paths.valueOrNull!;
    if (list.isEmpty) return const Ok(false);

    final imported = await _importOne(
      list.first,
      fromGallery: source == ScanSource.gallery,
    );
    if (imported case Err(:final failure)) return Err(failure);
    final fresh = imported.valueOrNull!;
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return const Err(AppFailure(FailureCode.notFound));
    final old = pages[index];
    final replaced = ScanPage(
      id: old.id,
      originalPath: fresh.originalPath,
      edits: fresh.edits,
      autoDetected: fresh.autoDetected,
    );
    await _commit([...pages]..[index] = replaced);
    await _deleteIfUnreferenced(old.originalPath);
    return const Ok(true);
  }

  Future<Result<int>> _importAll(
    List<String> paths, {
    required bool fromGallery,
  }) async {
    if (paths.isEmpty) return const Ok(0);
    final added = <ScanPage>[];
    for (final path in paths) {
      final page = await _importOne(path, fromGallery: fromGallery);
      if (page case Err(:final failure)) {
        if (added.isNotEmpty) await _commit([...pages, ...added]);
        return Err(failure);
      }
      added.add(page.valueOrNull!);
    }
    await _commit([...pages, ...added]);
    _log.info('pages_added', {'count': added.length, 'gallery': fromGallery});
    return Ok(added.length);
  }

  Future<Result<ScanPage>> _importOne(
    String externalPath, {
    required bool fromGallery,
  }) async {
    final files = ref.read(fileStoreProvider);
    final settings = await _settings();
    final String original;
    try {
      original = await files.importOriginal(externalPath);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }
    var page = ScanPage(
      id: newId(),
      originalPath: original,
      edits: PageEdits(filter: settings.defaultFilter),
    );
    // The platform scanner already crops; only gallery photos need detection.
    if (fromGallery && settings.autoDetectEdges) {
      try {
        final bytes = await files.read(original);
        final detected = await ref
            .read(imageProcessorProvider)
            .detectDocument(bytes);
        final quad = detected.valueOrNull;
        if (quad != null && quad.isConfident) {
          page = page.copyWith(
            edits: page.edits.copyWith(quad: quad.quad),
            autoDetected: true,
          );
        } else {
          ref.read(pagesNeedingReviewProvider.notifier).flag(page.id);
        }
      } on Object {
        ref.read(pagesNeedingReviewProvider.notifier).flag(page.id);
      }
    }
    return Ok(page);
  }

  Future<AppSettings> _settings() async {
    try {
      return await ref.read(settingsProvider.future);
    } on Object {
      return const AppSettings();
    }
  }

  // ── Editing ───────────────────────────────────────────────────────────────

  /// Removes a page and returns it with its index so the UI can offer undo.
  /// Call [purge] once undo is no longer possible.
  Future<({ScanPage page, int index})?> removePage(String pageId) async {
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return null;
    final page = pages[index];
    await _commit([...pages]..removeAt(index));
    return (page: page, index: index);
  }

  Future<void> restorePage(ScanPage page, int index) async {
    final list = [...pages]..insert(index.clamp(0, pages.length), page);
    await _commit(list);
  }

  /// Deletes the original image of a removed page if no page uses it.
  Future<void> purge(ScanPage removed) =>
      _deleteIfUnreferenced(removed.originalPath);

  Future<void> duplicate(String pageId) async {
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return;
    final src = pages[index];
    final copy = ScanPage(
      id: newId(),
      originalPath: src.originalPath,
      edits: src.edits,
      autoDetected: src.autoDetected,
    );
    await _commit([...pages]..insert(index + 1, copy));
  }

  /// Moves a page; indices follow [List.insert] semantics after removal.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= pages.length) return;
    final list = [...pages];
    final page = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), page);
    await _commit(list);
  }

  Future<void> rotate(String pageId, {bool clockwise = true}) => _edit(
    pageId,
    (e) => e.copyWith(quarterTurns: e.quarterTurns + (clockwise ? 1 : 3)),
  );

  Future<void> setFilter(String pageId, EnhancementFilter filter) =>
      _edit(pageId, (e) => e.copyWith(filter: filter));

  Future<void> applyToAll(
    EnhancementFilter filter, {
    double? brightness,
    double? contrast,
  }) => _commit([
    for (final p in pages)
      p.copyWith(
        edits: p.edits.copyWith(
          filter: filter,
          brightness: brightness,
          contrast: contrast,
        ),
      ),
  ]);

  Future<void> setAdjustments(
    String pageId, {
    double? brightness,
    double? contrast,
  }) => _edit(
    pageId,
    (e) => e.copyWith(brightness: brightness, contrast: contrast),
  );

  /// Sets the page corners. `null` (or the full frame) disables perspective
  /// correction.
  Future<void> setQuad(String pageId, Quad? quad) async {
    ref.read(pagesNeedingReviewProvider.notifier).clear(pageId);
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return;
    final p = pages[index];
    final edits = quad == null || quad.isFull
        ? p.edits.copyWith(clearQuad: true)
        : p.edits.copyWith(quad: quad);
    await _commit(
      [...pages]..[index] = p.copyWith(edits: edits, autoDetected: false),
    );
  }

  /// Discards the draft and deletes its captured images.
  Future<void> discard() async {
    await ref.read(draftStoreProvider).clear();
    ref.read(pagesNeedingReviewProvider.notifier).reset();
    state = const AsyncData(null);
  }

  /// Called after the PDF was saved and validated.
  Future<void> finishSaved() => discard();

  Future<void> _edit(
    String pageId,
    PageEdits Function(PageEdits) change,
  ) async {
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return;
    final p = pages[index];
    await _commit([...pages]..[index] = p.copyWith(edits: change(p.edits)));
  }

  Future<void> _commit(List<ScanPage> next) async {
    final draft =
        (_draft ??
                ScanDraft(
                  id: newId(),
                  pages: const [],
                  createdAt: DateTime.now(),
                ))
            .copyWith(pages: List.unmodifiable(next));
    state = AsyncData(draft);
    await ref.read(draftStoreProvider).save(draft);
  }

  Future<void> _deleteIfUnreferenced(String path) async {
    if (pages.any((p) => p.originalPath == path)) return;
    try {
      await ref.read(fileStoreProvider).delete(path);
    } on Object {
      // Best effort; orphaned originals are removed when the draft is cleared.
    }
  }
}

final scanSessionProvider =
    AsyncNotifierProvider<ScanSessionController, ScanDraft?>(
      ScanSessionController.new,
    );

/// Pages whose automatic edge detection was not confident; the review screen
/// shows a "Check corners" hint until the user confirms them.
class ReviewFlags extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void flag(String id) => state = {...state, id};
  void clear(String id) => state = {...state}..remove(id);
  void reset() => state = const {};
}

final pagesNeedingReviewProvider = NotifierProvider<ReviewFlags, Set<String>>(
  ReviewFlags.new,
);
