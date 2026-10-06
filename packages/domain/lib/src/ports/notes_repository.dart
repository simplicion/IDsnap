import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/folder.dart';
import 'package:docscan_domain/src/entities/note.dart';

/// Secure notes (feature_notes). Locked notes never match a search and
/// never expose a body preview.
abstract interface class NotesRepository {
  /// Pinned first, then most recently updated. A non-empty [search] matches
  /// title, body and tag of **unlocked** notes only.
  Stream<List<Note>> watch({String search = ''});

  Future<Note?> byId(String id);

  /// Every note (export).
  Future<List<Note>> all();

  Future<Result<Note>> create({
    String title = '',
    String body = '',
    String? tag,
    NoteTemplate template = NoteTemplate.custom,
  });

  /// Saves title, body, tag and template; bumps `updatedAt`.
  Future<Result<void>> save(Note note);

  Future<Result<void>> setPinned(String id, {required bool pinned});
  Future<Result<void>> setLockMode(String id, FolderLockMode mode);
  Future<Result<void>> delete(String id);

  /// Inserts a note as is (import). Skips an identical existing note.
  Future<Result<bool>> restore(Note note);
}
