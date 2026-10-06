import 'dart:async';

import 'package:clock/clock.dart';
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/src/passport_photo/capture_machine.dart';
import 'package:feature_scan/src/passport_photo/face_checks.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:feature_scan/src/passport_photo/photo_processing.dart';
import 'package:feature_scan/src/passport_photo/print_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The live camera + face stream. Overridden with a fake in tests.
final liveFaceCameraProvider = Provider.autoDispose<LiveFaceCamera>((ref) {
  final camera = CameraFaceSession();
  ref.onDispose(() => unawaited(camera.dispose()));
  return camera;
});

enum CameraStatus { opening, live, capturing, closed, failed }

/// Review of a captured photo.
@immutable
class PassportReview {
  const PassportReview({
    required this.source,
    required this.rect,
    this.brighten = false,
    this.photo,
    this.processing = false,
    this.failure,
  });

  final SourcePhoto source;
  final NRect rect;
  final bool brighten;
  final ProcessedPhoto? photo;
  final bool processing;
  final AppFailure? failure;

  bool get faceFound => source.face != null;

  PassportReview copyWith({
    NRect? rect,
    bool? brighten,
    ProcessedPhoto? photo,
    bool? processing,
    AppFailure? failure,
    bool clearFailure = false,
  }) => PassportReview(
    source: source,
    rect: rect ?? this.rect,
    brighten: brighten ?? this.brighten,
    photo: photo ?? this.photo,
    processing: processing ?? this.processing,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

sealed class PassportSave {
  const PassportSave();
}

final class PassportSaveIdle extends PassportSave {
  const PassportSaveIdle();
}

final class PassportSaving extends PassportSave {
  const PassportSaving();
}

final class PassportSaved extends PassportSave {
  const PassportSaved(this.document, {required this.sheet});
  final Document document;
  final bool sheet;
}

final class PassportSaveFailed extends PassportSave {
  const PassportSaveFailed(this.failure);
  final AppFailure failure;
}

@immutable
class PassportPhotoState {
  const PassportPhotoState({
    this.preset = PhotoPreset.passport,
    this.facing = CameraFacing.front,
    this.status = CameraStatus.closed,
    this.cameraFailure,
    this.detectorAvailable = true,
    this.checks = FaceCheckResult.noFrame,
    this.phase = const Searching(),
    this.face,
    this.canSwitchFacing = false,
    this.previewAspect = 3 / 4,
    this.mirrored = true,
    this.review,
    this.save = const PassportSaveIdle(),
  });

  final PhotoPreset preset;
  final CameraFacing facing;
  final CameraStatus status;
  final AppFailure? cameraFailure;
  final bool detectorAvailable;
  final FaceCheckResult checks;
  final CapturePhase phase;

  /// The single tracked face (for the overlay), if any.
  final LiveFace? face;
  final bool canSwitchFacing;
  final double previewAspect;
  final bool mirrored;
  final PassportReview? review;
  final PassportSave save;

  bool get autoCapture => phase is! Manual;
  GuideGeometry get guide =>
      GuideGeometry.forPreset(preset, previewAspect: previewAspect);

  PassportPhotoState copyWith({
    PhotoPreset? preset,
    CameraFacing? facing,
    CameraStatus? status,
    AppFailure? cameraFailure,
    bool clearCameraFailure = false,
    bool? detectorAvailable,
    FaceCheckResult? checks,
    CapturePhase? phase,
    LiveFace? face,
    bool clearFace = false,
    bool? canSwitchFacing,
    double? previewAspect,
    bool? mirrored,
    PassportReview? review,
    bool clearReview = false,
    PassportSave? save,
  }) => PassportPhotoState(
    preset: preset ?? this.preset,
    facing: facing ?? this.facing,
    status: status ?? this.status,
    cameraFailure: clearCameraFailure
        ? null
        : cameraFailure ?? this.cameraFailure,
    detectorAvailable: detectorAvailable ?? this.detectorAvailable,
    checks: checks ?? this.checks,
    phase: phase ?? this.phase,
    face: clearFace ? null : face ?? this.face,
    canSwitchFacing: canSwitchFacing ?? this.canSwitchFacing,
    previewAspect: previewAspect ?? this.previewAspect,
    mirrored: mirrored ?? this.mirrored,
    review: clearReview ? null : review ?? this.review,
    save: save ?? this.save,
  );
}

/// [saveFolderProvider] key of the passport-size photo flow.
const passportPhotoSaveFlow = 'passport-photo';

final passportPhotoProvider =
    NotifierProvider.autoDispose<PassportPhotoController, PassportPhotoState>(
      PassportPhotoController.new,
    );

/// Drives the passport-size photo flow: live checks → auto/manual capture →
/// automatic crop → review → save as JPEG or print sheet.
class PassportPhotoController extends Notifier<PassportPhotoState> {
  late LiveFaceCamera _camera;
  final _machine = CaptureMachine();
  StreamSubscription<LiveFaceFrame>? _sub;
  Timer? _ticker;
  LiveFace? _lastFace;
  var _openRequest = 0;

  @override
  PassportPhotoState build() {
    _camera = ref.watch(liveFaceCameraProvider);
    _sub = _camera.frames.listen(_onFrame, onError: _onFrameError);
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _ticker?.cancel();
      unawaited(_camera.close());
    });
    return const PassportPhotoState();
  }

