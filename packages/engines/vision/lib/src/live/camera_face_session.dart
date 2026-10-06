import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:engine_vision/src/live/frame_math.dart';
import 'package:engine_vision/src/live/live_face_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// [LiveFaceCamera] backed by the `camera` plugin and ML Kit face detection
/// (bundled model, fully offline). Frames are analyzed at most every
/// [throttle]; frames arriving while one is being analyzed are dropped.
class CameraFaceSession implements LiveFaceCamera {
  CameraFaceSession({
    this.throttle = const Duration(milliseconds: 150),
    this.resolution = ResolutionPreset.high,
  });

  final Duration throttle;
  final ResolutionPreset resolution;

  final _log = RedactedLogger('live-face');
  final _frames = StreamController<LiveFaceFrame>.broadcast();
  CameraController? _controller;
  FaceDetector? _detector;
  List<CameraDescription>? _cameras;
  CameraFacing? _facing;
  var _busy = false;
  var _detectorBroken = false;
  var _disposed = false;
  final _sinceLast = Stopwatch();
  Completer<void>? _idle;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  FaceDetector get _faces => _detector ??= FaceDetector(
    options: FaceDetectorOptions(enableClassification: true, minFaceSize: 0.15),
  );

  @override
  Stream<LiveFaceFrame> get frames => _frames.stream;

  @override
  CameraFacing? get facing => _facing;

  @override
  bool get canSwitchFacing {
    final cams = _cameras ?? const [];
    return cams.any((c) => c.lensDirection == CameraLensDirection.front) &&
        cams.any((c) => c.lensDirection == CameraLensDirection.back);
  }

  @override
  double? get previewAspectRatio {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    // The plugin reports landscape width / height; the UI is portrait.
    return 1 / c.value.aspectRatio;
  }

