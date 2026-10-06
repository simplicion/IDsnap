import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/database.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart';

/// [DocumentRepository] and [FolderRepository] on Drift/SQLite.
///
/// Folders nest through `folders.parent_id`. Structural rules (no cycles,
/// unique sibling names, cascading deletes) are enforced here rather than
/// with SQL cascades so every delete path is explicit and testable.
class DriftDocumentRepository implements DocumentRepository, FolderRepository {
  DriftDocumentRepository(this._db);

  final AppDatabase _db;

  static const List<DocumentFormat> _imageFormats = [
    DocumentFormat.jpeg,
    DocumentFormat.png,
    DocumentFormat.webp,
    DocumentFormat.heic,
    DocumentFormat.gif,
    DocumentFormat.bmp,
    DocumentFormat.tiff,
  ];
  static const List<DocumentFormat> _textFormats = [
    DocumentFormat.txt,
    DocumentFormat.markdown,
    DocumentFormat.html,
    DocumentFormat.csv,
    DocumentFormat.docx,
    DocumentFormat.xlsx,
    DocumentFormat.pptx,
  ];

  /// Re-runs [load] whenever documents or folders change (lock state lives
  /// on folders, so document listings depend on both tables).
  Stream<T> _live<T>(Future<T> Function() load) => _db
      .customSelect('SELECT 1', readsFrom: {_db.documents, _db.folders})
      .watch()
      .asyncMap((_) => load());

  Future<FolderTree> _tree() async => FolderTree(await allFolders());

  // ── Documents ─────────────────────────────────────────────────────────────

  @override
  Stream<List<Document>> watch(DocumentQuery query) => _live(() async {
    final q = _db.select(_db.documents);
    _applySearch(q, query.search);
    _applyFilter(q, query.filter);
    final folder = query.folderId;
    if (folder != null) {
      q.where((t) => t.folderId.equals(folder));
    } else {
      // Global lists (recents, pickers, search) never reveal what a locked
      // folder holds.
      final hidden = (await _tree()).hiddenContentIds(const {});
      if (hidden.isNotEmpty) {
        q.where((t) => t.folderId.isNull() | t.folderId.isNotIn(hidden));
      }
    }
    final category = query.category;
    if (category != null) q.where((t) => t.category.equals(category.name));
    _applySort(q, query.sort);
    final limit = query.limit;
    if (limit != null) q.limit(limit);
    return (await q.get()).map(_toDomain).toList();
  });

