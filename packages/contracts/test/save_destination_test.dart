import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Folders implements FolderRepository {
  _Folders(this.folders);

  final List<Folder> folders;

  @override
  Future<List<Folder>> allFolders() async => folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(folders);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Folder _folder(
  String id,
  String name, {
  String? parentId,
  FolderLockMode lockMode = FolderLockMode.none,
}) => Folder(
  id: id,
  name: name,
  parentId: parentId,
  lockMode: lockMode,
  createdAt: DateTime(2026),
);

final _tree = [
  _folder('fam', 'Family'),
  _folder('kids', 'Kids', parentId: 'fam'),
  _folder('priv', 'Private', lockMode: FolderLockMode.pin),
  _folder('deep', 'Deep secret', parentId: 'priv'),
];

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [folderRepositoryProvider.overrideWithValue(_Folders(_tree))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SaveFolderField(flow: 'test')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to the top level and browses unlocked folders', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('ID Vault'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kids'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save in Kids'));
    await tester.pumpAndSettle();
    expect(container.read(saveFolderProvider('test')), 'kids');
    expect(find.text('ID Vault › Family › Kids'), findsOneWidget);
    // Remembered as the default of the next flow.
    expect(container.read(lastSaveFolderProvider), 'kids');
    container.read(saveFolderProvider('other').notifier).start(null);
    expect(container.read(saveFolderProvider('other')), 'kids');
  });

  testWidgets('a locked folder can be chosen but never opened '
      '(its subfolders stay hidden)', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Locked · save here without opening it'), findsOneWidget);
    expect(find.text('Deep secret'), findsNothing);
    await tester.tap(find.text('Private'));
    await tester.pumpAndSettle();
    // Chosen directly (write-only), the sheet closed without browsing in.
    expect(container.read(saveFolderProvider('test')), 'priv');
    expect(find.text('Deep secret'), findsNothing);
    expect(find.textContaining('Locked folder: unlock it'), findsOneWidget);
  });

  testWidgets('a folder unlocked this session can be browsed', (tester) async {
    await pump(tester);
    container.read(unlockedFoldersProvider.notifier).publish({'priv'});
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private'));
    await tester.pumpAndSettle();
    expect(find.text('Deep secret'), findsOneWidget);
  });

  testWidgets('the folder a flow starts from wins over the last choice', (
    tester,
  ) async {
    await pump(tester);
    container.read(lastSaveFolderProvider.notifier).remember('kids');
    container.read(saveFolderProvider('test').notifier).start('fam');
    await tester.pumpAndSettle();
    expect(find.text('ID Vault › Family'), findsOneWidget);
  });

  test('a deleted folder resolves to the top level', () async {
    final repo = _Folders(_tree);
    expect(await existingSaveFolder(() => repo, 'fam'), 'fam');
    expect(await existingSaveFolder(() => repo, 'gone'), isNull);
    expect(
      await existingSaveFolder(() => throw StateError('unused'), null),
      isNull,
    );
  });

  test('Routes pass the folder to ID card and passport photo', () {
    expect(Routes.idCard(folderId: 'f1'), '/scan/id-card?folder=f1');
    expect(Routes.idCard(), '/scan/id-card');
    expect(
      Routes.passportPhoto(folderId: 'f1'),
      '/scan/passport-photo?folder=f1',
    );
    expect(Routes.passportPhoto(), Routes.passportPhotoCamera);
    expect(
      proFeatureForLocation(Uri.parse(Routes.idCard(folderId: 'f1'))),
      ProFeature.idCard,
    );
  });
}
