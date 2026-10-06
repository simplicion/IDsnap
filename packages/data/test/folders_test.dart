import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Document _doc(String name, {String? folderId, bool favorite = false}) {
  final t = DateTime(2026);
  return Document(
    id: newId(),
    name: name,
    format: DocumentFormat.pdf,
    relativePath: 'documents/$name.pdf',
    sizeBytes: 100,
    folderId: folderId,
    favorite: favorite,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  late Directory tmp;
  late DataLayer data;
  late DriftDocumentRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('docscan_folders');
    data = await openDataLayer(
      rootOverride: tmp.path,
      executor: NativeDatabase.memory(),
    );
    repo = data.documents;
  });

  tearDown(() async {
    await data.close();
    await tmp.delete(recursive: true);
  });

  Future<Folder> mk(String name, {String? parent}) async =>
      (await repo.createFolder(name: name, parentId: parent)).valueOrNull!;

  Future<Document> put(String name, {String? folder}) async {
    final d = _doc(name, folderId: folder);
    expect((await repo.add(d)).isOk, isTrue);
    return d;
  }

  test('nesting: contents, breadcrumb and recursive stats', () async {
    final a = await mk('A');
    final b = await mk('B', parent: a.id);
    final c = await mk('C', parent: b.id);
    await mk('Z');
    await put('root file');
    await put('in a', folder: a.id);
    await put('in c 1', folder: c.id);
    await put('in c 2', folder: c.id);

    final root = await repo.watchContents(null).first;
    expect(root.folders.map((f) => f.name), ['A', 'Z']);
    expect(root.documents.map((d) => d.name), ['root file']);
    final inA = await repo.watchContents(a.id).first;
    expect(inA.folders.single.id, b.id);
    expect(inA.documents.single.name, 'in a');

    final crumbs = await repo.breadcrumb(c.id);
    expect(crumbs.map((f) => f.name), ['A', 'B', 'C']);

    final tree = FolderTree(await repo.allFolders());
    final counts = await repo.watchDirectCounts().first;
    expect(counts[null], 1);
    expect(counts[c.id], 2);
    final stats = tree.stats(counts);
    expect(stats[a.id], const FolderStats(folders: 2, documents: 3));
    expect(stats[b.id], const FolderStats(folders: 1, documents: 2));
    expect(stats[c.id], const FolderStats(documents: 2));
  });

  test('names: trimmed, validated, unique among siblings only', () async {
    final a = await mk('  Taxes  ');
    expect(a.name, 'Taxes');
    final dup = await repo.createFolder(name: 'taxes');
    expect(dup.isOk, isFalse);
    expect(dup.failureOrNull?.message, contains('already exists'));
    expect((await repo.createFolder(name: '   ')).isOk, isFalse);
    expect((await repo.createFolder(name: 'x' * 61)).isOk, isFalse);
    // Same name in another folder is fine.
    expect(
      (await repo.createFolder(name: 'Taxes', parentId: a.id)).isOk,
      isTrue,
    );

    final b = await mk('Bills');
    expect((await repo.renameFolder(b.id, 'TAXES')).isOk, isFalse);
    expect((await repo.renameFolder(b.id, ' Bills 2026 ')).isOk, isTrue);
    expect(
      (await repo.allFolders()).any((f) => f.name == 'Bills 2026'),
      isTrue,
    );
    // Renaming to its own name (different case) is allowed.
    expect((await repo.renameFolder(b.id, 'bills 2026')).isOk, isTrue);
  });

  test('move: cycle prevention, name clashes, and to top level', () async {
    final a = await mk('A');
    final b = await mk('B', parent: a.id);
    final c = await mk('C', parent: b.id);

    expect((await repo.moveFolder(a.id, a.id)).isOk, isFalse);
    final cycle = await repo.moveFolder(a.id, c.id);
    expect(cycle.isOk, isFalse);
    expect(cycle.failureOrNull?.message, contains('into itself'));
    expect((await repo.breadcrumb(c.id)).map((f) => f.name), ['A', 'B', 'C']);

    await mk('C'); // top-level "C" clashes with moving c up.
    expect((await repo.moveFolder(c.id, null)).isOk, isFalse);

    expect((await repo.moveFolder(b.id, null)).isOk, isTrue);
    final root = await repo.watchContents(null).first;
    expect(root.folders.map((f) => f.name), ['A', 'B', 'C']);
    expect((await repo.breadcrumb(c.id)).map((f) => f.name), ['B', 'C']);
  });

  test('delete with contents removes the whole subtree', () async {
    final a = await mk('A');
    final b = await mk('B', parent: a.id);
    final keep = await put('keep');
    final d1 = await put('d1', folder: a.id);
    final d2 = await put('d2', folder: b.id);

    final removed = await repo.deleteFolder(
      a.id,
      FolderDeleteMode.deleteContents,
    );
    expect(
      removed.valueOrNull!.map((d) => d.id),
      unorderedEquals([d1.id, d2.id]),
    );
    expect(await repo.allFolders(), isEmpty);
    expect(await repo.byId(d1.id), isNull);
    expect(await repo.byId(d2.id), isNull);
    expect(await repo.byId(keep.id), isNotNull);
  });

  test('delete moving contents to the parent keeps everything', () async {
    final a = await mk('A');
    final b = await mk('B', parent: a.id);
    await mk('C', parent: b.id);
    await mk('C', parent: a.id); // Clashes with b's child after the move.
    final d = await put('d', folder: b.id);

    final removed = await repo.deleteFolder(
      b.id,
      FolderDeleteMode.moveContentsToParent,
    );
    expect(removed.valueOrNull, isEmpty);
    expect((await repo.byId(d.id))?.folderId, a.id);
    final inA = await repo.watchContents(a.id).first;
    expect(inA.folders.map((f) => f.name), ['C', 'C (2)']);

    // The legacy API moves a top-level folder's contents to the top level.
    await repo.removeFolder(a.id);
    final root = await repo.watchContents(null).first;
    expect(root.folders.map((f) => f.name), ['C', 'C (2)']);
    expect(root.documents.single.id, d.id);
  });

  test('moveDocuments and unknown folders', () async {
    final a = await mk('A');
    final d = await put('d');
    expect((await repo.moveDocuments([d.id], a.id)).isOk, isTrue);
    expect((await repo.byId(d.id))?.folderId, a.id);
    expect((await repo.moveDocuments([d.id], 'nope')).isOk, isFalse);
    expect((await repo.moveDocuments([d.id], null)).isOk, isTrue);
    expect((await repo.byId(d.id))?.folderId, isNull);
  });

  test('locked folders never leak through global lists or search', () async {
    final vault = await mk('Private');
    final inner = await mk('Inner', parent: vault.id);
    final open = await mk('Open');
    await put('secret passport', folder: vault.id);
    await put('secret deep', folder: inner.id);
    await put('public passport', folder: open.id);
    await put('loose passport');
    await repo.setFolderLockMode(vault.id, FolderLockMode.pin);

    final all = await repo.watch(const DocumentQuery()).first;
    expect(
      all.map((d) => d.name),
      unorderedEquals(['public passport', 'loose passport']),
    );
    // Folder names inside a locked folder are hidden; the locked folder
    // itself stays visible.
    final visible = await repo.watchFolders().first;
    expect(visible.map((f) => f.name), unorderedEquals(['Open', 'Private']));

    final search = await repo
        .watchSearch(const FolderSearch(text: 'secret'))
        .first;
    expect(search, isEmpty);
    final searchAll = await repo
        .watchSearch(const FolderSearch(text: 'passport'))
        .first;
    expect(searchAll, hasLength(2));

    // Unlocked for the session: the subtree (inner inherits) is searchable.
    final unlocked = await repo
        .watchSearch(
          FolderSearch(text: 'secret', unlockedFolderIds: {vault.id}),
        )
        .first;
    expect(unlocked, hasLength(2));
    final scoped = await repo
        .watchSearch(
          FolderSearch(
            text: 'secret',
            withinFolderId: inner.id,
            unlockedFolderIds: {vault.id},
          ),
        )
        .first;
    expect(scoped.single.name, 'secret deep');

    // A locked folder inside an unlocked one still needs its own unlock.
    await repo.setFolderLockMode(inner.id, FolderLockMode.device);
    final nested = await repo
        .watchSearch(
          FolderSearch(text: 'secret', unlockedFolderIds: {vault.id}),
        )
        .first;
    expect(nested.single.name, 'secret passport');

    // Lists update live when a lock is removed.
    final stream = repo.watch(const DocumentQuery());
    await repo.setFolderLockMode(vault.id, FolderLockMode.none);
    await repo.setFolderLockMode(inner.id, FolderLockMode.none);
    expect((await stream.first).length, 4);
  });

  test('stats never count what a locked subfolder holds', () async {
    final a = await mk('A');
    final locked = await mk('Locked', parent: a.id);
    await put('x', folder: a.id);
    await put('y', folder: locked.id);
    await repo.setFolderLockMode(locked.id, FolderLockMode.pin);
    final tree = FolderTree(await repo.allFolders());
    final stats = tree.stats(
      await repo.watchDirectCounts().first,
      hidden: tree.hiddenContentIds(const {}),
    );
    expect(stats[a.id], const FolderStats(folders: 1, documents: 1));
    expect(tree.isAccessible(locked.id, const {}), isFalse);
    expect(tree.isAccessible(locked.id, {locked.id}), isTrue);
    expect(tree.isAccessible(a.id, const {}), isTrue);
  });
}
