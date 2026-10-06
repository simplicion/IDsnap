import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/kits/kit_catalog.dart';
import 'package:feature_tools/src/kits/kit_pipeline.dart';
import 'package:feature_tools/src/kits/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Optional border-uniformity analyzer, overridden by the app with the
/// imaging engine's `backgroundUniformity`. Null disables the hint.
final backgroundAnalyzerProvider = Provider<BackgroundAnalyzer?>((ref) => null);

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on Object {
    return null;
  }
}

final kitPipelineProvider = Provider<KitPipeline>(
  (ref) => KitPipeline(
    files: ref.watch(fileStoreProvider),
    images: ref.watch(imageProcessorProvider),
    pdf: ref.watch(pdfEngineProvider),
    signatures: _optional(() => ref.watch(signatureProcessorProvider)),
    faces: _optional(() => ref.watch(faceLocatorProvider)),
    analyzeBackground: ref.watch(backgroundAnalyzerProvider),
  ),
);

sealed class KitItemState {
  const KitItemState();
}

final class KitItemEmpty extends KitItemState {
  const KitItemEmpty();
}

final class KitItemWorking extends KitItemState {
  const KitItemWorking({this.progress});
  final double? progress;
}

final class KitItemReady extends KitItemState {
  const KitItemReady(this.output, {required this.sourceName});
  final KitOutput output;
  final String sourceName;
}

final class KitItemNotice extends KitItemState {
  const KitItemNotice(this.message);
  final String message;
}

final class KitItemFailed extends KitItemState {
  const KitItemFailed(this.failure);
  final AppFailure failure;
}

sealed class KitSaveState {
  const KitSaveState();
}

final class KitSaveIdle extends KitSaveState {
  const KitSaveIdle();
}

final class KitSaving extends KitSaveState {
  const KitSaving(this.progress);
  final double progress;
}

final class KitSaved extends KitSaveState {
  const KitSaved(this.documents);
  final List<Document> documents;
}

final class KitSaveFailed extends KitSaveState {
  const KitSaveFailed(this.failure);
  final AppFailure failure;
}

@immutable
class KitState {
  const KitState({this.items = const {}, this.save = const KitSaveIdle()});

  final Map<String, KitItemState> items;
  final KitSaveState save;

  KitItemState of(String itemId) => items[itemId] ?? const KitItemEmpty();

  List<String> get readyIds => [
    for (final e in items.entries)
      if (e.value is KitItemReady) e.key,
  ];

  bool get busy =>
      save is KitSaving || items.values.any((s) => s is KitItemWorking);

  KitState withItem(String id, KitItemState s) =>
      KitState(items: {...items, id: s}, save: save);

  KitState withSave(KitSaveState s) => KitState(items: items, save: s);
}

/// State of one kit screen: per-item outputs and the "save all" step.
class KitController extends Notifier<KitState> {
  KitController(this.kitId);

  final String kitId;

  @override
  KitState build() => const KitState();

  ApplicationKit? get _kit => ref.read(kitByIdProvider(kitId));

  void reset() => state = const KitState();

  void clearItem(String itemId) =>
      state = state.withItem(itemId, const KitItemEmpty());

  /// Back to editing after a failed save; finished items are kept.
  void dismissSaveError() => state = state.withSave(const KitSaveIdle());

  Future<void> processPhoto(PhotoItem item, PickedFile file) => _run(
    item.id,
    file.baseName,
    () => ref.read(kitPipelineProvider).photo(item, file.path),
  );

  Future<void> processSignature(SignatureItem item, PickedFile file) => _run(
    item.id,
    file.baseName,
    () => ref.read(kitPipelineProvider).signature(item, file.path),
  );

  Future<void> processDocuments(DocumentItem item, List<PickedFile> files) =>
      _run(
        item.id,
        files.length == 1 ? files.single.baseName : '${files.length} files',
        () => ref
            .read(kitPipelineProvider)
            .document(
              item,
              [
                for (final f in files)
                  (path: f.path, format: DocumentFormat.fromExtension(f.name)),
              ],
              onProgress: (p) {
                if (ref.mounted) {
                  state = state.withItem(item.id, KitItemWorking(progress: p));
                }
              },
            ),
      );

  Future<void> _run(
    String itemId,
    String sourceName,
    Future<Result<KitOutput>> Function() work,
  ) async {
    state = state.withItem(itemId, const KitItemWorking());
    Result<KitOutput> r;
    try {
      r = await work();
    } on AppFailure catch (f) {
      r = Err(f);
    } on Object catch (e, st) {
      r = Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          message:
              "This item couldn't be prepared and nothing was saved. Try "
              'again, or choose a different photo or file.',
        ),
      );
    }
    if (!ref.mounted) return;
    state = state.withItem(itemId, switch (r) {
      Ok(:final value) => KitItemReady(value, sourceName: sourceName),
      Err(failure: final NoticeFailure f) => KitItemNotice(f.message),
      Err(:final failure) => KitItemFailed(failure),
    });
  }

  /// Commits every ready output into the kit's "Save to" folder
  /// ([saveFolderProvider] of [kitSaveFlow]). All-or-nothing: if any step fails, already-saved items are removed so
  /// the library never holds half a kit. Success only after every step.
  Future<void> saveAll() async {
    final kit = _kit;
    if (kit == null || state.busy) return;
    final ready = [
      for (final item in kit.items)
        if (state.of(item.id) case final KitItemReady r) (item, r),
    ];
    if (ready.isEmpty) return;

    final commit = ref.read(commitOutputProvider);
    final repo = ref.read(documentRepositoryProvider);
    final files = ref.read(fileStoreProvider);
    final saved = <Document>[];

    Future<void> rollback() async {
      for (final d in saved) {
        await repo.remove(d.id);
        await files.delete(d.relativePath);
        final thumb = d.thumbnailPath;
        if (thumb != null) await files.delete(thumb);
      }
    }

    state = state.withSave(const KitSaving(0));
    final folderId = await existingSaveFolder(
      () => ref.read(folderRepositoryProvider),
      ref.read(saveFolderProvider(kitSaveFlow(kit.id))),
    );
    if (!ref.mounted) return;
    for (final (i, (item, r)) in ready.indexed) {
      final committed = await commit(
        OutputFile(
          bytes: r.output.bytes,
          format: r.output.format,
          suggestedName: '${kit.label} · ${item.label}',
          expectedPages: r.output.pageCount,
        ),
        folderId: folderId,
      );
      if (committed case Err(:final failure)) {
        await rollback();
        if (ref.mounted) state = state.withSave(KitSaveFailed(failure));
        return;
      }
      saved.add(committed.valueOrNull!);
      if (ref.mounted) {
        state = state.withSave(KitSaving((i + 1) / ready.length));
      }
    }
    if (ref.mounted) state = state.withSave(KitSaved(List.unmodifiable(saved)));
  }
}

/// [saveFolderProvider] key of kit [kitId].
String kitSaveFlow(String kitId) => 'kit:$kitId';

final kitControllerProvider = NotifierProvider.autoDispose
    .family<KitController, KitState, String>(KitController.new);