  void _applySearch(
    SimpleSelectStatement<$DocumentsTable, DocumentRow> q,
    String raw,
  ) {
    final search = raw.trim();
    if (search.isEmpty) return;
    final escaped = search
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    q.where((t) => t.name.like('%$escaped%', escapeChar: r'\'));
  }

  void _applyFilter(
    SimpleSelectStatement<$DocumentsTable, DocumentRow> q,
    DocumentFilter filter,
  ) {
    switch (filter) {
      case DocumentFilter.all:
        break;
      case DocumentFilter.pdf:
        q.where((t) => t.format.equals(DocumentFormat.pdf.name));
      case DocumentFilter.images:
        q.where((t) => t.format.isIn(_imageFormats.map((f) => f.name)));
      case DocumentFilter.text:
        q.where((t) => t.format.isIn(_textFormats.map((f) => f.name)));
      case DocumentFilter.favorites:
        q.where((t) => t.favorite.equals(true));
    }
  }

  void _applySort(
    SimpleSelectStatement<$DocumentsTable, DocumentRow> q,
    DocumentSort sort,
  ) => q.orderBy([
    (t) => switch (sort) {
      DocumentSort.newest => OrderingTerm.desc(t.updatedAt),
      DocumentSort.oldest => OrderingTerm.asc(t.updatedAt),
      DocumentSort.nameAz => OrderingTerm.asc(t.name.collate(Collate.noCase)),
      DocumentSort.largest => OrderingTerm.desc(t.sizeBytes),
    },
  ]);

  /// Live document counts per vault category (uncategorized excluded).
  Stream<Map<DocumentCategory, int>> watchCategoryCounts() {
    final count = _db.documents.id.count();
    final q = _db.selectOnly(_db.documents)
      ..addColumns([_db.documents.category, count])
      ..where(_db.documents.category.isNotNull())
      ..groupBy([_db.documents.category]);
    return q.watch().map((rows) {
      final byName = DocumentCategory.values.asNameMap();
      return {
        for (final r in rows)
          ?byName[r.read(_db.documents.category)]: r.read(count) ?? 0,
      };
    });
  }

  /// All documents (used by the library archiver).
  Future<List<Document>> all() async =>
      (await _db.select(_db.documents).get()).map(_toDomain).toList();

  @override
  Future<Document?> byId(String id) async {
    final row = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<Result<void>> add(Document document) => guard(() async {
    final filed = await _fileByCategory(document, previous: null);
    await _db.into(_db.documents).insert(_toRow(filed));
  }, code: FailureCode.insufficientStorage);

  @override
  Future<Result<void>> update(Document document) => guard(() async {
    final previous = await byId(document.id);
    if (previous == null) throw const AppFailure(FailureCode.notFound);
    final filed = await _fileByCategory(document, previous: previous);
    final ok = await _db.update(_db.documents).replace(_toRow(filed));
    if (!ok) throw const AppFailure(FailureCode.notFound);
  });

  /// Backward compatibility for flows that still categorize (ID card,
  /// application kits): when a document *gains* a category while it has no
  /// folder, it's filed into the top-level folder made from the matching
  /// template, if the user has one. Nothing is created automatically.
  Future<Document> _fileByCategory(
    Document d, {
    required Document? previous,
  }) async {
    final category = d.category;
    if (category == null || d.folderId != null) return d;
    if (previous != null && previous.category == category) return d;
    final folder =
        await (_db.select(_db.folders)
              ..where(
                (t) =>
                    t.parentId.isNull() & t.templateKey.equals(category.name),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return folder == null ? d : d.copyWith(folderId: folder.id);
  }

  @override
  Future<Result<void>> remove(String id) => guard(() async {
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
  });

  @override
  Future<Result<void>> moveDocuments(
    List<String> documentIds,
    String? folderId,
  ) => guard(() async {
    if (documentIds.isEmpty) return;
    if (folderId != null && await _folderRow(folderId) == null) {
      throw const AppFailure(
        FailureCode.notFound,
        message: 'That folder no longer exists. Choose another one.',
      );
    }
    await (_db.update(
      _db.documents,
    )..where((t) => t.id.isIn(documentIds))).write(
      DocumentsCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  // ── Folders (legacy DocumentRepository API) ───────────────────────────────

  @override
  Stream<List<Folder>> watchFolders() => _live(() async {
    final tree = await _tree();
    final hidden = tree.hiddenContentIds(const {});
    return [
      for (final f in tree.all)
        if (!hidden.contains(f.parentId)) f,
    ]..sort(FolderTree.compareFolders);
  });

  @override
  Future<Result<Folder>> addFolder(String name) =>
      createFolder(name: FolderNames.clean(name).isEmpty ? 'New folder' : name);

  @override
  Future<Result<void>> removeFolder(String id) async => (await deleteFolder(
    id,
    FolderDeleteMode.moveContentsToParent,
  )).map<void>((_) {});

  // ── Folders ───────────────────────────────────────────────────────────────

  @override
  Stream<List<Folder>> watchAllFolders() =>
      _db.select(_db.folders).watch().map((rows) => rows.map(_folder).toList());

  @override
  Future<List<Folder>> allFolders() async =>
      (await _db.select(_db.folders).get()).map(_folder).toList();

  Future<FolderRow?> _folderRow(String id) => (_db.select(
    _db.folders,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<String>> _siblingNames(String? parentId, {String? except}) async {
    final q = _db.select(_db.folders)
      ..where(
        (t) => parentId == null
            ? t.parentId.isNull()
            : t.parentId.equals(parentId),
      );
    return [
      for (final r in await q.get())
        if (r.id != except) r.name,
    ];
  }

  static AppFailure _invalid(String message) => AppFailure(
    FailureCode.unknown,
    detail: message,
    message: message,
    action: FailureAction.none,
  );

  @override
  Future<Result<Folder>> createFolder({
    required String name,
    String? parentId,
    String? templateKey,
    String? icon,
    String? color,
  }) => guard(
    () => _db.transaction(() async {
      if (parentId != null && await _folderRow(parentId) == null) {
        throw const AppFailure(FailureCode.notFound);
      }
      final error = FolderNames.validate(name, await _siblingNames(parentId));
      if (error != null) throw _invalid(error);
      final now = DateTime.now();
      final folder = Folder(
        id: newId(),
        name: FolderNames.clean(name),
        createdAt: now,
        parentId: parentId,
        templateKey: templateKey,
        icon: icon,
        color: color,
      );
      await _db
          .into(_db.folders)
          .insert(
            FoldersCompanion.insert(
              id: folder.id,
              name: folder.name,
              createdAt: now,
              parentId: Value(parentId),
              templateKey: Value(templateKey),
              icon: Value(icon),
              color: Value(color),
              updatedAt: Value(now),
            ),
          );
      return folder;
    }),
  );

  @override
  Future<Result<void>> renameFolder(String id, String name) => guard(
    () => _db.transaction(() async {
      final row = await _folderRow(id);
      if (row == null) throw const AppFailure(FailureCode.notFound);
      final error = FolderNames.validate(
        name,
        await _siblingNames(row.parentId, except: id),
      );
      if (error != null) throw _invalid(error);
      await _write(id, FoldersCompanion(name: Value(FolderNames.clean(name))));
    }),
  );

  @override
  Future<Result<void>> setFolderStyle(
    String id, {
    required String? icon,
    required String? color,
  }) => guard(
    () => _write(id, FoldersCompanion(icon: Value(icon), color: Value(color))),
  );

  @override
  Future<Result<void>> setFolderLockMode(String id, FolderLockMode mode) =>
      guard(() => _write(id, FoldersCompanion(lockMode: Value(mode.name))));

  Future<void> _write(String id, FoldersCompanion changes) async {
    final n = await (_db.update(_db.folders)..where((t) => t.id.equals(id)))
        .write(changes.copyWith(updatedAt: Value(DateTime.now())));
    if (n == 0) throw const AppFailure(FailureCode.notFound);
  }

  @override
  Future<Result<void>> moveFolder(String id, String? newParentId) => guard(
    () => _db.transaction(() async {
      final tree = await _tree();
      final folder = tree[id];
      if (folder == null) throw const AppFailure(FailureCode.notFound);
      if (folder.parentId == newParentId) return;
      if (newParentId != null) {
        if (!tree.contains(newParentId)) {
          throw const AppFailure(FailureCode.notFound);
        }
        if (tree.isWithin(newParentId, id)) {
          throw _invalid(
            "A folder can't be moved into itself or one of its subfolders.",
          );
        }
      }
      final clash = FolderNames.validate(
        folder.name,
        await _siblingNames(newParentId, except: id),
      );
      if (clash != null) {
        throw _invalid(
          'A folder named "${folder.name}" already exists there. Rename one '
          'of them first.',
        );
      }
      await _write(id, FoldersCompanion(parentId: Value(newParentId)));
    }),
  );

  @override
  Future<Result<List<Document>>> deleteFolder(
    String id,
    FolderDeleteMode mode,
  ) => guard(
    () => _db.transaction(() async {
      final tree = await _tree();
      final folder = tree[id];
      if (folder == null) throw const AppFailure(FailureCode.notFound);
      switch (mode) {
        case FolderDeleteMode.deleteContents:
          final subtree = tree.subtreeIds(id);
          final docs = await (_db.select(
            _db.documents,
          )..where((t) => t.folderId.isIn(subtree))).get();
          await (_db.delete(
            _db.documents,
          )..where((t) => t.folderId.isIn(subtree))).go();
          // One statement: SQLite checks the parent_id references at its
          // end, when parents and children are gone together.
          await (_db.delete(
            _db.folders,
          )..where((t) => t.id.isIn(subtree))).go();
          return docs.map(_toDomain).toList();
        case FolderDeleteMode.moveContentsToParent:
          final parent = folder.parentId;
          final now = DateTime.now();
          await (_db.update(
            _db.documents,
          )..where((t) => t.folderId.equals(id))).write(
            DocumentsCompanion(folderId: Value(parent), updatedAt: Value(now)),
          );
          final taken = {
            for (final n in await _siblingNames(parent, except: id))
              n.toLowerCase(),
          };
          for (final child in tree.children(id)) {
            var name = child.name;
            for (var n = 2; taken.contains(name.toLowerCase()); n++) {
              name = '${child.name} ($n)';
            }
            taken.add(name.toLowerCase());
            await _write(
              child.id,
              FoldersCompanion(parentId: Value(parent), name: Value(name)),
            );
          }
          await (_db.delete(_db.folders)..where((t) => t.id.equals(id))).go();
          return const <Document>[];
      }
    }),
  );

  @override
  Stream<FolderContents> watchContents(
    String? folderId, {
    DocumentSort sort = DocumentSort.newest,
    DocumentFilter filter = DocumentFilter.all,
  }) => _live(() async {
    final tree = await _tree();
    if (folderId != null && !tree.contains(folderId)) {
      return FolderContents.empty;
    }
    final q = _db.select(_db.documents);
    if (folderId != null) {
      q.where((t) => t.folderId.equals(folderId));
    } else {
      final ids = [for (final f in tree.all) f.id];
      q.where((t) => t.folderId.isNull() | t.folderId.isNotIn(ids));
    }
    _applyFilter(q, filter);
    _applySort(q, sort);
    return FolderContents(
      folders: tree.children(folderId),
      documents: (await q.get()).map(_toDomain).toList(),
    );
  });

  @override
  Stream<Map<String?, int>> watchDirectCounts() => _live(() async {
    final count = _db.documents.id.count();
    final rows =
        await (_db.selectOnly(_db.documents)
              ..addColumns([_db.documents.folderId, count])
              ..groupBy([_db.documents.folderId]))
            .get();
    final known = {for (final f in await allFolders()) f.id};
    final out = <String?, int>{};
    for (final r in rows) {
      final raw = r.read(_db.documents.folderId);
      final key = known.contains(raw) ? raw : null;
      out[key] = (out[key] ?? 0) + (r.read(count) ?? 0);
    }
    return out;
  });

  @override
  Future<List<Folder>> breadcrumb(String folderId) async =>
      (await _tree()).pathTo(folderId);

  @override
  Stream<List<Document>> watchSearch(FolderSearch query) => _live(() async {
    final tree = await _tree();
    final hidden = tree.hiddenContentIds(query.unlockedFolderIds);
    final q = _db.select(_db.documents);
    _applySearch(q, query.text);
    _applyFilter(q, query.filter);
    final within = query.withinFolderId;
    if (within != null) {
      final scope = tree.subtreeIds(within).difference(hidden);
      if (scope.isEmpty) return const <Document>[];
      q.where((t) => t.folderId.isIn(scope));
    } else if (hidden.isNotEmpty) {
      q.where((t) => t.folderId.isNull() | t.folderId.isNotIn(hidden));
    }
    _applySort(q, query.sort);
    return (await q.get()).map(_toDomain).toList();
  });

  // ── Mapping ───────────────────────────────────────────────────────────────

  static Folder _folder(FolderRow r) => Folder(
    id: r.id,
    name: r.name,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    parentId: r.parentId,
    icon: r.icon,
    color: r.color,
    templateKey: r.templateKey,
    sortOrder: r.sortOrder,
    lockMode:
        FolderLockMode.values.asNameMap()[r.lockMode] ?? FolderLockMode.none,
  );

  static Document _toDomain(DocumentRow r) => Document(
    id: r.id,
    name: r.name,
    format:
        DocumentFormat.values.asNameMap()[r.format] ?? DocumentFormat.unknown,
    relativePath: r.relativePath,
    sizeBytes: r.sizeBytes,
    pageCount: r.pageCount,
    folderId: r.folderId,
    favorite: r.favorite,
    thumbnailPath: r.thumbnailPath,
    category: DocumentCategory.values.asNameMap()[r.category],
    expiresAt: r.expiresAt,
    slot: r.slot,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  static DocumentRow _toRow(Document d) => DocumentRow(
    id: d.id,
    name: d.name,
    format: d.format.name,
    relativePath: d.relativePath,
    sizeBytes: d.sizeBytes,
    pageCount: d.pageCount,
    folderId: d.folderId,
    favorite: d.favorite,
    thumbnailPath: d.thumbnailPath,
    category: d.category?.name,
    expiresAt: d.expiresAt,
    slot: d.slot,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  );
}
