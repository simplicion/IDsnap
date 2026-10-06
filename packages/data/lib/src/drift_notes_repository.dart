import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/database.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart';

/// [NotesRepository] on Drift. The whole database is SQLCipher-encrypted,
/// so note bodies are encrypted at rest with everything else (ADR-0010).
class DriftNotesRepository implements NotesRepository {
  DriftNotesRepository(this._db);

  final AppDatabase _db;

  static const maxTitleLength = 200;

  @override
  Stream<List<Note>> watch({String search = ''}) {
    final q = _db.select(_db.notes);
    final text = search.trim();
    if (text.isNotEmpty) {
      final escaped = text
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final like = '%$escaped%';
      // Locked notes never match a search, not even by title.
      q.where(
        (t) =>
            t.lockMode.equals(FolderLockMode.none.name) &
            (t.title.like(like, escapeChar: r'\') |
                t.body.like(like, escapeChar: r'\') |
                t.tag.like(like, escapeChar: r'\')),
      );
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Note?> byId(String id) async {
    final row = await (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<List<Note>> all() async =>
      (await _db.select(_db.notes).get()).map(_toDomain).toList();

  @override
  Future<Result<Note>> create({
    String title = '',
    String body = '',
    String? tag,
    NoteTemplate template = NoteTemplate.custom,
  }) => guard(() async {
    final now = DateTime.now();
    final note = Note(
      id: newId(),
      title: _clip(title),
      body: body,
      tag: _cleanTag(tag),
      template: template,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.notes).insert(_toRow(note));
    return note;
  }, code: FailureCode.insufficientStorage);

  @override
  Future<Result<void>> save(Note note) => guard(() async {
    final n = await (_db.update(_db.notes)..where((t) => t.id.equals(note.id)))
        .write(
          NotesCompanion(
            title: Value(_clip(note.title)),
            body: Value(note.body),
            tag: Value(_cleanTag(note.tag)),
            template: Value(note.template.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (n == 0) throw const AppFailure(FailureCode.notFound);
  }, code: FailureCode.insufficientStorage);

  @override
  Future<Result<void>> setPinned(String id, {required bool pinned}) =>
      _write(id, NotesCompanion(pinned: Value(pinned)));

  @override
  Future<Result<void>> setLockMode(String id, FolderLockMode mode) =>
      _write(id, NotesCompanion(lockMode: Value(mode.name)));

  Future<Result<void>> _write(String id, NotesCompanion changes) =>
      guard(() async {
        final n = await (_db.update(
          _db.notes,
        )..where((t) => t.id.equals(id))).write(changes);
        if (n == 0) throw const AppFailure(FailureCode.notFound);
      });

  @override
  Future<Result<void>> delete(String id) => guard(() async {
    await (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
  });

  @override
  Future<Result<bool>> restore(Note note) => guard(() async {
    final same =
        await (_db.select(_db.notes)..where(
              (t) =>
                  t.title.equals(note.title) &
                  t.body.equals(note.body) &
                  t.createdAt.equals(note.createdAt),
            ))
            .get();
    if (same.isNotEmpty) return false;
    final exists = await byId(note.id) != null;
    final row = _toRow(
      Note(
        id: exists ? newId() : note.id,
        title: _clip(note.title),
        body: note.body,
        tag: _cleanTag(note.tag),
        template: note.template,
        pinned: note.pinned,
        lockMode: note.lockMode,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      ),
    );
    await _db.into(_db.notes).insert(row);
    return true;
  }, code: FailureCode.insufficientStorage);

  static String _clip(String s) {
    final t = s.trim();
    return t.length > maxTitleLength ? t.substring(0, maxTitleLength) : t;
  }

  static String? _cleanTag(String? tag) {
    final t = tag?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static Note _toDomain(NoteRow r) => Note(
    id: r.id,
    title: r.title,
    body: r.body,
    tag: r.tag,
    template: NoteTemplate.byName(r.template),
    pinned: r.pinned,
    lockMode:
        FolderLockMode.values.asNameMap()[r.lockMode] ?? FolderLockMode.device,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  static NoteRow _toRow(Note n) => NoteRow(
    id: n.id,
    title: n.title,
    body: n.body,
    tag: n.tag,
    template: n.template.name,
    pinned: n.pinned,
    lockMode: n.lockMode.name,
    createdAt: n.createdAt,
    updatedAt: n.updatedAt,
  );
}
