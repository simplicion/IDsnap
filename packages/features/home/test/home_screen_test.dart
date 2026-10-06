import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Drafts implements DraftStore {
  _Drafts(this.draft);
  ScanDraft? draft;

  @override
  Future<ScanDraft?> load() async => draft;
  @override
  Future<void> save(ScanDraft d) async => draft = d;
  @override
  Future<void> clear({bool deleteImages = true}) async => draft = null;
}

class _Repo extends Mock implements DocumentRepository {
  _Repo(this.docs);
  final List<Document> docs;

  @override
  Stream<List<Document>> watch(DocumentQuery query) =>
      Stream.value(docs.take(query.limit ?? docs.length).toList());
}

class _Settings implements SettingsStore {
  _Settings(this.settings);
  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings s) async => settings = s;
}

class _Files extends Mock implements FileStore {
  @override
  String absolute(String relativePath) => '/app/$relativePath';
}

Document _doc(int i, {DocumentFormat format = DocumentFormat.pdf}) => Document(
  id: 'd$i',
  name: 'Invoice $i',
  format: format,
  relativePath: 'documents/d$i.${format.extension}',
  sizeBytes: 1000 * i,
  pageCount: format == DocumentFormat.pdf ? i : null,
  createdAt: DateTime(2026, 9, 2),
  updatedAt: DateTime(2026, 9, 2),
);

