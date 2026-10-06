import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/id_card/layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IdSide {
  front('Front'),
  back('Back');

  const IdSide(this.label);
  final String label;
}

enum IdCardStep { front, back, preview }

/// One captured side of the card: the untouched original plus its rendered,
/// straightened image.
@immutable
class IdCardCapture {
  const IdCardCapture({
    required this.originalPath,
    required this.rendered,
    required this.width,
    required this.height,
    this.quad,
    this.lowConfidence = false,
  });

  final String originalPath;
  final Quad? quad;
  final Uint8List rendered;
  final int width;
  final int height;

  /// Auto-detection wasn't sure about the edges.
  final bool lowConfidence;

  double get aspect => height == 0 ? idCardAspect : width / height;

  /// Show "Check corners": unsure detection or not card-shaped (> 8 % off).
  bool get needsCheck => lowConfidence || idCardNeedsCornerCheck(width, height);
}

sealed class IdCardSaveState {
  const IdCardSaveState();
}

final class IdCardSaveIdle extends IdCardSaveState {
  const IdCardSaveIdle();
}

final class IdCardSaving extends IdCardSaveState {
  const IdCardSaving();
}

final class IdCardSaved extends IdCardSaveState {
  const IdCardSaved(this.document);
  final Document document;
}

final class IdCardSaveFailed extends IdCardSaveState {
  const IdCardSaveFailed(this.failure);
  final AppFailure failure;
}

@immutable
class IdCardFlowState {
  const IdCardFlowState({
    this.step = IdCardStep.front,
    this.front,
    this.back,
    this.slot,
    this.layout = IdCardLayout.stacked,
    this.sizing = IdCardSizing.actual,
    this.watermark = false,
    this.purpose = '',
    this.busy,
    this.save = const IdCardSaveIdle(),
  });

  final IdCardStep step;
  final IdCardCapture? front;
  final IdCardCapture? back;

  /// [VaultSlot.key] this copy fills, if started from a vault slot.
  final String? slot;
  final IdCardLayout layout;
  final IdCardSizing sizing;
  final bool watermark;
  final String purpose;

  /// Side currently being captured/rendered, if any.
  final IdSide? busy;
  final IdCardSaveState save;

  IdCardCapture? side(IdSide s) => s == IdSide.front ? front : back;

  bool get hasAnyCapture => front != null || back != null;
  bool get canSave => front != null && back != null && save is! IdCardSaving;

  /// "COPY — for `purpose` only", or null when the watermark is off.
  String? get watermarkText {
    if (!watermark) return null;
    final p = purpose.trim();
    return p.isEmpty ? 'COPY' : 'COPY — for $p only';
  }

  IdCardFlowState copyWith({
    IdCardStep? step,
    IdCardCapture? front,
    IdCardCapture? back,
    String? slot,
    IdCardLayout? layout,
    IdCardSizing? sizing,
    bool? watermark,
    String? purpose,
    IdSide? busy,
    bool clearBusy = false,
    IdCardSaveState? save,
  }) => IdCardFlowState(
    step: step ?? this.step,
    front: front ?? this.front,
    back: back ?? this.back,
    slot: slot ?? this.slot,
    layout: layout ?? this.layout,
    sizing: sizing ?? this.sizing,
    watermark: watermark ?? this.watermark,
    purpose: purpose ?? this.purpose,
    busy: clearBusy ? null : busy ?? this.busy,
    save: save ?? this.save,
  );

  IdCardFlowState withSide(IdSide s, IdCardCapture capture) =>
      s == IdSide.front ? copyWith(front: capture) : copyWith(back: capture);
}

/// Drives ID card front & back → one-page PDF (roadmap Feature A).
///
/// State lives in memory for the length of the flow: [DraftStore] holds the
/// single regular scan draft, and storing the two card sides there would make
/// them appear as a resumable multi-page scan. Captured originals are deleted
/// after a successful save or when the flow is discarded.
class IdCardFlowController extends Notifier<IdCardFlowState> {
  final _log = RedactedLogger('id_card');
  var _finished = false;
  late FileStore _files;

  /// Originals imported by this flow and not yet deleted.
  final _originals = <String>{};

  @override
  IdCardFlowState build() {
    // Captured here: Ref can't be used inside onDispose.
    _files = ref.read(fileStoreProvider);
    ref.onDispose(() {
      if (!_finished) unawaited(_deleteOriginals());
    });
    return const IdCardFlowState();
  }

