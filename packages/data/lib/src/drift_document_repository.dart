import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/database.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart';

/// [DocumentRepository] on Drift/SQLite.
class DriftDocumentRepository implements DocumentRepository {
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

  @override
  Stream<List<Document>> watch(DocumentQuery query) {
    final q = _db.select(_db.documents);
    final search = query.search.trim();
    if (search.isNotEmpty) {
      final escaped = search
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      q.where((t) => t.name.like('%$escaped%', escapeChar: r'\'));
    }
    switch (query.filter) {
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
    final folder = query.folderId;
    if (folder != null) q.where((t) => t.folderId.equals(folder));
    q.orderBy([
      (t) => switch (query.sort) {
        DocumentSort.newest => OrderingTerm.desc(t.updatedAt),
        DocumentSort.oldest => OrderingTerm.asc(t.updatedAt),
        DocumentSort.nameAz => OrderingTerm.asc(t.name.collate(Collate.noCase)),
        DocumentSort.largest => OrderingTerm.desc(t.sizeBytes),
      },
    ]);
    final limit = query.limit;
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Document?> byId(String id) async {
    final row = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<Result<void>> add(Document document) => guard(
    () => _db.into(_db.documents).insert(_toRow(document)),
    code: FailureCode.insufficientStorage,
  );

  @override
  Future<Result<void>> update(Document document) => guard(() async {
    final ok = await _db.update(_db.documents).replace(_toRow(document));
    if (!ok) throw const AppFailure(FailureCode.notFound);
  });

  @override
  Future<Result<void>> remove(String id) => guard(() async {
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
  });

  @override
  Stream<List<Folder>> watchFolders() =>
      (_db.select(
            _db.folders,
          )..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                Folder(id: r.id, name: r.name, createdAt: r.createdAt),
            ],
          );

  @override
  Future<Result<Folder>> addFolder(String name) => guard(() async {
    final folder = Folder(
      id: newId(),
      name: name.trim().isEmpty ? 'New folder' : name.trim(),
      createdAt: DateTime.now(),
    );
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(
            id: folder.id,
            name: folder.name,
            createdAt: folder.createdAt,
          ),
        );
    return folder;
  });

  @override
  Future<Result<void>> renameFolder(String id, String name) => guard(() async {
    await (_db.update(_db.folders)..where((t) => t.id.equals(id))).write(
      FoldersCompanion(name: Value(name.trim())),
    );
  });

  @override
  Future<Result<void>> removeFolder(String id) => guard(
    () => _db.transaction(() async {
      await (_db.update(_db.documents)..where((t) => t.folderId.equals(id)))
          .write(const DocumentsCompanion(folderId: Value(null)));
      await (_db.delete(_db.folders)..where((t) => t.id.equals(id))).go();
    }),
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
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  );
}
