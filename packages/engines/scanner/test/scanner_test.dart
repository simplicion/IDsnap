import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:engine_scanner/engine_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformDocumentScanner', () {
    test('capability is honest per platform', () async {
      final android = await PlatformDocumentScanner(
        platform: TargetPlatform.android,
      ).capability();
      expect(android.available && android.requiresDownload, isTrue);

      final ios = await PlatformDocumentScanner(
        platform: TargetPlatform.iOS,
      ).capability();
      expect(ios.available && !ios.requiresDownload, isTrue);

      final windows = await PlatformDocumentScanner(
        platform: TargetPlatform.windows,
      ).capability();
      expect(windows.available, isFalse);
    });

    test('unsupported platform fails without calling capture', () async {
      var called = false;
      final r = await PlatformDocumentScanner(
        platform: TargetPlatform.linux,
        capture: (_) async {
          called = true;
          return null;
        },
      ).scan();
      expect(called, isFalse);
      expect(r.failureOrNull?.code, FailureCode.cameraUnavailable);
    });

    test('null / empty result means cancelled', () async {
      final r = await PlatformDocumentScanner(
        platform: TargetPlatform.android,
        capture: (_) async => null,
      ).scan();
      expect(r.failureOrNull?.code, FailureCode.captureCancelled);
    });

    test('returns existing page paths and clamps page count', () async {
      final tmp = await Directory.systemTemp.createTemp('scan');
      addTearDown(() => tmp.delete(recursive: true));
      final page = File('${tmp.path}/p1.jpg')..writeAsBytesSync([1, 2, 3]);
      int? requested;
      final r = await PlatformDocumentScanner(
        platform: TargetPlatform.iOS,
        capture: (n) async {
          requested = n;
          return [page.path, '${tmp.path}/missing.jpg'];
        },
      ).scan(maxPages: 500);
      expect(requested, 100);
      expect(r.valueOrNull, [page.path]);
    });

    test('native exceptions map to typed failures', () async {
      final r = await PlatformDocumentScanner(
        platform: TargetPlatform.android,
        capture: (_) async => throw const CunningDocumentScannerException(
          'no',
          code: 'PERMISSION_DENIED',
        ),
      ).scan();
      expect(r.failureOrNull?.code, FailureCode.permissionDenied);
      expect(
        mapScannerError('MODULE_UNAVAILABLE'),
        FailureCode.offlineDependencyUnavailable,
      );
      expect(mapScannerError(null), FailureCode.cameraUnavailable);
    });
  });

  test('pickerExtensions expands aliases and skips unknown', () {
    expect(
      pickerExtensions({
        DocumentFormat.jpeg,
        DocumentFormat.pdf,
        DocumentFormat.unknown,
      }),
      ['jpeg', 'jpg', 'pdf'],
    );
    expect(pickerExtensions({}), isEmpty);
  });
}