  void start({String? slot}) {
    if (slot != null && slot != state.slot) state = state.copyWith(slot: slot);
  }

  /// Captures [side] with the platform document scanner.
  /// Returns a failure to show, or null (success or user cancel).
  Future<AppFailure?> captureWithCamera(IdSide side) =>
      _capture(side, () async {
        final r = await ref.read(documentScannerProvider).scan(maxPages: 1);
        return r.map((paths) => paths.isEmpty ? null : paths.first);
      }, fromGallery: false);

  /// Picks one photo of [side] from the gallery.
  Future<AppFailure?> captureFromPhotos(IdSide side) => _capture(
    side,
    () async {
      final r = await ref.read(mediaPickerProvider).pickImages(multiple: false);
      return r.map((files) => files.isEmpty ? null : files.first.path);
    },
    fromGallery: true,
  );

  Future<AppFailure?> _capture(
    IdSide side,
    Future<Result<String?>> Function() acquire, {
    required bool fromGallery,
  }) async {
    if (state.busy != null) return null;
    state = state.copyWith(busy: side);
    try {
      final acquired = await acquire();
      if (!ref.mounted) return null;
      final external = switch (acquired) {
        Ok(:final value) => value,
        Err(:final failure) =>
          failure.code == FailureCode.captureCancelled ? null : throw failure,
      };
      if (external == null) return null;

      final files = _files;
      final original = await files.importOriginal(external);
      _originals.add(original);
      final bytes = await files.read(original);

      Quad? quad;
      var lowConfidence = false;
      // The platform scanner already crops; gallery photos need detection.
      if (fromGallery) {
        final det = await ref
            .read(imageProcessorProvider)
            .detectDocument(bytes);
        final d = det.valueOrNull;
        if (d != null && d.isConfident) {
          quad = d.quad;
        } else {
          lowConfidence = true;
          quad = d?.quad;
        }
      }
      final capture = await _render(original, bytes, quad, lowConfidence);
      if (!ref.mounted) return null;

      final old = state.side(side);
      var next = state.withSide(side, capture);
      next = next.copyWith(
        step: side == IdSide.front && next.back == null
            ? IdCardStep.back
            : IdCardStep.preview,
        save: const IdCardSaveIdle(),
      );
      state = next;
      if (old != null) {
        _originals.remove(old.originalPath);
        unawaited(files.delete(old.originalPath));
      }
      _log.info('captured', {'side': side, 'check': capture.needsCheck});
      return null;
    } on AppFailure catch (f) {
      return f;
    } on Object catch (e, st) {
      return AppFailure(
        FailureCode.unknown,
        cause: e,
        stackTrace: st,
        message:
            "This photo couldn't be processed. Retake this side of the "
            'card.',
      );
    } finally {
      if (ref.mounted) state = state.copyWith(clearBusy: true);
    }
  }

  Future<IdCardCapture> _render(
    String originalPath,
    Uint8List bytes,
    Quad? quad,
    bool lowConfidence,
  ) async {
    final images = ref.read(imageProcessorProvider);
    final rendered = await images.renderPage(
      bytes,
      PageEdits(quad: quad),
      preset: QualityPreset.high,
    );
    final jpeg = switch (rendered) {
      Ok(:final value) => value,
      Err(:final failure) => throw failure,
    };
    final info = (await images.inspect(jpeg)).valueOrNull;
    return IdCardCapture(
      originalPath: originalPath,
      quad: quad,
      rendered: jpeg,
      width: info?.width ?? 0,
      height: info?.height ?? 0,
      lowConfidence: lowConfidence,
    );
  }

  /// Applies manually adjusted corners to [side] and re-renders it.
  Future<AppFailure?> setQuad(IdSide side, Quad quad) async {
    final current = state.side(side);
    if (current == null || state.busy != null) return null;
    state = state.copyWith(busy: side);
    try {
      final bytes = await ref
          .read(fileStoreProvider)
          .read(current.originalPath);
      final capture = await _render(current.originalPath, bytes, quad, false);
      if (!ref.mounted) return null;
      state = state
          .withSide(side, capture)
          .copyWith(save: const IdCardSaveIdle());
      return null;
    } on AppFailure catch (f) {
      return f;
    } on Object catch (e, st) {
      return AppFailure(
        FailureCode.unknown,
        cause: e,
        stackTrace: st,
        action: FailureAction.adjustCorners,
        message:
            "The new corners couldn't be applied. Adjust them again or "
            'retake this side.',
      );
    } finally {
      if (ref.mounted) state = state.copyWith(clearBusy: true);
    }
  }

