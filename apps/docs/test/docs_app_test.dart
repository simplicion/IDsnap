import 'dart:convert';

import 'package:docscan_docs/src/app.dart';
import 'package:docscan_docs/src/docs_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBundle extends CachingAssetBundle {
  FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Missing asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

final String _manifest = jsonEncode({
  'title': 'Test Docs',
  'sections': [
    {
      'title': 'Overview',
      'pages': [
        {'title': 'Welcome', 'path': 'index.md'},
      ],
    },
    {
      'title': 'Guides',
      'pages': [
        {'title': 'Testing', 'path': 'guides/testing.md'},
      ],
    },
  ],
});

FakeBundle _bundle() => FakeBundle({
  'assets/docs/manifest.json': _manifest,
  'assets/docs/index.md':
      '# Welcome home\n\nRead the [testing guide](guides/testing.md).\n\n## Promises\n\nOffline first.',
  'assets/docs/guides/testing.md':
      '# Testing\n\n| Layer | Tool |\n|---|---|\n| Unit | test |\n\n## Airplane mode\n\nChecklist.',
});

void main() {
  group('path helpers', () {
    test('location <-> path', () {
      expect(pathToLocation('index.md'), '/');
      expect(pathToLocation('product/PRD.md'), '/product/PRD');
      expect(locationToPath('/'), 'index.md');
      expect(locationToPath('/product/PRD'), 'product/PRD.md');
    });

    test('resolves relative links and anchors', () {
      final r = resolveDocLink(
        'adr/0001-x.md',
        '../guides/testing.md#device-matrix',
      );
      expect(r?.path, 'guides/testing.md');
      expect(r?.anchor, 'device-matrix');
      expect(resolveDocLink('index.md', 'https://flutter.dev'), isNull);
      expect(resolveDocLink('index.md', '#promises')?.path, 'index.md');
    });

    test('splits sections outside code fences', () {
      const md =
          '# T\nintro\n## A\ntext\n```\n## not a heading\n```\n### B\nmore';
      final sections = splitSections(md);
      expect(sections.map((s) => s.heading), [null, 'A', 'B']);
      expect(sections[1].anchor, 'a');
      expect(slugify('4.1 Color tokens'), '41-color-tokens');
    });
  });

  test('search finds titles and body text', () async {
    final repo = DocsRepository(bundle: _bundle());
    final hits = await repo.search('airplane');
    expect(hits.single.page.path, 'guides/testing.md');
    expect((await repo.search('welcome')).first.titleMatch, isTrue);
    expect(await repo.search('   '), isEmpty);
  });

  testWidgets('renders home, navigates via nav and links', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DocsApp(bundle: _bundle()));
    await tester.pumpAndSettle();

    expect(find.text('Test Docs'), findsOneWidget);
    expect(find.text('Welcome home'), findsOneWidget);
    expect(find.text('GUIDES'), findsOneWidget);

    await tester.tap(find.text('Testing').first);
    await tester.pumpAndSettle();
    expect(find.text('Airplane mode'), findsOneWidget);
    expect(find.text('Unit'), findsOneWidget); // table cell
  });

  testWidgets('phone layout uses a drawer', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DocsApp(bundle: _bundle()));
    await tester.pumpAndSettle();
    expect(find.text('GUIDES'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('GUIDES'), findsOneWidget);
  });

  testWidgets('unknown page shows a friendly empty state', (tester) async {
    await tester.pumpWidget(
      DocsApp(bundle: _bundle(), initialLocation: '/nope'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
  });
}
