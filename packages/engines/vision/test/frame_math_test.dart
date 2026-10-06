import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frameRotationDegrees', () {
    test('Android back camera compensates against device rotation', () {
      expect(
        frameRotationDegrees(
          android: true,
          front: false,
          sensorOrientation: 90,
          deviceOrientationDegrees: 0,
          bufferWidth: 1280,
          bufferHeight: 720,
        ),
        90,
      );
      expect(
        frameRotationDegrees(
          android: true,
          front: false,
          sensorOrientation: 90,
          deviceOrientationDegrees: 90,
          bufferWidth: 1280,
          bufferHeight: 720,
        ),
        0,
      );
    });

    test('Android front camera adds device rotation', () {
      expect(
        frameRotationDegrees(
          android: true,
          front: true,
          sensorOrientation: 270,
          deviceOrientationDegrees: 0,
          bufferWidth: 1280,
          bufferHeight: 720,
        ),
        270,
      );
      expect(
        frameRotationDegrees(
          android: true,
          front: true,
          sensorOrientation: 270,
          deviceOrientationDegrees: 180,
          bufferWidth: 1280,
          bufferHeight: 720,
        ),
        90,
      );
    });

    test('iOS portrait buffers need no rotation', () {
      expect(
        frameRotationDegrees(
          android: false,
          front: true,
          sensorOrientation: 90,
          deviceOrientationDegrees: 0,
          bufferWidth: 720,
          bufferHeight: 1280,
        ),
        0,
      );
      expect(
        frameRotationDegrees(
          android: false,
          front: true,
          sensorOrientation: 90,
          deviceOrientationDegrees: 0,
          bufferWidth: 1280,
          bufferHeight: 720,
        ),
        90,
      );
    });
  });

  test('uprightFrameSize swaps for quarter turns', () {
    expect(uprightFrameSize(1280, 720, 90), (width: 720, height: 1280));
    expect(uprightFrameSize(1280, 720, 180), (width: 1280, height: 720));
  });

  group('normalizeLiveBox', () {
    test('normalizes to the upright frame', () {
      final b = normalizeLiveBox(
        left: 180,
        top: 320,
        width: 360,
        height: 480,
        frameWidth: 720,
        frameHeight: 1280,
        mirror: false,
      )!;
      expect(b.left, closeTo(0.25, 1e-9));
      expect(b.top, closeTo(0.25, 1e-9));
      expect(b.width, closeTo(0.5, 1e-9));
      expect(b.height, closeTo(0.375, 1e-9));
    });

    test('mirrors horizontally for the front camera', () {
      final b = normalizeLiveBox(
        left: 0,
        top: 0,
        width: 72,
        height: 100,
        frameWidth: 720,
        frameHeight: 1000,
        mirror: true,
      )!;
      expect(b.left, closeTo(0.9, 1e-9));
      expect(b.right, closeTo(1, 1e-9));
    });

    test('rejects degenerate boxes', () {
      expect(
        normalizeLiveBox(
          left: 800,
          top: 0,
          width: 10,
          height: 10,
          frameWidth: 720,
          frameHeight: 1000,
          mirror: false,
        ),
        isNull,
      );
    });
  });

  group('meanLuminance', () {
    test('reads the Y plane of NV21', () {
      const w = 64;
      const h = 48;
      // Y plane at 128 followed by chroma bytes that must be ignored.
      final bytes = Uint8List(w * h * 3 ~/ 2)..fillRange(0, w * h, 128);
      final l = meanLuminance(
        bytes,
        width: w,
        height: h,
        bytesPerRow: w,
        bgra: false,
      )!;
      expect(l, closeTo(128 / 255, 1e-9));
    });

    test('computes luma for BGRA pixels with row padding', () {
      const w = 10;
      const h = 10;
      const stride = 48; // 40 bytes of pixels + 8 padding
      final bytes = Uint8List(stride * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * stride + x * 4;
          bytes[i + 2] = 255; // pure red
          bytes[i + 3] = 255;
        }
      }
      final l = meanLuminance(
        bytes,
        width: w,
        height: h,
        bytesPerRow: stride,
        bgra: true,
      )!;
      expect(l, closeTo(0.299, 1e-3));
    });

    test('returns null when the buffer is too small', () {
      expect(
        meanLuminance(
          Uint8List(10),
          width: 100,
          height: 100,
          bytesPerRow: 100,
          bgra: false,
        ),
        isNull,
      );
    });
  });

  test('LiveCameraFailure carries a typed, actionable message', () {
    final f = LiveCameraFailure(LiveCameraIssue.permissionDenied);
    expect(f.code, FailureCode.permissionDenied);
    expect(f.title, 'Camera permission needed');
    expect(f.recovery, contains('Settings'));
    expect(
      LiveCameraFailure(LiveCameraIssue.noCamera).nextAction,
      FailureAction.pickDifferentFile,
    );
  });

  test(
    'CameraFaceSession reports unsupported platforms without throwing',
    () async {
      final session = CameraFaceSession();
      final r = await session.open(CameraFacing.front);
      // Tests run on the desktop host, where the camera path is unsupported.
      expect(
        (r.failureOrNull! as LiveCameraFailure).issue,
        LiveCameraIssue.unsupportedPlatform,
      );
      await session.dispose();
    },
  );
}