  /// Goes back to capture [side] again; the other side is kept.
  void retake(IdSide side) => state = state.copyWith(
    step: side == IdSide.front ? IdCardStep.front : IdCardStep.back,
    save: const IdCardSaveIdle(),
  );

  void setLayout(IdCardLayout v) => state = state.copyWith(layout: v);
  void setSizing(IdCardSizing v) => state = state.copyWith(sizing: v);
  void setWatermark({required bool enabled}) =>
      state = state.copyWith(watermark: enabled);
  void setPurpose(String v) => state = state.copyWith(purpose: v);
  void resetSave() => state = state.copyWith(save: const IdCardSaveIdle());

  /// The layout that [save] will write, for on-screen preview.
  IdCardSheetLayout? currentLayout() {
    final f = state.front;
    final b = state.back;
    if (f == null || b == null) return null;
    return layoutIdCards(
      front: f.rendered,
      back: b.rendered,
      layout: state.layout,
      sizing: state.sizing,
      frontAspect: f.aspect,
      backAspect: b.aspect,
    );
  }

  /// Builds the one-page PDF and commits it (validated) into the folder
  /// chosen under "Save to" ([saveFolderProvider] of [idCardSaveFlow]).
  /// Success is only reported after the commit returned `Ok`.
  ///
  /// Any unexpected error ends in [IdCardSaveFailed] (with retry), never in
  /// an endless spinner on a screen that can't be left while saving.
  Future<void> save({DateTime? now}) async {
    try {
      await _save(now: now);
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      final failure = e is AppFailure
          ? e
          : AppFailure(FailureCode.unknown, cause: e, stackTrace: st);
      state = state.copyWith(save: IdCardSaveFailed(failure));
    }
  }

  Future<void> _save({DateTime? now}) async {
    if (!state.canSave) return;
    final layout = currentLayout()!;
    state = state.copyWith(save: const IdCardSaving());

    final built = await ref
        .read(sheetPdfBuilderProvider)
        .build(
          layout.images,
          pageWidthPt: layout.pageWidthPt,
          pageHeightPt: layout.pageHeightPt,
          watermark: state.watermarkText,
        );
    if (!ref.mounted) return;
    final Uint8List bytes;
    switch (built) {
      case Ok(:final value):
        bytes = value;
      case Err(:final failure):
        state = state.copyWith(save: IdCardSaveFailed(failure));
        return;
    }

    // The user's "Save to" choice; a folder deleted meanwhile → top level.
    final folderId = await existingSaveFolder(
      () => ref.read(folderRepositoryProvider),
      ref.read(saveFolderProvider(idCardSaveFlow)),
    );
    if (!ref.mounted) return;
    final committed = await ref
        .read(commitOutputProvider)
        .call(
          OutputFile(
            bytes: bytes,
            format: DocumentFormat.pdf,
            suggestedName: defaultIdCardName(now ?? DateTime.now()),
            expectedPages: 1,
          ),
          folderId: folderId,
        );
    if (!ref.mounted) return;
    switch (committed) {
      case Err(:final failure):
        state = state.copyWith(save: IdCardSaveFailed(failure));
      case Ok(value: final doc):
        _log.info('saved', {'inFolder': doc.folderId != null});
        _finished = true;
        await _deleteOriginals();
        if (!ref.mounted) return;
        state = state.copyWith(save: IdCardSaved(doc));
    }
  }

  /// Deletes captured originals (discard or after a successful save).
  Future<void> discard() async {
    _finished = true;
    await _deleteOriginals();
  }

  Future<void> _deleteOriginals() async {
    final paths = [..._originals];
    _originals.clear();
    for (final path in paths) {
      try {
        await _files.delete(path);
      } on Object {
        // Best effort; nothing else references these originals.
      }
    }
  }
}

/// [saveFolderProvider] key of the ID card flow.
const idCardSaveFlow = 'id-card';

final idCardFlowProvider =
    NotifierProvider.autoDispose<IdCardFlowController, IdCardFlowState>(
      IdCardFlowController.new,
    );

/// "ID card — 2026-09-25"
String defaultIdCardName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'ID card — ${t.year}-${two(t.month)}-${two(t.day)}';
}
