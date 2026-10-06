import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// [FaceLocator] backed by ML Kit face detection. The Android model is the
/// bundled `com.google.mlkit:face-detection` artifact and iOS uses the
/// GoogleMLKit pod, so detection runs fully offline.
class MlKitFaceLocator implements FaceLocator {
  MlKitFaceLocator();

  final _log = RedactedLogger('face');
  FaceDetector? _detector;

  FaceDetector get _instance => _detector ??= FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<EngineCapability> capability() async => _supported
      ? const EngineCapability(available: true, worksOffline: true)
      : const EngineCapability(
          available: false,
          worksOffline: false,
          note: 'Face detection is available on Android and iOS.',
        );

  @override
  Future<Result<NRect?>> locateLargestFace(String imagePath) async {
    if (!_supported) {
      return const Err(AppFailure(FailureCode.modelUnavailable));
    }
    try {
      final size = await uprightSize(await File(imagePath).readAsBytes());
      if (size == null) return const Err(AppFailure(FailureCode.corruptFile));
      final faces = await _instance.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final box = largestFaceBox(
        [
          for (final f in faces)
            (
              left: f.boundingBox.left,
              top: f.boundingBox.top,
              width: f.boundingBox.width,
              height: f.boundingBox.height,
            ),
        ],
        size.width,
        size.height,
      );
      _log.info('located', {'faces': faces.length});
      return Ok(box);
    } on PlatformException catch (e, st) {
      return Err(
        AppFailure(FailureCode.modelUnavailable, cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      return Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          heading: "The face couldn't be found automatically",
          message: 'You can still frame the photo by hand.',
          action: FailureAction.none,
        ),
      );
    }
  }

  Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }
}

typedef PixelBox = ({double left, double top, double width, double height});

/// Picks the largest face and normalizes it to the upright image size.
@visibleForTesting
NRect? largestFaceBox(List<PixelBox> faces, int width, int height) {
  if (faces.isEmpty || width <= 0 || height <= 0) return null;
  final best = faces.reduce(
    (a, b) => a.width * a.height >= b.width * b.height ? a : b,
  );
  final left = (best.left / width).clamp(0.0, 1.0);
  final top = (best.top / height).clamp(0.0, 1.0);
  final right = ((best.left + best.width) / width).clamp(0.0, 1.0);
  final bottom = ((best.top + best.height) / height).clamp(0.0, 1.0);
  if (right <= left || bottom <= top) return null;
  return NRect(left, top, right - left, bottom - top);
}

/// Pixel size of the image after EXIF orientation (what ML Kit reports
/// boxes against). Decodes a tiny frame to learn the upright aspect cheaply.
@visibleForTesting
Future<({int width, int height})?> uprightSize(Uint8List bytes) async {
  var iw = 0;
  var ih = 0;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        iw = w;
        ih = h;
        final s = 64 / math.max(w, h);
        return ui.TargetImageSize(
          width: math.max(1, (w * s).round()),
          height: math.max(1, (h * s).round()),
        );
      },
    );
    final frame = await codec.getNextFrame();
    final rotated =
        (frame.image.width > frame.image.height) != (iw > ih) && iw != ih;
    frame.image.dispose();
    codec.dispose();
    if (iw == 0 || ih == 0) return null;
    return rotated ? (width: ih, height: iw) : (width: iw, height: ih);
  } on Object {
    return null;
  } finally {
    buffer.dispose();
  }
}
