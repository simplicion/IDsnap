import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/database.dart';
import 'package:docscan_data/src/drift_document_repository.dart';
import 'package:docscan_data/src/json_stores.dart';
import 'package:docscan_data/src/local_file_store.dart';
import 'package:docscan_data/src/vault/shred.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// [VaultEraser] on the data layer (audit H-06). Enumerates documents with
/// [DriftDocumentRepository.all], which includes locked folders (callers
/// re-authenticate first). The vault key is kept: an empty vault with the
/// same key is indistinguishable from a fresh install, and the licence
/// lives in its own storage, which is never touched.
class DataVaultEraser implements VaultEraser {
  DataVaultEraser({
    required AppDatabase database,
    required DriftDocumentRepository documents,
    required LocalFileStore files,
    required JsonDraftStore drafts,
    required JsonSettingsStore settings,
    List<Erasable> targets = const [],
    RedactedLogger? logger,
  }) : _db = database,
       _repo = documents,
       _files = files,
       _drafts = drafts,
       _settings = settings,
       _targets = targets,
       _log = logger ?? RedactedLogger('erase');

  final AppDatabase _db;
  final DriftDocumentRepository _repo;
  final LocalFileStore _files;
  final JsonDraftStore _drafts;
  final JsonSettingsStore _settings;
  final List<Erasable> _targets;
  final RedactedLogger _log;

  /// Everything else "Erase everything" removes (authenticator secrets,
  /// signatures, QR history, PIN hashes…).
  List<Erasable> get targets => List.unmodifiable(_targets);

  @override
  Future<Result<int>> deleteAllDocuments({
    Future<void> Function(Document document)? onDeleted,
  }) => guard(() async {
    final docs = await _repo.all();
    for (final d in docs) {
      await _files.delete(d.relativePath);
      final thumb = d.thumbnailPath;
      if (thumb != null) await _files.delete(thumb);
      final removed = await _repo.remove(d.id);
      if (removed case Err(:final failure)) throw failure;
      await _notify(onDeleted, d);
    }
    await _files.clearVaultTemp();
    _log.info('deleted_all_documents', {'count': docs.length});
    return docs.length;
  });

  Future<void> _notify(
    Future<void> Function(Document)? onDeleted,
    Document d,
  ) async {
    if (onDeleted == null) return;
    try {
      await onDeleted(d);
    } on Object {
      // Reminders etc. are best effort; the document is gone either way.
    }
  }

  @override
  Future<Result<void>> eraseEverything({
    Future<void> Function(Document document)? onDeleted,
  }) => guard(() async {
    final failed = <String>[];
    for (final d in await _repo.all()) {
      await _notify(onDeleted, d);
    }
    for (final t in _targets) {
      try {
        await t.erase();
      } on Object catch (e) {
        failed.add(t.label);
        _log.warn('erase_failed', {'type': e.runtimeType.toString()});
      }
    }
    await _db.transaction(() async {
      await _db.delete(_db.documents).go();
      await _db.delete(_db.folders).go();
      await _db.delete(_db.notes).go();
      await _db.delete(_db.totpAccounts).go();
    });
    try {
      await _db.customStatement('VACUUM');
    } on Object {
      // Freed pages stay encrypted (SQLCipher); VACUUM only compacts.
    }
    try {
      await _drafts.clear();
    } on Object {
      // Removed with its directory below.
    }
    for (final dir in [
      ..._files.vaultDirectories,
      p.join(_files.root, 'drafts'),
    ]) {
      await shredDirectory(dir);
    }
    final settings = File(_settings.path);
    if (settings.existsSync()) await settings.delete();
    await _files.clearTemp();
    await _files.ensureLayout();
    _log.info('erased_everything', {'failed': failed.length});
    if (failed.isNotEmpty) {
      throw AppFailure(
        FailureCode.unknown,
        message:
            "Some data couldn't be erased: ${failed.join(', ')}. "
            'Try Erase everything again.',
      );
    }
  });
}
