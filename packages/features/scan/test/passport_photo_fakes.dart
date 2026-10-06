import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/src/passport_photo/passport_photo_controller.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fakes.dart';
import 'id_card_fakes.dart';

/// A face whose head exactly fills the preset's oval.
LiveFace goodFace(
  GuideGeometry g, {
  double dx = 0,
  double scale = 1,
  double? roll = 0,
  double? yaw = 0,
  double? eyes = 0.95,
}) {
  final headH = g.oval.height * scale;
  final boxH = headH / 1.3;
  final bottom = g.oval.top + g.oval.height / 2 + headH / 2;
  final w = g.oval.width * scale * 0.9;
  final cx = g.oval.left + g.oval.width / 2 + dx;
  return LiveFace(
    box: NRect(cx - w / 2, bottom - boxH, w, boxH),
    rollDegrees: roll,
    yawDegrees: yaw,
    leftEyeOpen: eyes,
    rightEyeOpen: eyes,
  );
}

LiveFaceFrame frameOf(List<LiveFace> faces, {double? brightness = 0.55}) =>
    LiveFaceFrame(faces: faces, brightness: brightness);

GuideGeometry passportGuide() =>
    GuideGeometry.forPreset(PhotoPreset.passport, previewAspect: 3 / 4);

/// Camera + detector fake driven by the test.
class FakeLiveCamera implements LiveFaceCamera {
  final controller = StreamController<LiveFaceFrame>.broadcast();
  Result<void> openResult = const Ok(null);
  Result<CapturedPhoto>? captureResult;
  CameraFacing? _facing;
  int opens = 0;
  int closes = 0;
  int captures = 0;
  final openedFacings = <CameraFacing>[];

  void emit(LiveFaceFrame f) => controller.add(f);

  @override
  Future<Result<void>> open(CameraFacing facing) async {
    opens++;
    openedFacings.add(facing);
    if (openResult.isOk) _facing = facing;
    return openResult;
  }

  @override
  CameraFacing? get facing => _facing;

  @override
  bool get canSwitchFacing => true;

  @override
  Stream<LiveFaceFrame> get frames => controller.stream;

  @override
  double? get previewAspectRatio => 3 / 4;

  @override
  bool get isMirrored => _facing == CameraFacing.front;

  @override
  Widget buildPreview() =>
      const ColoredBox(color: Colors.blueGrey, key: Key('fake-preview'));

  @override
  Future<Result<CapturedPhoto>> capture() async {
    captures++;
    return captureResult ??
        Ok(
          CapturedPhoto(
            path: '/tmp/shot.jpg',
            facing: _facing ?? CameraFacing.front,
          ),
        );
  }

  @override
  Future<void> close() async {
    closes++;
    _facing = null;
  }

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

class FakeFaceLocator implements FaceLocator {
  Result<NRect?> next = const Ok(NRect(0.35, 0.3, 0.3, 0.25));
  bool available = true;
  int calls = 0;

  @override
  Future<EngineCapability> capability() async =>
      EngineCapability(available: available, worksOffline: true);

  @override
  Future<Result<NRect?>> locateLargestFace(String imagePath) async {
    calls++;
    return next;
  }
}

/// The source still is 3000×4000; everything else reports the requested
/// output size. [compressTo] sets the compressed length.
class PassportImages extends FakeImages {
  final crops = <(NRect, int?, int?)>[];
  final compressions = <ImageCompressionOptions>[];
  final renders = <PageEdits>[];
  int outW = 413;
  int outH = 531;
  int cropBytes = 80 * 1024;
  int compressTo = 40 * 1024;

  static bool _isSource(Uint8List b) => b.length == 3;

  Uint8List _bytes(int n) => Uint8List(n)..setRange(0, kPng1x1.length, kPng1x1);

  @override
  Future<Result<EncodedImage>> crop(
    Uint8List imageBytes,
    NRect rect, {
    int? outputWidth,
    int? outputHeight,
    int quarterTurns = 0,
    ImageOutputFormat format = ImageOutputFormat.jpeg,
    int quality = 92,
  }) async {
    crops.add((rect, outputWidth, outputHeight));
    outW = outputWidth ?? outW;
    outH = outputHeight ?? outH;
    return Ok(
      EncodedImage(
        bytes: _bytes(cropBytes),
        width: outW,
        height: outH,
        format: ImageOutputFormat.jpeg,
      ),
    );
  }

  @override
  Future<Result<Uint8List>> renderPage(
    Uint8List original,
    PageEdits edits, {
    QualityPreset preset = QualityPreset.balanced,
  }) async {
    renders.add(edits);
    return Ok(_bytes(original.length));
  }

  @override
  Future<Result<EncodedImage>> compress(
    Uint8List imageBytes,
    ImageCompressionOptions options,
  ) async {
    compressions.add(options);
    return Ok(
      EncodedImage(
        bytes: _bytes(compressTo),
        width: outW,
        height: outH,
        format: ImageOutputFormat.jpeg,
      ),
    );
  }

  @override
  Future<Result<ImageDetails>> inspect(Uint8List imageBytes) async => Ok(
    _isSource(imageBytes)
        ? const ImageDetails(width: 3000, height: 4000, sizeBytes: 3)
        : ImageDetails(width: outW, height: outH, sizeBytes: imageBytes.length),
  );
}

class PassportFakes {
  final camera = FakeLiveCamera();
  final faces = FakeFaceLocator();
  final images = PassportImages();
  final files = FakeFileStore();
  final sheet = FakeSheetBuilder();
  final commit = FakeCommit();

  List<Override> get overrides => [
    liveFaceCameraProvider.overrideWithValue(camera),
    faceLocatorProvider.overrideWithValue(faces),
    imageProcessorProvider.overrideWithValue(images),
    fileStoreProvider.overrideWithValue(files),
    sheetPdfBuilderProvider.overrideWithValue(sheet),
    commitOutputProvider.overrideWithValue(commit),
  ];
}
