import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

/// On-device OCR with Google ML Kit Text Recognition v2 (bundled models).
///
/// Latin is always bundled by the plugin. Other scripts need the app to add
/// the matching model dependency (Android: `com.google.mlkit:text-recognition-
/// <script>`; iOS: `GoogleMLKit/TextRecognition<Script>` pod) and list the
/// script in [bundledScripts]. Images never leave the device.
class MlKitTextRecognizer implements TextRecognizer {
  MlKitTextRecognizer({
    this.bundledScripts = const {OcrScript.latin},
    @visibleForTesting bool? isSupportedPlatform,
    RedactedLogger? logger,
  }) : _platformOk =
           isSupportedPlatform ??
           (!kIsWeb && (Platform.isAndroid || Platform.isIOS)),
       _log = logger ?? RedactedLogger('ocr');

  final Set<OcrScript> bundledScripts;
  final bool _platformOk;
  final RedactedLogger _log;
  final Map<OcrScript, mlkit.TextRecognizer> _recognizers = {};

  @override
  Future<EngineCapability> capability(OcrScript script) async {
    if (!_platformOk) {
      return const EngineCapability(
        available: false,
        worksOffline: false,
        note: 'Text recognition is available on Android and iOS.',
      );
    }
    if (!bundledScripts.contains(script)) {
      return EngineCapability(
        available: false,
        worksOffline: false,
        note: '${script.label} is not installed in this build.',
      );
    }
    return const EngineCapability(available: true, worksOffline: true);
  }

  @override
  Future<Result<OcrResult>> recognize(
    String imagePath,
    OcrScript script,
  ) async {
    final cap = await capability(script);
    if (!cap.available) {
      return const Err(AppFailure(FailureCode.modelUnavailable));
    }
    if (!File(imagePath).existsSync()) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    try {
      final size = await _imageSize(imagePath);
      final recognizer = _recognizers.putIfAbsent(
        script,
        () => mlkit.TextRecognizer(script: toMlKitScript(script)),
      );
      final started = DateTime.now();
      final text = await recognizer.processImage(
        mlkit.InputImage.fromFilePath(imagePath),
      );
      final result = toOcrResult(text, size.width, size.height, script);
      _log.info('recognized', {
        'script': script,
        'lines': result.lines.length,
        'ms': DateTime.now().difference(started).inMilliseconds,
      });
      return Ok(result);
    } on PlatformException catch (e, st) {
      _log.warn('platform_error', {'code': e.code});
      return Err(AppFailure(mapPlatformCode(e.code), cause: e, stackTrace: st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.unknown, cause: e, stackTrace: st));
    }
  }

  /// Releases native recognizers. Call when the app shuts down.
  Future<void> close() async {
    for (final r in _recognizers.values) {
      await r.close();
    }
    _recognizers.clear();
  }

  /// Reads image dimensions from the header without decoding pixels.
  static Future<ui.Size> _imageSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = ui.Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
}

mlkit.TextRecognitionScript toMlKitScript(OcrScript s) => switch (s) {
  OcrScript.latin => mlkit.TextRecognitionScript.latin,
  OcrScript.devanagari => mlkit.TextRecognitionScript.devanagiri,
  OcrScript.chinese => mlkit.TextRecognitionScript.chinese,
  OcrScript.japanese => mlkit.TextRecognitionScript.japanese,
  OcrScript.korean => mlkit.TextRecognitionScript.korean,
};

/// Missing model classes / unavailable modules surface as platform errors.
FailureCode mapPlatformCode(String code) {
  final c = code.toLowerCase();
  if (c.contains('model') ||
      c.contains('unavailable') ||
      c.contains('classnotfound') ||
      c.contains('noclassdef')) {
    return FailureCode.modelUnavailable;
  }
  if (c.contains('image') || c.contains('decode')) {
    return FailureCode.corruptFile;
  }
  return FailureCode.unknown;
}

/// Converts ML Kit output (pixel boxes) into domain [OcrResult] with boxes
/// normalized to the image size and clamped to 0..1.
OcrResult toOcrResult(
  mlkit.RecognizedText text,
  double imageWidth,
  double imageHeight,
  OcrScript script,
) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    return OcrResult(blocks: const [], script: script);
  }
  return OcrResult(
    script: script,
    blocks: [
      for (final b in text.blocks)
        OcrBlock([
          for (final l in b.lines)
            if (l.text.trim().isNotEmpty)
              OcrLine(
                l.text,
                normalizeRect(l.boundingBox, imageWidth, imageHeight),
                confidence: l.confidence,
              ),
        ]),
    ].where((b) => b.lines.isNotEmpty).toList(),
  );
}

NRect normalizeRect(ui.Rect r, double w, double h) {
  final left = (r.left / w).clamp(0.0, 1.0);
  final top = (r.top / h).clamp(0.0, 1.0);
  final right = (r.right / w).clamp(0.0, 1.0);
  final bottom = (r.bottom / h).clamp(0.0, 1.0);
  return NRect(left, top, right - left, bottom - top);
}
