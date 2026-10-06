import 'dart:async';
import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// [CodeScanner] for the QR & barcode tool on `mobile_scanner`, the same
/// plugin and bundled on-device model as the authenticator's QR scanner
/// (Android: `com.google.mlkit:barcode-scanning`, never the Play-services
/// download; iOS: Apple Vision). Runs entirely on the device.
class MobileCodeScanner implements CodeScanner {
  const MobileCodeScanner();

  static const cameraDenied =
      'Allow camera access in Settings, or choose a picture of the code '
      'instead.';

  /// Every symbology the tool supports.
  static const formats = [
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.aztec,
    BarcodeFormat.pdf417,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.itf14,
    BarcodeFormat.codabar,
  ];

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<EngineCapability> capability() async => EngineCapability(
    available: _supported,
    worksOffline: true,
    note: _supported ? null : 'The camera scanner works on Android and iOS.',
  );

  @override
  Widget buildPreview(
    BuildContext context, {
    required CodeScannerController controller,
    required ValueChanged<List<ScannedCode>> onDetect,
    required ValueChanged<AppFailure> onError,
  }) => _Preview(controller: controller, onDetect: onDetect, onError: onError);

  @override
  Future<Result<List<ScannedCode>>> decodeImage(String path) async {
    final controller = MobileScannerController(
      autoStart: false,
      formats: formats,
    );
    try {
      final capture = await controller.analyzeImage(path, formats: formats);
      return Ok(toCodes(capture?.barcodes ?? const []));
    } on MobileScannerException catch (e, st) {
      return Err(_map(e, st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    } finally {
      unawaited(controller.dispose());
    }
  }

  /// Distinct, non-empty codes in detection order.
  static List<ScannedCode> toCodes(List<Barcode> barcodes) {
    final seen = <ScannedCode>{};
    for (final b in barcodes) {
      final code = ScannedCode.from(
        rawValue: b.rawValue,
        symbology: symbologyOf(b.format),
        bytes: switch (b.rawDecodedBytes) {
          DecodedBarcodeBytes(:final bytes) => bytes,
          DecodedVisionBarcodeBytes(:final bytes) => bytes,
          null => null,
        },
      );
      if (code.raw.isNotEmpty) seen.add(code);
    }
    return seen.toList();
  }

  static CodeSymbology symbologyOf(BarcodeFormat format) => switch (format) {
    BarcodeFormat.qrCode || BarcodeFormat.microQrCode => CodeSymbology.qr,
    BarcodeFormat.dataMatrix => CodeSymbology.dataMatrix,
    BarcodeFormat.aztec => CodeSymbology.aztec,
    BarcodeFormat.pdf417 => CodeSymbology.pdf417,
    BarcodeFormat.ean13 => CodeSymbology.ean13,
    BarcodeFormat.ean8 => CodeSymbology.ean8,
    BarcodeFormat.upcA => CodeSymbology.upcA,
    BarcodeFormat.upcE => CodeSymbology.upcE,
    BarcodeFormat.code128 => CodeSymbology.code128,
    BarcodeFormat.code39 => CodeSymbology.code39,
    BarcodeFormat.code93 => CodeSymbology.code93,
    BarcodeFormat.itf14 ||
    BarcodeFormat.itf2of5 ||
    BarcodeFormat.itf2of5WithChecksum => CodeSymbology.itf,
    BarcodeFormat.codabar => CodeSymbology.codabar,
    _ => CodeSymbology.unknown,
  };

  static AppFailure _map(MobileScannerException e, [StackTrace? st]) =>
      switch (e.errorCode) {
        MobileScannerErrorCode.permissionDenied => AppFailure(
          FailureCode.permissionDenied,
          message: cameraDenied,
          action: FailureAction.pickDifferentFile,
          cause: e,
          stackTrace: st,
        ),
        MobileScannerErrorCode.unsupported => AppFailure(
          FailureCode.cameraUnavailable,
          detail: 'This device has no usable camera.',
          action: FailureAction.pickDifferentFile,
          cause: e,
          stackTrace: st,
        ),
        _ => AppFailure(
          FailureCode.cameraUnavailable,
          cause: e,
          stackTrace: st,
        ),
      };
}

class _Preview extends StatefulWidget {
  const _Preview({
    required this.controller,
    required this.onDetect,
    required this.onError,
  });

  final CodeScannerController controller;
  final ValueChanged<List<ScannedCode>> onDetect;
  final ValueChanged<AppFailure> onError;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  // Normal speed: the scan screen de-duplicates repeats itself, so the same
  // code can be scanned again after a short pause.
  final _camera = MobileScannerController(formats: MobileCodeScanner.formats);
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    widget.controller.torch.addListener(_syncTorch);
    widget.controller.paused.addListener(_syncPaused);
    _camera.addListener(_onCameraState);
  }

  @override
  void dispose() {
    widget.controller.torch.removeListener(_syncTorch);
    widget.controller.paused.removeListener(_syncPaused);
    _camera.removeListener(_onCameraState);
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onCameraState() {
    final torch = _camera.value.torchState;
    widget.controller.torchAvailable.value = torch != TorchState.unavailable;
  }

  Future<void> _syncTorch() async {
    final want = widget.controller.torch.value;
    final state = _camera.value.torchState;
    if (state == TorchState.unavailable) return;
    final on = state == TorchState.on;
    if (want != on) {
      try {
        await _camera.toggleTorch();
      } on Object {
        // Torch busy or unsupported; the button simply has no effect.
      }
    }
  }

  Future<void> _syncPaused() async {
    try {
      if (widget.controller.paused.value) {
        await _camera.stop();
      } else {
        await _camera.start();
        await _syncTorch();
      }
    } on Object {
      // Camera already in the requested state or closing.
    }
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _camera,
    onDetect: (capture) {
      if (widget.controller.paused.value) return;
      final codes = MobileCodeScanner.toCodes(capture.barcodes);
      if (codes.isNotEmpty) widget.onDetect(codes);
    },
    errorBuilder: (context, error) {
      if (!_reported) {
        _reported = true;
        // Report after this build; the screen swaps in an explanation.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onError(MobileCodeScanner._map(error)),
        );
      }
      return const ColoredBox(color: Colors.black);
    },
  );
}
