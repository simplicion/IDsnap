// Ads in the Tools feature (ADR-0013), with the fake ads service: the
// Tools tab (banner + one native card between groups), tool option forms
// (banner under the main button, never while a job runs), and the
// saved-file panel (one native card, and the app's only interstitial
// moment when the user leaves it).
import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/result_sheet.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

final _banner = find.byKey(AdBannerSlot.openKey);
final _native = find.byKey(AdNativeSlot.openKey);

/// A stand-in tool screen on the real [ToolScaffold]: "Run" starts a job
/// that finishes when the test says so.
class _Tool extends ConsumerWidget {
  const _Tool(this.work);

  final Completer<Result<List<OutputFile>>> Function() work;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToolScaffold(
    jobKey: 'ads-test',
    title: 'A tool',
    description: 'Choose options, then run.',
    showSaveFolder: false,
    primaryLabel: 'Run',
    onPrimary: () =>
        ref.read(jobProvider('ads-test').notifier).start((_) => work().future),
    children: const [Text('the form')],
  );
}

void main() {
  setUpAll(registerFallbacks);

  late FakeAdsService ads;
  late Harness h;
  late GoRouter router;
  late Completer<Result<List<OutputFile>>> job;

  Future<void> pump(
    WidgetTester tester, {
    MonetizationMode mode = MonetizationMode.ads,
    Size size = const Size(400, 1600),
    double textScale = 1,
    String? open,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    job = Completer();
    Widget tool(BuildContext _, GoRouterState _) => _Tool(() => job);
    router = GoRouter(
      initialLocation: Routes.tools,
      routes: [
        GoRoute(
          path: Routes.tools,
          builder: (_, _) => const ToolsScreen(),
          routes: [
            GoRoute(path: ToolId.merge.path, builder: tool),
            GoRoute(path: ToolId.compressPdf.path, builder: tool),
            GoRoute(path: ToolId.protectFile.path, builder: tool),
            GoRoute(path: ToolId.removePdfPassword.path, builder: tool),
            GoRoute(path: ToolId.signPdf.path, builder: tool),
            GoRoute(path: ToolId.mySignature.path, builder: tool),
            GoRoute(path: ToolId.photoCrop.path, builder: tool),
          ],
        ),
        GoRoute(
          path: '/files/doc/:id',
          builder: (_, _) => const Scaffold(body: Text('viewer')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          folderRepositoryProvider.overrideWithValue(FakeFolders(const [])),
          monetizationModeProvider.overrideWithValue(mode),
          adsServiceProvider.overrideWithValue(ads),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open != null) {
      router.push(open).ignore();
      await tester.pumpAndSettle();
    }
  }

  /// Runs the open tool's job to its saved-file panel.
  Future<void> finishJob(WidgetTester tester) async {
    await tester.tap(find.text('Run'));
    await tester.pump();
    job.complete(
      Ok([
        OutputFile(
          bytes: Uint8List(4),
          format: DocumentFormat.pdf,
          suggestedName: 'out',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('File saved'), findsOneWidget);
  }

  setUp(() {
    ads = FakeAdsService();
    h = Harness();
    when(
      () => h.commit(any(), folderId: any(named: 'folderId')),
    ).thenAnswer((_) async => Ok(doc('d1')));
  });

  group('Tools tab', () {
    testWidgets('one banner at the bottom, in its own space', (tester) async {
      await pump(tester, size: const Size(400, 800));
      expect(_banner, findsOneWidget);
      final banner = tester.getRect(_banner);
      expect(banner.bottom, 800);
      expect(
        tester.getRect(find.byType(SingleChildScrollView)).bottom,
        lessThanOrEqualTo(banner.top),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('one native card after the 2nd group: never above the '
        'first group or the search field', (tester) async {
      await pump(tester, size: const Size(400, 4000));
      expect(_native, findsOneWidget);
      expect(ads.nativeSizes, [AdNativeSize.small]);
      final card = tester.getRect(_native);
      double top(String text) => tester.getRect(find.text(text)).top;
      expect(card.top, greaterThan(top('Search tools')));
      expect(card.top, greaterThan(top(ToolSection.kits.title)));
      expect(card.top, greaterThan(top(ToolSection.capture.title)));
      // After every tile of the 2nd group, before the 3rd group.
      expect(
        card.top - tester.getRect(find.text('Images to PDF')).bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
      expect(
        top(ToolSection.pdf.title) - card.bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
      // It doesn't look like a tool tile: other surface colour, labelled.
      final material = tester.widget<Material>(_native);
      expect(
        material.color,
        isNot(Theme.of(tester.element(_native)).cardTheme.color),
      );
      expect(
        find.descendant(of: _native, matching: find.text('Ad')),
        findsOneWidget,
      );
      expect(find.byType(AdNativeSlot), findsOneWidget);
    });

    testWidgets('while searching there is no native card (and the banner '
        'hides with the keyboard)', (tester) async {
      await pump(tester, size: const Size(400, 4000));
      expect(_native, findsOneWidget);
      await tester.enterText(find.byType(TextField), 'pdf');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(_native, findsNothing);
      expect(find.byType(AdNativeSlot), findsNothing);
      expect(_banner, findsNothing);
      expect(ads.nativesDisposed, 1);
    });

    testWidgets('no native ad loaded: zero height, no gap', (tester) async {
      ads.nativeLoaded = false;
      await pump(tester, size: const Size(400, 4000));
      expect(_native, findsNothing);
      expect(tester.getSize(find.byType(AdNativeSlot)).height, 0);
    });

    testWidgets('no overflow at 2x text size with the banner and the native '
        'card, on a small phone', (tester) async {
      await pump(tester, size: const Size(320, 568), textScale: 2);
      expect(_banner, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        _native,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_native, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(ToolSection.convert.title),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('free build: no Pro badge on any tool', (tester) async {
      await pump(tester, size: const Size(400, 4000));
      expect(find.text('Pro'), findsNothing);
    });

    testWidgets('paid builds: no ads on the Tools tab', (tester) async {
      for (final mode in [MonetizationMode.licence, MonetizationMode.store]) {
        ads = FakeAdsService();
        await pump(tester, mode: mode, size: const Size(400, 4000));
        expect(_banner, findsNothing, reason: mode.name);
        expect(_native, findsNothing, reason: mode.name);
        expect(ads.adActivity, 0, reason: mode.name);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('tool option form', () {
    testWidgets('banner under the main button, kept apart from it; the '
        "Tools tab's own ads close underneath", (tester) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      expect(find.text('the form'), findsOneWidget);
      expect(_banner, findsOneWidget);
      final button = tester.getRect(find.widgetWithText(FilledButton, 'Run'));
      final banner = tester.getRect(_banner);
      expect(
        banner.top - button.bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.bannerButtonGap),
      );
      expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
      expect(_native, findsNothing);
    });

    testWidgets('never while the job runs: the banner is gone before the '
        'progress appears', (tester) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      expect(_banner, findsOneWidget);
      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ProgressPanel), findsOneWidget);
      expect(_banner, findsNothing);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      expect(_native, findsNothing);
      expect(ads.interstitialRequests, 0);
      job.complete(const Err(AppFailure(FailureCode.corruptFile)));
      await tester.pumpAndSettle();
      // A failure screen has no ads either.
      expect(_banner, findsNothing);
      expect(_native, findsNothing);
    });

    for (final tool in [
      ToolId.protectFile,
      ToolId.removePdfPassword,
      ToolId.signPdf,
      ToolId.mySignature,
      ToolId.photoCrop,
    ]) {
      testWidgets('${tool.name}: no banner, no native card, no interstitial', (
        tester,
      ) async {
        await pump(tester, open: Routes.tool(tool));
        expect(find.text('the form'), findsOneWidget);
        expect(_banner, findsNothing);
        await finishJob(tester);
        expect(_native, findsNothing);
        expect(_banner, findsNothing);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(ads.interstitialRequests, 0);
        // Nothing was even asked for on that screen (the Tools tab under
        // it took its own native card earlier).
        expect(ads.nativeSizes, isNot(contains(AdNativeSize.medium)));
      });
    }

    testWidgets('a tool opened for a vault document shows no ads at all', (
      tester,
    ) async {
      await pump(tester, open: Routes.tool(ToolId.merge, docId: 'd1'));
      expect(find.text('the form'), findsOneWidget);
      expect(_banner, findsNothing);
      await finishJob(tester);
      expect(_native, findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 0);
    });
  });

  group('saved-file panel', () {
    testWidgets('one native card below the result and its buttons, with '
        'space around it; no banner', (tester) async {
      await pump(tester, open: Routes.tool(ToolId.compressPdf));
      await finishJob(tester);
      expect(_banner, findsNothing);
      expect(_native, findsOneWidget);
      expect(ads.nativeSizes.last, AdNativeSize.medium);
      final card = tester.getRect(_native);
      final done = tester.getRect(find.widgetWithText(TextButton, 'Done'));
      expect(
        card.top - done.bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
      for (final label in ['Open', 'Share', 'Save to device', 'Start over']) {
        expect(
          tester.getRect(find.text(label)).bottom,
          lessThan(card.top),
          reason: label,
        );
      }
      // The result is on screen with the ad: never an ad plus an exit only.
      expect(find.text('File saved'), findsOneWidget);
      expect(find.byType(AdNativeSlot), findsOneWidget);
    });

    testWidgets('no native ad loaded: the panel looks exactly as before', (
      tester,
    ) async {
      ads.nativeLoaded = false;
      await pump(tester, open: Routes.tool(ToolId.compressPdf));
      await finishJob(tester);
      expect(_native, findsNothing);
      expect(tester.getSize(find.byType(AdNativeSlot).last).height, 0);
    });

    testWidgets('no interstitial before or during the job, nor when the '
        'result appears', (tester) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      expect(ads.interstitialRequests, 0);
      await finishJob(tester);
      expect(ads.interstitialRequests, 0);
    });

    testWidgets('Done leaves the panel: the interstitial is asked for once, '
        'and the user is back on Tools at once', (tester) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      await finishJob(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 1);
      expect(find.text('File saved'), findsNothing);
      expect(find.text('Search tools'), findsOneWidget);
    });

    testWidgets('going back from the panel counts as leaving it too', (
      tester,
    ) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      await finishJob(tester);
      router.pop();
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 1);
    });

    testWidgets('"Start over" stays in the tool: no interstitial', (
      tester,
    ) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      await finishJob(tester);
      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();
      expect(find.text('the form'), findsOneWidget);
      expect(ads.interstitialRequests, 0);
      // Back on the form: the banner returns.
      expect(_banner, findsOneWidget);
    });

    testWidgets('backing out of the form (no finished job): no '
        'interstitial', (tester) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      router.pop();
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 0);
    });

    testWidgets('no interstitial loaded: Done still closes at once', (
      tester,
    ) async {
      ads.interstitialLoaded = false;
      await pump(tester, open: Routes.tool(ToolId.merge));
      await finishJob(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Search tools'), findsOneWidget);
      expect(ads.interstitialsShown, 0);
    });

    testWidgets('no overflow at 2x text size with the native card', (
      tester,
    ) async {
      await pump(
        tester,
        open: Routes.tool(ToolId.merge),
        size: const Size(320, 568),
        textScale: 2,
      );
      await finishJob(tester);
      await tester.scrollUntilVisible(
        _native,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(_native, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inside a bottom sheet the panel never shows an ad', (
      tester,
    ) async {
      await pump(tester, open: Routes.tool(ToolId.merge));
      unawaited(
        showResultSheet(tester.element(find.text('the form')), [doc('d1')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('File saved'), findsOneWidget);
      expect(find.byType(AdNativeSlot), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 0);
    });

    testWidgets('paid builds: the panel has no ads and Done asks for none', (
      tester,
    ) async {
      await pump(
        tester,
        mode: MonetizationMode.licence,
        open: Routes.tool(ToolId.merge),
      );
      expect(_banner, findsNothing);
      await finishJob(tester);
      expect(_native, findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ads.adActivity, 0);
    });
  });
}
