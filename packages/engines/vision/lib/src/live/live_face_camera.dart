import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/widgets.dart';

/// Which physical camera a [LiveFaceCamera] uses.
enum CameraFacing { front, back }

/// One face seen in a live preview frame.
///
/// [box] is the detector box (roughly brow to chin) normalized to the
/// upright preview, in the same orientation the user sees — mirrored for
/// the front camera.
@immutable
class LiveFace {
  const LiveFace({
    required this.box,
    this.rollDegrees,
    this.yawDegrees,
    this.leftEyeOpen,
    this.rightEyeOpen,
  });

  final NRect box;

  /// Head tilt towards a shoulder (in-plane rotation), when reported.
  final double? rollDegrees;

  /// Head turned left/right, when reported.
  final double? yawDegrees;

  /// 0..1 eye-open probabilities, when classification is available.
  final double? leftEyeOpen;
  final double? rightEyeOpen;
}

/// Result of analyzing one (throttled) preview frame.
@immutable
class LiveFaceFrame {
  const LiveFaceFrame({required this.faces, this.brightness});

  final List<LiveFace> faces;

  /// Mean luminance of the frame, 0 (black) to 1 (white); `null` when the
  /// frame format doesn't allow a cheap estimate.
  final double? brightness;
}

/// A still photo taken by [LiveFaceCamera.capture].
@immutable
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.facing});

  /// Temporary JPEG file (EXIF orientation set by the platform).
  final String path;
  final CameraFacing facing;
}

/// Why the live camera can't be used. Each maps to a typed [AppFailure]
/// with an actionable message.
enum LiveCameraIssue {
  permissionDenied(
    FailureCode.permissionDenied,
    "Camera access is turned off for this app. Open your phone's Settings, "
    'allow Camera for this app, then tap Try again.',
    FailureAction.retry,
  ),
  noCamera(
    FailureCode.cameraUnavailable,
    "We couldn't find a camera on this device. You can crop an existing "
    'photo instead.',
    FailureAction.pickDifferentFile,
  ),
  cameraUnavailable(
    FailureCode.cameraUnavailable,
    'The camera is busy or stopped responding. Close other apps that use '
    'the camera and try again.',
    FailureAction.retry,
  ),
  detectorUnavailable(
    FailureCode.modelUnavailable,
    "Face detection isn't available on this device. You can still take the "
    'photo with the shutter button and adjust the crop yourself.',
    FailureAction.none,
  ),
  unsupportedPlatform(
    FailureCode.cameraUnavailable,
    'Taking photos is available on Android and iOS. You can crop an '
    'existing photo instead.',
    FailureAction.pickDifferentFile,
  );

  const LiveCameraIssue(this.code, this.message, this.action);
  final FailureCode code;
  final String message;
  final FailureAction action;
}

/// Typed live-camera failure. The cause is kept for diagnostics only.
class LiveCameraFailure extends AppFailure {
  LiveCameraFailure(this.issue, {super.cause, super.stackTrace})
    : super(issue.code, message: issue.message, action: issue.action);

  final LiveCameraIssue issue;

  @override
  String get title => switch (issue) {
    LiveCameraIssue.permissionDenied => 'Camera permission needed',
    LiveCameraIssue.noCamera => 'No camera found',
    LiveCameraIssue.cameraUnavailable => 'Camera unavailable',
    LiveCameraIssue.detectorUnavailable => 'Face detection unavailable',
    LiveCameraIssue.unsupportedPlatform => 'Camera not supported here',
  };
}

/// A camera preview with an on-device face-detection stream. Implementations
/// must release the camera in [close] and must never use the network.
abstract interface class LiveFaceCamera {
  /// Opens [facing] (falling back to any available camera) and starts the
  /// preview and face stream. Calling it again reopens the camera.
  Future<Result<void>> open(CameraFacing facing);

  /// The camera in use, or `null` while closed.
  CameraFacing? get facing;

  /// Whether both a front and a back camera exist (known after [open]).
  bool get canSwitchFacing;

  /// Analyzed frames while open. Emits a [LiveCameraFailure] error with
  /// [LiveCameraIssue.detectorUnavailable] (once) when face detection stops
  /// working; the preview keeps running for manual capture.
  Stream<LiveFaceFrame> get frames;

  /// Upright preview aspect ratio (width / height), when open.
  double? get previewAspectRatio;

  /// Whether the preview is shown mirrored (front camera).
  bool get isMirrored;

  /// The live preview, sized to [previewAspectRatio].
  Widget buildPreview();

  /// Takes a full-resolution still. The face stream pauses while capturing.
  Future<Result<CapturedPhoto>> capture();

  /// Stops the preview and releases the camera (e.g. on app pause).
  Future<void> close();

  /// Releases everything; the object can't be used afterwards.
  Future<void> dispose();
}