  PassportPhotoProcessor get _processor => PassportPhotoProcessor(
    files: ref.read(fileStoreProvider),
    images: ref.read(imageProcessorProvider),
    faces: _faceLocatorOrNull(),
  );

  FaceLocator? _faceLocatorOrNull() {
    try {
      return ref.read(faceLocatorProvider);
    } on Object {
      return null; // Not wired in this app: fall back to the live box.
    }
  }

  /// Opens (or reopens) the camera for the current facing.
  Future<void> start() async {
    final request = ++_openRequest;
    _stopTicker();
    _machine.reset();
    _lastFace = null;
    state = state.copyWith(
      status: CameraStatus.opening,
      clearCameraFailure: true,
      checks: FaceCheckResult.noFrame,
      phase: _machine.phase,
      clearFace: true,
    );
    final r = await _camera.open(state.facing);
    if (!ref.mounted || request != _openRequest) return;
    switch (r) {
      case Ok():
        state = state.copyWith(
          status: CameraStatus.live,
          facing: _camera.facing ?? state.facing,
          canSwitchFacing: _camera.canSwitchFacing,
          previewAspect: _camera.previewAspectRatio ?? state.previewAspect,
          mirrored: _camera.isMirrored,
        );
      case Err(:final failure):
        state = state.copyWith(
          status: CameraStatus.failed,
          cameraFailure: failure,
        );
    }
  }

  /// Releases the camera (app paused / screen hidden).
  Future<void> pause() async {
    _openRequest++;
    _stopTicker();
    _machine.reset();
    if (state.status == CameraStatus.live ||
        state.status == CameraStatus.opening) {
      state = state.copyWith(
        status: CameraStatus.closed,
        phase: _machine.phase,
        clearFace: true,
      );
    }
    await _camera.close();
  }

  /// Reopens the camera after [pause] unless a photo is being reviewed.
  Future<void> resume() async {
    if (state.review != null) return;
    if (state.status == CameraStatus.closed) await start();
  }

  Future<void> switchFacing() async {
    state = state.copyWith(
      facing: state.facing == CameraFacing.front
          ? CameraFacing.back
          : CameraFacing.front,
    );
    await start();
  }

  void setPreset(PhotoPreset preset) {
    _machine.reset();
    _lastFace = null;
    _stopTicker();
    state = state.copyWith(preset: preset, phase: _machine.phase);
    final review = state.review;
    if (review != null) {
      final rect = _processor.autoRect(review.source, preset);
      unawaited(_render(review.copyWith(rect: rect)));
    }
  }

  void setAutoCapture({required bool enabled}) {
    _machine.setAuto(enabled: enabled && state.detectorAvailable);
    _stopTicker();
    state = state.copyWith(phase: _machine.phase);
  }

