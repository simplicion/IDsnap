import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fakes.dart';

/// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _vaultPath = '/abs/documents/p.pdf';

/// PDFium stand-in: the vault copy asks for a password; the unlocked temp
/// copy (written by [_FakeProtector]) opens with 2 pages.
class _FakePdf implements PdfEngine {
  final opened = <String>[];

  @override
  Future<Result<int>> pageCount(String path) async {
    opened.add(path);
    return path == _vaultPath
        ? const Err(AppFailure(FailureCode.passwordProtected))
        : const Ok(2);
  }

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) async => Ok(_png);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProtector implements PdfProtector {
  final attempts = <String>[];

  @override
  Future<Result<bool>> needsPassword(String path) async =>
      Ok(path == _vaultPath);

  @override
  Future<Result<ProtectedFile>> removePdfPassword(
    String inputPath,
    String password, {
    required String outputPath,
  }) async {
    attempts.add(password);
    if (password != 'secret') {
      return const Err(AppFailure(FailureCode.wrongPassword));
    }
    return Ok(
      ProtectedFile(
        path: outputPath,
        format: DocumentFormat.pdf,
        sizeBytes: 10,
        pageCount: 2,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePdf pdf;
  late _FakeProtector protector;
  late FakeFileStore files;

  setUp(() {
    pdf = _FakePdf();
    protector = _FakeProtector();
    files = FakeFileStore();
  });

  List<Override> overrides(
    FakeRepository repo, {
    EntitlementState entitlement = const MonthlyEntitlement(),
  }) => [
    ...baseOverrides(repo, files),
    pdfEngineProvider.overrideWithValue(pdf),
    pdfProtectorProvider.overrideWithValue(protector),
    // A paid mode: the default build is free with ads (ADR-0013).
    monetizationModeProvider.overrideWithValue(MonetizationMode.licence),
    entitlementServiceProvider.overrideWithValue(
      StaticEntitlementService(entitlement),
    ),
  ];

  /// A router with the library plus stub scan/tool screens.
  Widget app(List<Override> overrides, {String at = '/files/doc/p'}) {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/files',
          builder: (_, _) => const FilesScreen(),
          routes: libraryRoutes(root),
        ),
        GoRoute(
          path: '/scan/id-card',
          builder: (_, s) => Text('id card ${s.uri.queryParameters['folder']}'),
        ),
        GoRoute(
          path: '/scan/passport-photo',
          builder: (_, s) =>
              Text('passport ${s.uri.queryParameters['folder']}'),
        ),
        GoRoute(
          path: '/tools/:tool',
          builder: (_, s) => Text(
            'tool ${s.pathParameters['tool']} ${s.uri.queryParameters['doc']}',
          ),
        ),
        GoRoute(path: '/paywall', builder: (_, _) => const Text('paywall')),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  FakeRepository protectedRepo() => FakeRepository([
    doc('p', 'Contract', DocumentFormat.pdf),
    doc('n', 'Plain', DocumentFormat.pdf),
  ]);

  group('viewer: password-protected PDF', () {
    testWidgets('asks for the password, then shows the pages', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(app(overrides(protectedRepo())));
      await tester.pumpAndSettle();

      // Prompted straight away; the panel stays behind the dialog.
      expect(find.text('Password needed'), findsOneWidget);
      expect(find.text('This PDF is password-protected'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'secret',
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Password needed'), findsNothing);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      // Rendered from the unlocked temp copy, never from the vault file.
      expect(pdf.opened.last, '/tmp/x.pdf');
      expect(protector.attempts, ['secret']);

      // Leaving the viewer removes the unlocked temp copy.
      files.deleted.clear();
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
      expect(files.deleted, contains('/tmp/x.pdf'));
    });

    testWidgets('a wrong password shows an error and allows a retry', (
      tester,
    ) async {
      useTallPhone(tester);
      await tester.pumpWidget(app(overrides(protectedRepo())));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'nope',
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining("That password isn't right"), findsOneWidget);
      expect(find.text('Password needed'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'secret',
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(protector.attempts, ['nope', 'secret']);
    });

    testWidgets('cancel keeps the file locked; it can be asked again', (
      tester,
    ) async {
      useTallPhone(tester);
      await tester.pumpWidget(app(overrides(protectedRepo())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Password needed'), findsNothing);
      expect(find.text('This PDF is password-protected'), findsOneWidget);
      expect(find.text('Remove password…'), findsOneWidget);

      await tester.tap(find.text('Enter password'));
      await tester.pumpAndSettle();
      expect(find.text('Password needed'), findsOneWidget);
    });

    testWidgets('"Remove password" opens the tool for this document', (
      tester,
    ) async {
      useTallPhone(tester);
      await tester.pumpWidget(app(overrides(protectedRepo())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove password…'));
      await tester.pumpAndSettle();
      expect(find.text('tool remove-pdf-password p'), findsOneWidget);
    });
  });

  testWidgets('lists show a lock badge and a locked-PDF thumbnail', (
    tester,
  ) async {
    useTallPhone(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(overrides(protectedRepo()), at: '/files'));
    await tester.pumpAndSettle();
    expect(find.text('Contract'), findsWidgets);
    expect(find.byKey(const ValueKey('protected-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-pdf-thumb')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Password-protected')), findsWidgets);
    semantics.dispose();
  });

  group('+ menu', () {
    testWidgets('ID card and passport photo open for the current folder', (
      tester,
    ) async {
      useTallPhone(tester);
      final repo = FakeRepository([], folders: [folder('fam', 'Family')]);
      await tester.pumpWidget(app(overrides(repo), at: '/files/folder/fam'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      expect(find.text('ID card (front & back)'), findsOneWidget);
      expect(find.text('Passport-size photo'), findsOneWidget);
      // Entitled: no PRO badges.
      expect(find.text('PRO'), findsNothing);
      await tester.tap(find.text('ID card (front & back)'));
      await tester.pumpAndSettle();
      expect(find.text('id card fam'), findsOneWidget);
    });

    testWidgets('passport photo passes the folder too', (tester) async {
      useTallPhone(tester);
      final repo = FakeRepository([], folders: [folder('fam', 'Family')]);
      await tester.pumpWidget(app(overrides(repo), at: '/files/folder/fam'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Passport-size photo'));
      await tester.pumpAndSettle();
      expect(find.text('passport fam'), findsOneWidget);
    });

    testWidgets('PRO badges show only when the policy locks them', (
      tester,
    ) async {
      useTallPhone(tester);
      final repo = FakeRepository([], folders: [folder('fam', 'Family')]);
      await tester.pumpWidget(
        app(
          overrides(
            repo,
            entitlement: const ExpiredEntitlement(
              reason: LapseReason.trialEnded,
            ),
          ),
          at: '/files/folder/fam',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      // Scan, ID card, passport photo are Pro; folder and upload are free.
      expect(find.text('PRO'), findsNWidgets(3));
      await tester.tap(find.text('ID card (front & back)'));
      await tester.pumpAndSettle();
      expect(find.text('paywall'), findsOneWidget);
    });
  });

  testWidgets('viewer tool chips carry PRO badges only when locked', (
    tester,
  ) async {
    useTallPhone(tester);
    final repo = FakeRepository([doc('t', 'Notes', DocumentFormat.txt)]);
    await tester.pumpWidget(app(overrides(repo), at: '/files/doc/t'));
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsNothing);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      app(
        overrides(
          FakeRepository([doc('t', 'Notes', DocumentFormat.txt)]),
          entitlement: const ExpiredEntitlement(reason: LapseReason.trialEnded),
        ),
        at: '/files/doc/t',
      ),
    );
    await tester.pumpAndSettle();
    // Text documents offer one chip: Convert (Pro).
    expect(
      find.descendant(
        of: find.widgetWithText(ActionChip, 'Convert'),
        matching: find.text('PRO'),
      ),
      findsOneWidget,
    );
  });
}
