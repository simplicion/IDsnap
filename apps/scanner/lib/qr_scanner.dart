import 'dart:async';
import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// [QrScanner] on `mobile_scanner`. Fully offline: Android links the
/// bundled ML Kit barcode model (`com.google.mlkit:barcode-scanning`, not the
/// Play-services download; `useUnbundled` is never set), iOS uses Apple
/// Vision. Runs entirely on the device.
class MobileQrScanner implements QrScanner {
  const MobileQrScanner();

  static const cameraDenied =
      'Allow camera access in Settings, or choose a screenshot of the QR '
      'code instead.';

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
    required ValueChanged<String> onDetect,
    required ValueChanged<AppFailure> onError,
  }) => _Preview(onDetect: onDetect, onError: onError);

  @override
  Future<Result<String?>> decodeImage(String path) async {
    final controller = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
    try {
      final capture = await controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      final raw = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      return Ok(raw);
    } on MobileScannerException catch (e, st) {
      return Err(_map(e, st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    } finally {
      unawaited(controller.dispose());
    }
  }

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
  const _Preview({required this.onDetect, required this.onError});

  final ValueChanged<String> onDetect;
  final ValueChanged<AppFailure> onError;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _reported = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _controller,
    onDetect: (capture) {
      for (final b in capture.barcodes) {
        final raw = b.rawValue;
        if (raw != null && raw.isNotEmpty) {
          widget.onDetect(raw);
          return;
        }
      }
    },
    errorBuilder: (context, error) {
      if (!_reported) {
        _reported = true;
        // Report after this build; the screen swaps in an explanation.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onError(MobileQrScanner._map(error)),
        );
      }
      return const ColoredBox(color: Colors.black);
    },
  );
}
