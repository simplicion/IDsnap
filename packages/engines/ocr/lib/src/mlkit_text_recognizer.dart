import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_ocr/src/imaging_ocr_preparer.dart'
    show ImagingOcrPreparer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

/// On-device OCR with Google ML Kit Text Recognition v2 (bundled models).
///
/// Latin is always bundled by the plugin. Other scripts need the app to add
/// the matching model dependency (Android: `com.google.mlkit:text-recognition-
/// <script>`; iOS: `GoogleMLKit/TextRecognition<Script>` pod) and list the
/// script in [bundledScripts]. [bundledScripts] must match the native build
/// exactly: a script listed here but not linked crashes on Android and
/// silently reads with the Latin model on iOS. Images never leave the device.
///
/// This adapter recognizes one file as is. For EXIF/rotation/scale handling,
/// Auto script, reading order and multi-page PDFs, wrap it in the domain's
/// `RecognizeText` / `RecognizeDocument` with an [ImagingOcrPreparer].
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
      // Never instantiate a recognizer whose model isn't linked: on Android
      // that throws NoClassDefFoundError (an Error, which crashes the app),
      // and on iOS the plugin silently falls back to the Latin model.
      return Err(
        AppFailure(
          FailureCode.modelUnavailable,
          detail: script.shortLabel,
          message: cap.note,
        ),
      );
    }
    final file = File(imagePath);
    if (!file.existsSync()) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    if (file.lengthSync() == 0) {
      return const Err(AppFailure(FailureCode.emptyFile));
    }

    // Pre-flight: the image must decode on this device, otherwise ML Kit
    // fails with an opaque error. Typed here so the UI can say why.
    final ui.Size size;
    try {
      size = await _imageSize(imagePath).timeout(const Duration(seconds: 20));
    } on Object catch (e, st) {
      _log.warn('decode_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(
          FailureCode.unsupportedFormat,
          message:
              "This image can't be opened on this phone. Save it as JPG or "
              'PNG and try again.',
          cause: e,
          stackTrace: st,
        ),
      );
    }

    try {
      final recognizer = _recognizers.putIfAbsent(
        script,
        () => mlkit.TextRecognizer(script: toMlKitScript(script)),
      );
      final started = DateTime.now();
      final text = await recognizer
          .processImage(mlkit.InputImage.fromFilePath(imagePath))
          .timeout(recognizeTimeout);
      final result = toOcrResult(text, size.width, size.height, script);
      _log.info('recognized', {
        'script': script,
        'lines': result.lines.length,
        'ms': DateTime.now().difference(started).inMilliseconds,
      });
      return Ok(result);
    } on PlatformException catch (e, st) {
      final code = classifyMlKitError(e.code, e.message);
      _log.warn('platform_error', {'code': code});
      return Err(
        code == FailureCode.unknown
            ? _ocrFailed(e, st)
            : AppFailure(code, cause: e, stackTrace: st),
      );
    } on MissingPluginException catch (e, st) {
      _log.error('plugin_missing', {});
      return Err(
        AppFailure(
          FailureCode.modelUnavailable,
          message: "Text recognition isn't available in this build.",
          action: FailureAction.none,
          cause: e,
          stackTrace: st,
        ),
      );
    } on TimeoutException catch (e, st) {
      return Err(AppFailure(FailureCode.timeout, cause: e, stackTrace: st));
      // Deliberate: report exhausted memory as a typed, recoverable failure.
      // ignore: avoid_catching_errors
    } on OutOfMemoryError catch (e, st) {
      return Err(
        AppFailure(FailureCode.memoryLimitExceeded, cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      _log.error('ocr_failed', {'type': e.runtimeType.toString()});
      return Err(_ocrFailed(e, st));
    }
  }

  /// Upper bound for one recognition call.
  static const recognizeTimeout = Duration(seconds: 60);

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
FailureCode mapPlatformCode(String code) => classifyMlKitError(code, null);

/// Classifies an ML Kit platform error using both its code and message.
/// The plugin reports most failures with the generic code
/// `TextRecognizerError`, so the message carries the real reason.
FailureCode classifyMlKitError(String code, String? message) {
  final c = '${code.toLowerCase()} ${message?.toLowerCase() ?? ''}';
  bool has(List<String> words) => words.any(c.contains);
  if (has([
    'model',
    'classnotfound',
    'noclassdef',
    'not available',
    'unavailable',
    'download',
  ])) {
    return FailureCode.modelUnavailable;
  }
  if (has(['outofmemory', 'out of memory', 'oom'])) {
    return FailureCode.memoryLimitExceeded;
  }
  if (has(['no such file', 'filenotfound', 'enoent'])) {
    return FailureCode.notFound;
  }
  if (has(['heic', 'heif', 'unsupported', 'format'])) {
    return FailureCode.unsupportedFormat;
  }
  if (has(['decode', 'bitmap', 'image', 'invalid', 'corrupt'])) {
    return FailureCode.corruptFile;
  }
  if (has(['timeout', 'timed out', 'deadline'])) {
    return FailureCode.timeout;
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
                angle: l.angle,
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

/// Text recognition stopped for an unexpected reason (audit M-04).
AppFailure _ocrFailed(Object e, StackTrace st) => AppFailure(
  FailureCode.unknown,
  cause: e,
  stackTrace: st,
  heading: "Text couldn't be read",
  message:
      'Your file is unchanged. Try again; if it keeps failing, use a '
      'sharper photo or restart IDSnap.',
  action: FailureAction.retry,
);