  /// Cancel button during the 3-2-1 countdown.
  void cancelCountdown() {
    _machine.cancel();
    _stopTicker();
    state = state.copyWith(phase: _machine.phase);
  }

  void _onFrame(LiveFaceFrame frame) {
    if (state.status != CameraStatus.live || state.review != null) return;
    final checks = evaluateFace(frame, state.guide, previous: _lastFace);
    final single = frame.faces.length == 1 ? frame.faces.single : null;
    _lastFace = single;
    final phase = _machine.onChecks(allPass: checks.allPass, now: clock.now());
    state = state.copyWith(
      checks: checks,
      phase: phase,
      face: single,
      clearFace: single == null,
    );
    _afterPhase(phase);
  }

  void _onFrameError(Object error) {
    if (error is LiveCameraFailure &&
        error.issue == LiveCameraIssue.detectorUnavailable) {
      _machine.setAuto(enabled: false);
      _stopTicker();
      state = state.copyWith(
        detectorAvailable: false,
        phase: _machine.phase,
        clearFace: true,
      );
    }
  }

  void _afterPhase(CapturePhase phase) {
    switch (phase) {
      case Countdown():
        _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
          final p = _machine.tick(clock.now());
          if (p != state.phase) state = state.copyWith(phase: p);
          _afterPhase(p);
        });
      case Fire():
        _stopTicker();
        unawaited(capture());
      case Searching() || Holding() || Manual():
        _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Takes the photo (shutter button or auto-capture), releases the camera
  /// and prepares the automatic crop.
  Future<void> capture() async {
    if (state.status != CameraStatus.live) return;
    _stopTicker();
    final liveFace = state.face;
    final mirrored = state.mirrored;
    state = state.copyWith(status: CameraStatus.capturing);
    final shot = await _camera.capture();
    if (!ref.mounted) return;
    final CapturedPhoto photo;
    switch (shot) {
      case Err(:final failure):
        _machine.reset();
        state = state.copyWith(
          status: CameraStatus.failed,
          cameraFailure: failure,
          phase: _machine.phase,
        );
        return;
      case Ok(:final value):
        photo = value;
    }
    await _camera.close();
    if (!ref.mounted) return;
    state = state.copyWith(clearFace: true);

    final processor = _processor;
    final loaded = await processor.load(
      photo.path,
      fallbackFace: liveFace == null
          ? null
          : unmirrorBox(liveFace.box, mirrored: mirrored),
    );
    if (!ref.mounted) return;
    switch (loaded) {
      case Err(:final failure):
        state = state.copyWith(
          status: CameraStatus.failed,
          cameraFailure: failure,
        );
      case Ok(:final value):
        final rect = processor.autoRect(value, state.preset);
        await _render(PassportReview(source: value, rect: rect));
    }
  }

  /// Back to the camera.
  Future<void> retake() async {
    _machine.reset();
    state = state.copyWith(
      clearReview: true,
      save: const PassportSaveIdle(),
      phase: _machine.phase,
    );
    await start();
  }

  Future<void> setCrop(NRect rect) async {
    final review = state.review;
    if (review == null) return;
    await _render(review.copyWith(rect: rect));
  }

  /// The automatic crop for the photo under review, if any.
  NRect? autoRectForReview() {
    final review = state.review;
    return review == null
        ? null
        : _processor.autoRect(review.source, state.preset);
  }

  /// Resets the crop to the automatic framing.
  Future<void> autoCrop() async {
    final review = state.review;
    if (review == null) return;
    await setCrop(_processor.autoRect(review.source, state.preset));
  }

  Future<void> setBrighten({required bool enabled}) async {
    final review = state.review;
    if (review == null) return;
    await _render(review.copyWith(brighten: enabled));
  }