  @override
  bool get isMirrored => _facing == CameraFacing.front;

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  @override
  Future<Result<void>> open(CameraFacing facing) async {
    if (_disposed) {
      return Err(LiveCameraFailure(LiveCameraIssue.cameraUnavailable));
    }
    if (!_supported) {
      return Err(LiveCameraFailure(LiveCameraIssue.unsupportedPlatform));
    }
    await close();
    try {
      final cams = _cameras ??= await availableCameras();
      if (cams.isEmpty) {
        return Err(LiveCameraFailure(LiveCameraIssue.noCamera));
      }
      final wanted = facing == CameraFacing.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final desc = cams.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        desc,
        resolution,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on Object {
        // Not supported everywhere; capture still works.
      }
      _facing = desc.lensDirection == CameraLensDirection.front
          ? CameraFacing.front
          : CameraFacing.back;
      await _startStream();
      _log.info('opened', {'facing': _facing!.name});
      return const Ok(null);
    } on CameraException catch (e, st) {
      await close();
      return Err(
        LiveCameraFailure(_issueFor(e.code), cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      await close();
      return Err(
        LiveCameraFailure(
          LiveCameraIssue.cameraUnavailable,
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }

  static LiveCameraIssue _issueFor(String code) => switch (code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' ||
    'cameraPermission' ||
    'permissionDenied' => LiveCameraIssue.permissionDenied,
    'cameraNotFound' || 'noCamerasAvailable' => LiveCameraIssue.noCamera,
    _ => LiveCameraIssue.cameraUnavailable,
  };

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || _detectorBroken || c.value.isStreamingImages) return;
    _sinceLast
      ..reset()
      ..start();
    var first = true;
    await c.startImageStream((image) {
      if (_busy || (!first && _sinceLast.elapsed < throttle)) return;
      first = false;
      _sinceLast
        ..reset()
        ..start();
      unawaited(_analyze(c, image));
    });
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.isStreamingImages) {
      try {
        await c.stopImageStream();
      } on Object {
        // Already stopped.
      }
    }
    // Let an in-flight analysis finish before the buffer goes away.
    if (_busy) await (_idle ??= Completer<void>()).future;
  }

  Future<void> _analyze(CameraController c, CameraImage image) async {
    _busy = true;
    try {
      final android = Platform.isAndroid;
      final desc = c.description;
      final rotation = frameRotationDegrees(
        android: android,
        front: desc.lensDirection == CameraLensDirection.front,
        sensorOrientation: desc.sensorOrientation,
        deviceOrientationDegrees: _degrees(c.value.deviceOrientation),
        bufferWidth: image.width,
        bufferHeight: image.height,
      );
      final format = InputImageFormatValue.fromRawValue(
        image.format.raw as int,
      );
      final okFormat = android
          ? format == InputImageFormat.nv21
          : format == InputImageFormat.bgra8888;
      if (format == null || !okFormat || image.planes.isEmpty) return;
      final plane = image.planes.first;
      final brightness = meanLuminance(
        plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        bgra: !android,
      );
      final input = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(rotation) ??
              InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final found = await _faces.processImage(input);
      final upright = uprightFrameSize(image.width, image.height, rotation);
      final mirror = isMirrored;
      final faces = <LiveFace>[
        for (final f in found)
          if (normalizeLiveBox(
                left: f.boundingBox.left,
                top: f.boundingBox.top,
                width: f.boundingBox.width,
                height: f.boundingBox.height,
                frameWidth: upright.width,
                frameHeight: upright.height,
                mirror: mirror,
              )
              case final box?)
            LiveFace(
              box: box,
              rollDegrees: f.headEulerAngleZ,
              yawDegrees: f.headEulerAngleY,
              // ML Kit's "left eye" is the subject's; order doesn't matter.
              leftEyeOpen: f.leftEyeOpenProbability,
              rightEyeOpen: f.rightEyeOpenProbability,
            ),
      ];
      if (!_frames.isClosed && _controller == c) {
        _frames.add(LiveFaceFrame(faces: faces, brightness: brightness));
      }
    } on PlatformException catch (e, st) {
      _reportDetectorFailure(e, st);
    } on MissingPluginException catch (e, st) {
      _reportDetectorFailure(e, st);
    } on Object catch (e, st) {
      _log.warn('frame_failed', {'type': e.runtimeType.toString()});
      if (kDebugMode) debugPrintStack(stackTrace: st, maxFrames: 3);
    } finally {
      _busy = false;
      _idle?.complete();
      _idle = null;
    }
  }

  void _reportDetectorFailure(Object e, StackTrace st) {
    if (_detectorBroken) return;
    _detectorBroken = true;
    _log.warn('detector_unavailable', {'type': e.runtimeType.toString()});
    if (!_frames.isClosed) {
      _frames.addError(
        LiveCameraFailure(
          LiveCameraIssue.detectorUnavailable,
          cause: e,
          stackTrace: st,
        ),
      );
    }
    unawaited(_stopStream());
  }

  static int _degrees(DeviceOrientation o) => switch (o) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };

  @override
  Future<Result<CapturedPhoto>> capture() async {
    final c = _controller;
    final facing = _facing;
    if (c == null || facing == null || !c.value.isInitialized) {
      return Err(LiveCameraFailure(LiveCameraIssue.cameraUnavailable));
    }
    try {
      await _stopStream();
      final file = await c.takePicture();
      return Ok(CapturedPhoto(path: file.path, facing: facing));
    } on CameraException catch (e, st) {
      return Err(
        LiveCameraFailure(_issueFor(e.code), cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      return Err(
        LiveCameraFailure(
          LiveCameraIssue.cameraUnavailable,
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    final c = _controller;
    if (c == null) return;
    await _stopStream();
    _controller = null;
    _facing = null;
    try {
      await c.dispose();
    } on Object {
      // Releasing a failed controller can throw; nothing else to do.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await close();
    await _detector?.close();
    _detector = null;
    await _frames.close();
  }
}