List<Override> _overrides({
  List<Document> docs = const [],
  ScanDraft? draft,
  AppSettings settings = const AppSettings(),
}) => [
  settingsStoreProvider.overrideWithValue(_Settings(settings)),
  draftStoreProvider.overrideWithValue(_Drafts(draft)),
  documentRepositoryProvider.overrideWithValue(_Repo(docs)),
  fileStoreProvider.overrideWithValue(_Files()),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Document> docs = const [],
  ScanDraft? draft,
  double textScale = 1,
  ThemeData? theme,
  AppSettings settings = const AppSettings(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(docs: docs, draft: draft, settings: settings),
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: HomeScreen(now: DateTime(2026, 9, 24, 9)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The free build's banner (the default mode): it promises what stays on
/// the phone rather than "offline", because ads use the internet.
const _privacyBanner =
    'Private vault · Your documents, IDs and codes never leave this phone';

void main() {
  testWidgets('first run shows the hero, quick tools and an empty library', (
    tester,
  ) async {
    _phone(tester);
    await _pump(tester);

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Works offline'), findsOneWidget);
    expect(find.text('No account. Files stay on this phone.'), findsOneWidget);
    expect(find.text('Scan a document'), findsOneWidget);
    for (final title in [
      'Import photos',
      'Import PDF',
      'Extract text',
      'Merge PDFs',
      'Compress PDF',
      'Take passport-size photo',
      'Crop a photo',
      'Compress image',
      'All tools',
    ]) {
      await tester.scrollUntilVisible(find.text(title), 100);
      expect(find.text(title), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Nothing here yet'), 200);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Unfinished scan'), findsNothing);
  });

  testWidgets('recent files are listed with type and page count', (
    tester,
  ) async {
    _phone(tester);
    await _pump(
      tester,
      docs: [
        _doc(2),
        _doc(1, format: DocumentFormat.jpeg),
      ],
      theme: AppTheme.dark(),
    );
    await tester.scrollUntilVisible(find.text('Invoice 2'), 200);

    expect(find.text('Invoice 2'), findsOneWidget);
    expect(find.text('Invoice 1'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.textContaining('JPG'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('an unfinished draft shows the resume banner', (tester) async {
    _phone(tester);
    final draft = ScanDraft(
      id: 'x',
      createdAt: DateTime.now(),
      pages: const [
        ScanPage(id: 'a', originalPath: '/o/a.jpg'),
        ScanPage(id: 'b', originalPath: '/o/b.jpg'),
      ],
    );
    await _pump(tester, draft: draft);
    expect(find.text('Unfinished scan'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('200% text size lays out without overflow', (tester) async {
    _phone(tester);
    await _pump(tester, docs: [_doc(3), _doc(4)], textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Invoice 3'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Scan a document'), findsNothing); // scrolled away
  });

  testWidgets('tablet width uses a four-column grid', (tester) async {
    tester.view
      ..physicalSize = const Size(1024, 1366)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    final a = tester.getTopLeft(find.text('ID card (front & back)'));
    final d = tester.getTopLeft(find.text('Extract text'));
    expect(d.dy, a.dy, reason: 'first four tools share a row');
  });

  testWidgets('tapping the hero opens the scan flow', (tester) async {
    _phone(tester);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => HomeScreen(now: DateTime(2026, 9, 24, 15)),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, state) =>
              Text('scan:${state.uri.queryParameters['source']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good afternoon'), findsOneWidget);
    await tester.tap(find.text('Scan a document'));
    await tester.pumpAndSettle();
    expect(find.text('scan:camera'), findsOneWidget);
  });

  testWidgets('ID card is the first quick action and opens its flow', (
    tester,
  ) async {
    _phone(tester);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => HomeScreen(now: DateTime(2026, 9, 24, 15)),
        ),
        GoRoute(
          path: '/scan/id-card',
          builder: (_, _) => const Text('ID CARD FLOW'),
        ),
        GoRoute(
          path: '/tools/kits/:id',
          builder: (_, s) => Text('KIT ${s.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final id = tester.getTopLeft(find.text('ID card (front & back)'));
    final photos = tester.getTopLeft(find.text('Import photos'));
    expect(id.dy, lessThanOrEqualTo(photos.dy));
    expect(id.dx, lessThan(photos.dx));
    await tester.tap(find.text('ID card (front & back)'));
    await tester.pumpAndSettle();
    expect(find.text('ID CARD FLOW'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Square photo (2 × 2 in)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Square photo (2 × 2 in)'));
    await tester.pumpAndSettle();
    expect(find.text('KIT us-visa'), findsOneWidget);
  });

  testWidgets('application kits section lists three kits', (tester) async {
    _phone(tester);
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.text('Passport size photo (35 × 45 mm)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Application kits'), findsOneWidget);
    expect(find.text('Square photo (2 × 2 in)'), findsOneWidget);
    expect(find.text('Exam portal pack'), findsOneWidget);
    // Presets are named by size term, never by country.
    expect(
      find.textContaining(
        RegExp(r'\b(US|USA|UK|India|Canada|Schengen|China|Aadhaar|PAN)\b'),
      ),
      findsNothing,
    );
    expect(find.text('Passport size photo (35 × 45 mm)'), findsOneWidget);
  });

  testWidgets('privacy banner shows by default and can be dismissed', (
    tester,
  ) async {
    _phone(tester);
    await _pump(tester);
    expect(find.text(_privacyBanner), findsOneWidget);
    await tester.tap(find.byTooltip('Hide for now'));
    await tester.pumpAndSettle();
    expect(find.text(_privacyBanner), findsNothing);
  });

  testWidgets('app bar shows the IDSnap brand and tagline', (tester) async {
    _phone(tester);
    await _pump(tester);
    expect(find.text('IDSnap'), findsOneWidget);
    expect(find.text('Identity & Everyday Document Vault'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('Authenticator'), findsOneWidget);
    // No stale brand anywhere on Home.
    expect(find.textContaining('DocScan'), findsNothing);
  });

  testWidgets('settings gear pushes Settings and the Authenticator card '
      'switches tabs', (tester) async {
    _phone(tester);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => HomeScreen(now: DateTime(2026, 9, 24, 15)),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => const Scaffold(body: Text('SETTINGS')),
        ),
        GoRoute(
          path: '/authenticator',
          builder: (_, _) => const Scaffold(body: Text('AUTHENTICATOR')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
    // Pushed, not a tab switch: Home stays underneath.
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Authenticator'));
    await tester.pumpAndSettle();
    expect(find.text('AUTHENTICATOR'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('privacy banner respects the settings switch', (tester) async {
    _phone(tester);
    await _pump(tester, settings: const AppSettings(showPrivacyBanner: false));
    expect(find.text(_privacyBanner), findsNothing);
  });
}
