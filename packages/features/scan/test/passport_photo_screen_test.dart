import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'id_card_fakes.dart' show FakeFolders, testFolder;
import 'passport_photo_fakes.dart';

void main() {
  late PassportFakes fakes;

  setUp(() => fakes = PassportFakes());

  Future<void> pump(
    WidgetTester tester, {
    String at = '/scan/passport-photo',
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(
          path: '/files/doc/:id',
          builder: (_, s) => Text('DOC ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/tools/photo-crop',
          builder: (_, _) => const Text('PHOTO CROP TOOL'),
        ),
        ...scanRoutes(),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...fakes.overrides, ...extra],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Emits [n] frames 150 ms apart (the engine's throttle).
  Future<void> feed(
    WidgetTester tester,
    LiveFaceFrame Function() frame, {
    int n = 1,
  }) async {
    for (var i = 0; i < n; i++) {
      fakes.camera.emit(frame());
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  LiveFaceFrame good() => frameOf([goodFace(passportGuide())]);

  String hint(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('passport-hint'))).data!;

  testWidgets('opens the front camera and shows the size presets', (
    tester,
  ) async {
    await pump(tester);
    expect(fakes.camera.openedFacings, [CameraFacing.front]);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    expect(find.text('Passport size (35 × 45 mm)'), findsOneWidget);
    expect(hint(tester), 'Look at the camera');
    // Term-specific wording only.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(
      RegExp(r'\b(US|Green Card|Schengen|India|UK|Canada)\b').hasMatch(texts),
      isFalse,
    );
  });

  testWidgets('good frames → countdown → auto-capture → review', (
    tester,
  ) async {
    await pump(tester);
    await feed(tester, () => frameOf([]));
    expect(hint(tester), contains('no face found'));

    await feed(tester, good, n: 7);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();

    expect(fakes.camera.captures, 1);
    expect(fakes.camera.closes, greaterThanOrEqualTo(1));
    expect(fakes.faces.calls, 1);
    expect(find.text('Your photo'), findsOneWidget);
    expect(find.byKey(const Key('passport-result')), findsOneWidget);
    expect(find.textContaining('413 × 531 px'), findsOneWidget);
    expect(fakes.images.crops.single.$2, 413);
  });

  testWidgets('a failing frame resets the dwell; cancel stops auto-capture', (
    tester,
  ) async {
    await pump(tester);
    await feed(tester, good, n: 4);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await feed(tester, () => frameOf([goodFace(passportGuide(), yaw: 30)]));
    expect(hint(tester), 'Look straight at the camera');
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await feed(tester, good, n: 7);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await feed(tester, good, n: 30);
    expect(fakes.camera.captures, 0);
    expect(hint(tester), 'Looks good — tap the shutter');
    expect(
      tester.widget<Switch>(find.byKey(const Key('auto-capture'))).value,
      isFalse,
    );
  });

  testWidgets('manual shutter, then save as JPEG', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    expect(fakes.camera.captures, 1);
    expect(find.text('Your photo'), findsOneWidget);

    await tapVisible(tester, find.text('Save as JPEG'));
    await tester.pump();
    await tester.pump();
    expect(fakes.commit.outputs.single.format, DocumentFormat.jpeg);
    expect(fakes.commit.outputs.single.suggestedName, 'Passport size photo');
    expect(find.text('Photo saved to ID Vault'), findsOneWidget);
  });

  testWidgets('started from a folder: the photo is saved into it', (
    tester,
  ) async {
    await pump(
      tester,
      at: '/scan/passport-photo?folder=fam',
      extra: [
        folderRepositoryProvider.overrideWithValue(
          FakeFolders([testFolder('fam', 'Family')]),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    expect(find.text('ID Vault › Family'), findsOneWidget);
    await tapVisible(tester, find.text('Save as JPEG'));
    await tester.pump();
    await tester.pump();
    expect(fakes.commit.folderIds.single, 'fam');
    expect(find.text('Photo saved to ID Vault › Family'), findsOneWidget);
  });

  testWidgets('no face in the still falls back and says so', (tester) async {
    fakes.faces.next = const Ok(null);
    await pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("couldn't find a face"), findsOneWidget);
  });

  testWidgets('print sheet: 6 photos on 4 × 6 in paper', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    await tapVisible(tester, find.text('Print sheet (4 × 6 in or A4)'));
    await tester.pumpAndSettle();
    expect(find.text('6 of 6 photos'), findsOneWidget);
    await tester.tap(find.text('Create print sheet (PDF)'));
    await tester.pumpAndSettle();
    final call = fakes.sheet.calls.single;
    expect(call.$1, hasLength(6));
    expect(call.$2, closeTo(101.6 * 72 / 25.4, 1e-6));
    expect(fakes.commit.outputs.single.format, DocumentFormat.pdf);
    expect(fakes.commit.outputs.single.expectedPages, 1);
  });

  testWidgets('custom size with a KB limit compresses to that limit', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.text('Custom…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('px'));
    await tester.enterText(find.byKey(const Key('custom-width')), '350');
    await tester.enterText(find.byKey(const Key('custom-height')), '450');
    await tester.enterText(find.byKey(const Key('custom-kb')), '50');
    await tester.tap(find.text('Use this size'));
    await tester.pumpAndSettle();
    expect(find.text('Custom (350 × 450 px, max 50 KB)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    expect(fakes.images.crops.single.$2, 350);
    expect(fakes.images.compressions.single.targetBytes, 50 * 1024);
    expect(
      tester.widget<Text>(find.byKey(const Key('passport-size'))).data,
      contains('limit 50 KB'),
    );
  });

  testWidgets('camera permission denied shows an actionable message', (
    tester,
  ) async {
    fakes.camera.openResult = Err(
      LiveCameraFailure(LiveCameraIssue.permissionDenied),
    );
    await pump(tester);
    expect(find.text('Camera permission needed'), findsOneWidget);
    expect(find.textContaining('Settings'), findsOneWidget);

    fakes.camera.openResult = const Ok(null);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(fakes.camera.opens, 2);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
  });

  testWidgets('no camera offers cropping an existing photo', (tester) async {
    fakes.camera.openResult = Err(LiveCameraFailure(LiveCameraIssue.noCamera));
    await pump(tester);
    expect(find.text('No camera found'), findsOneWidget);
    await tester.tap(find.text(FailureAction.pickDifferentFile.label));
    await tester.pumpAndSettle();
    expect(find.text('PHOTO CROP TOOL'), findsOneWidget);
  });

  testWidgets('detector failure switches to manual capture', (tester) async {
    await pump(tester);
    fakes.camera.controller.addError(
      LiveCameraFailure(LiveCameraIssue.detectorUnavailable),
    );
    await tester.pump();
    await tester.pump();
    expect(hint(tester), contains("Face detection isn't available"));
    final auto = tester.widget<Switch>(find.byKey(const Key('auto-capture')));
    expect(auto.value, isFalse);
    expect(auto.onChanged, isNull);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    expect(fakes.camera.captures, 1);
  });

  testWidgets('releases the camera on pause and reopens on resume', (
    tester,
  ) async {
    await pump(tester);
    final closes = fakes.camera.closes;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fakes.camera.closes, greaterThan(closes));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(fakes.camera.opens, 2);
  });

  testWidgets('switching camera reopens with the back camera', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Use back camera'));
    await tester.pump();
    await tester.pump();
    expect(fakes.camera.openedFacings, [CameraFacing.front, CameraFacing.back]);
  });

  testWidgets('retake returns to the camera', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await tester.pump();
    await tapVisible(tester, find.text('Retake'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    expect(fakes.camera.opens, 2);
  });
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
