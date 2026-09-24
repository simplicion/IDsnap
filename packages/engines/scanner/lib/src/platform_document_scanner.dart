import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

/// Signature of the platform capture call, injectable for tests.
typedef CaptureFn = Future<List<String>?> Function(int maxPages);

Future<List<String>?> _cunningCapture(int maxPages) =>
    CunningDocumentScanner.getPictures(
      noOfPages: maxPages,
      scannerSource: ScannerSource.camera,
    );

/// Document camera: Google ML Kit Document Scanner on Android, VisionKit
/// (`VNDocumentCameraViewController`) on iOS. Both detect edges, correct
/// perspective and return cropped page images; processing is on-device.
///
/// On Android the scanner UI/model ships as a Google Play services module
/// that may be downloaded on first use, so the capability reports
/// `requiresDownload` — after that it works offline.
class PlatformDocumentScanner implements DocumentScanner {
  PlatformDocumentScanner({
    @visibleForTesting CaptureFn? capture,
    @visibleForTesting TargetPlatform? platform,
    RedactedLogger? logger,
  }) : _capture = capture ?? _cunningCapture,
       _platform = platform ?? (kIsWeb ? null : defaultTargetPlatform),
       _log = logger ?? RedactedLogger('scanner');

  final CaptureFn _capture;
  final TargetPlatform? _platform;
  final RedactedLogger _log;

  @override
  Future<EngineCapability> capability() async => switch (_platform) {
    TargetPlatform.android => const EngineCapability(
      available: true,
      worksOffline: true,
      requiresDownload: true,
      note:
          'Uses the Google Play services document scanner. It may download '
          'once on first use; afterwards it works offline.',
    ),
    TargetPlatform.iOS => const EngineCapability(
      available: true,
      worksOffline: true,
    ),
    _ => const EngineCapability(
      available: false,
      worksOffline: false,
      note: 'The document camera is available on Android and iOS.',
    ),
  };

  @override
  Future<Result<List<String>>> scan({int maxPages = 50}) async {
    if (!(await capability()).available) {
      return const Err(AppFailure(FailureCode.cameraUnavailable));
    }
    try {
      final pages = await _capture(maxPages.clamp(1, 100));
      if (pages == null || pages.isEmpty) {
        return const Err(AppFailure(FailureCode.captureCancelled));
      }
      final existing = pages.where((p) => File(p).existsSync()).toList();
      if (existing.isEmpty) {
        return const Err(AppFailure(FailureCode.cameraUnavailable));
      }
      _log.info('scanned', {'pages': existing.length});
      return Ok(existing);
    } on CunningDocumentScannerException catch (e, st) {
      return Err(AppFailure(mapScannerError(e.code), cause: e, stackTrace: st));
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.cameraUnavailable, cause: e, stackTrace: st),
      );
    }
  }
}

/// Maps native error codes to failure categories.
FailureCode mapScannerError(String? code) {
  final c = (code ?? '').toLowerCase();
  if (c.contains('permission') || c.contains('denied')) {
    return FailureCode.permissionDenied;
  }
  if (c.contains('cancel')) return FailureCode.captureCancelled;
  if (c.contains('module') || c.contains('play') || c.contains('unavailable')) {
    return FailureCode.offlineDependencyUnavailable;
  }
  return FailureCode.cameraUnavailable;
}