  Future<void> _render(PassportReview review) async {
    state = state.copyWith(
      review: review.copyWith(processing: true, clearFailure: true),
      save: const PassportSaveIdle(),
    );
    final preset = state.preset;
    final r = await _processor.render(
      review.source,
      preset,
      review.rect,
      brighten: review.brighten,
    );
    if (!ref.mounted) return;
    final current = state.review;
    // A newer edit replaced this one while it was rendering.
    if (current == null ||
        current.rect != review.rect ||
        current.brighten != review.brighten ||
        state.preset != preset) {
      return;
    }
    state = state.copyWith(
      review: switch (r) {
        Ok(:final value) => current.copyWith(photo: value, processing: false),
        Err(:final failure) => current.copyWith(
          processing: false,
          failure: failure,
        ),
      },
    );
  }

  String get _baseName => '${state.preset.name} photo';

  /// The "Save to" folder ([saveFolderProvider] of [passportPhotoSaveFlow]);
  /// a folder deleted meanwhile falls back to the top level.
  Future<String?> _saveFolder() => existingSaveFolder(
    () => ref.read(folderRepositoryProvider),
    ref.read(saveFolderProvider(passportPhotoSaveFlow)),
  );

  /// Saves the finished JPEG into the chosen ID Vault folder.
  Future<void> saveJpeg() async {
    final photo = state.review?.photo;
    if (photo == null || state.save is PassportSaving) return;
    state = state.copyWith(save: const PassportSaving());
    final folderId = await _saveFolder();
    if (!ref.mounted) return;
    final r = await ref
        .read(commitOutputProvider)
        .call(
          OutputFile(
            bytes: photo.bytes,
            format: DocumentFormat.jpeg,
            suggestedName: _baseName,
          ),
          folderId: folderId,
        );
    if (!ref.mounted) return;
    state = state.copyWith(
      save: switch (r) {
        Ok(:final value) => PassportSaved(value, sheet: false),
        Err(:final failure) => PassportSaveFailed(failure),
      },
    );
  }

  /// Builds a one-page PDF with [count] copies on [paper] and saves it.
  Future<void> savePrintSheet(PrintPaper paper, {int? count}) async {
    final photo = state.review?.photo;
    if (photo == null || state.save is PassportSaving) return;
    state = state.copyWith(save: const PassportSaving());
    try {
      await _savePrintSheet(photo, paper, count: count);
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      final failure = e is AppFailure
          ? e
          : AppFailure(FailureCode.unknown, cause: e, stackTrace: st);
      state = state.copyWith(save: PassportSaveFailed(failure));
    }
  }

  Future<void> _savePrintSheet(
    ProcessedPhoto photo,
    PrintPaper paper, {
    int? count,
  }) async {
    final preset = state.preset;
    final layout = layoutPrintSheet(
      jpeg: photo.bytes,
      photoWidthMm: preset.widthMm,
      photoHeightMm: preset.heightMm,
      paper: paper,
      count: count,
    );
    if (layout.images.isEmpty) {
      state = state.copyWith(
        save: const PassportSaveFailed(
          AppFailure(
            FailureCode.outputValidationFailed,
            message: "This photo size doesn't fit on that paper.",
          ),
        ),
      );
      return;
    }
    final built = await ref
        .read(sheetPdfBuilderProvider)
        .build(
          layout.images,
          pageWidthPt: layout.pageWidthPt,
          pageHeightPt: layout.pageHeightPt,
        );
    if (!ref.mounted) return;
    if (built case Err(:final failure)) {
      state = state.copyWith(save: PassportSaveFailed(failure));
      return;
    }
    final folderId = await _saveFolder();
    if (!ref.mounted) return;
    final r = await ref
        .read(commitOutputProvider)
        .call(
          OutputFile(
            bytes: built.valueOrNull!,
            format: DocumentFormat.pdf,
            suggestedName: '${preset.name} print sheet',
            expectedPages: 1,
          ),
          folderId: folderId,
        );
    if (!ref.mounted) return;
    state = state.copyWith(
      save: switch (r) {
        Ok(:final value) => PassportSaved(value, sheet: true),
        Err(:final failure) => PassportSaveFailed(failure),
      },
    );
  }
}
