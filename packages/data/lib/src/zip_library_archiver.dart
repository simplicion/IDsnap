import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/drift_document_repository.dart';
import 'package:docscan_data/src/local_file_store.dart';
import 'package:docscan_data/src/vault/shred.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// Full backup of the vault (roadmap B4, "Data Independence"; audit H-04,
/// H-05).
///
/// Layout (manifest version 3): the vault's folder tree as ZIP directories
/// (`IDs & Proofs/Passport/scan.pdf`), top-level files at the ZIP root,
/// `manifest.json` describing every folder (icons, colours, lock mode) and
/// document (names, categories, expiry dates, thumbnail), and app data under
/// `.idsnap/`: `secure-notes.json`, `thumbs/<n>.jpg` and one
/// `<section>.json` per [BackupSection] (authenticator accounts with their
/// secrets and recovery codes, saved signatures, QR history, settings).
///
/// With a password every file entry, the manifest included, is AES-256
/// encrypted (WinZip AE-2: 7-Zip, WinZip, Keka and The Unarchiver open it).
/// File and folder *names* stay readable in any ZIP; contents don't.
///
/// Everything streams: one document at a time is decrypted from the vault
/// into the app's work directory, streamed into the archive on a background
/// isolate and shredded; import extracts one entry at a time and encrypts
/// it into the vault. Memory stays at a few chunks whatever the vault size.
///
/// Not included, by design: folder and note PIN hashes (they never leave
/// the keystore; locked folders come back locked with the phone's screen
/// lock) and the IDSnap Pro licence (restored from the store).
///
/// Older backups still import: version 2 (folders + notes at the root) and
/// version 1 (category directories become folders, `Other/` = top level).
class ZipLibraryArchiver implements LibraryArchiver {
  ZipLibraryArchiver({
    required DriftDocumentRepository repository,
    required LocalFileStore files,
    ArchiveCodec? codec,
    NotesRepository? notes,
    RedactedLogger? logger,
    DateTime Function()? clock,
  }) : _repo = repository,
       _files = files,
       _codec = codec,
       _notes = notes,
       _log = logger ?? RedactedLogger('archive'),
       _clock = clock ?? DateTime.now;

  static const manifestName = 'manifest.json';

  /// Version-2 location of the notes; version 3 uses [notesPath].
  static const notesName = 'secure-notes.json';
  static const dataDir = '.idsnap/';
  static const notesPath = '${dataDir}secure-notes.json';
  static const manifestVersion = 3;

  /// Version-1 directory for uncategorized files (imported to the top level).
  static const uncategorizedFolder = 'Other';

  /// What a backup never contains (shown in the export dialog, written to
  /// the manifest).
  static const notIncluded = <String>[
    _pinsNotIncluded,
    'Your IDSnap Pro purchase: restore it from the store',
  ];

  static const _pinsNotIncluded =
      'Folder and note PINs: locked folders come back locked with the phone '
      'screen lock; set PINs again on the new phone';

  final DriftDocumentRepository _repo;
  final LocalFileStore _files;
  final ArchiveCodec? _codec;
  final NotesRepository? _notes;
  final RedactedLogger _log;
  final DateTime Function() _clock;

  static String sectionPath(String key) => '$dataDir$key.json';

  static bool _reserved(String name) =>
      name == manifestName || name == notesName || name.startsWith(dataDir);

  ArchiveCodec get _requireCodec =>
      _codec ??
      (throw const AppFailure(
        FailureCode.unknown,
        message: 'Backups are not available in this build.',
      ));

  // ── Export ────────────────────────────────────────────────────────────

  @override
  Future<Result<BackupResult>> exportBackup({
    String? password,
    List<BackupSection> sections = const [],
    bool includeDocuments = true,
    String? fileName,
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  }) async {
    ArchiveWriter? writer;
    String? outDir;
    String? plainCopy;
    void Function()? unregister;
    try {
      final codec = _requireCodec;
      cancel?.throwIfCancelled();
      onProgress?.call(const BackupProgress(BackupStage.preparing, 0));
      final now = _clock();
      final name = safeFileName(fileName ?? defaultFileName(now));
      outDir = await _files.newExportDirectory();
      final outPath = p.join(outDir, name);
      final w = writer = await codec.createWriter(outPath, password: password);
      unregister = cancel?.onCancel(() => unawaited(w.abort()));

      final docs = includeDocuments ? await _repo.all() : const <Document>[];
      final tree = FolderTree(
        includeDocuments ? await _repo.allFolders() : const [],
      );
      final used = <String>{manifestName, notesName, dataDir};
      final dirs = _directories(tree, used);
      final folderEntries = <Map<String, Object?>>[];
      for (final f in tree.all) {
        final dir = dirs[f.id];
        if (dir == null) continue; // Unreachable (cycle); never happens.
        await w.addDirectory('$dir/');
        folderEntries.add({
          'id': f.id,
          'name': f.name,
          'parentId': f.parentId,
          'path': dir,
          'icon': f.icon,
          'color': f.color,
          'templateKey': f.templateKey,
          'sortOrder': f.sortOrder,
          'locked': f.isLocked,
          'lockMode': f.lockMode.name,
          'createdAt': f.createdAt.toIso8601String(),
        });
      }

      final present = <Document>[];
      for (final d in docs) {
        if (await _files.exists(d.relativePath)) present.add(d);
      }
      final totalBytes =
          present.fold<int>(0, (a, d) => a + d.sizeBytes) + present.length + 1;
      var doneBytes = 0;
      void report(int extra, int index) => onProgress?.call(
        BackupProgress(
          BackupStage.documents,
          0.02 + 0.93 * ((doneBytes + extra) / totalBytes).clamp(0, 1),
          item: '${index + 1} of ${present.length}',
        ),
      );

      final entries = <Map<String, Object?>>[];
      for (final (i, d) in present.indexed) {
        cancel?.throwIfCancelled();
        final dir = dirs[d.folderId];
        final path = uniquePath(
          dir ?? '',
          safeFileName(d.name),
          d.format.extension,
          used,
        );
        // Decrypted into the work directory, streamed, shredded (ADR-0010).
        final plain = await _files.plainPathForRead(d.relativePath);
        if (plain.isCopy) plainCopy = plain.path;
        try {
          await w.addFile(plain.path, path, onBytes: (n) => report(n, i));
        } finally {
          if (plain.isCopy) {
            await shredFile(plain.path);
            plainCopy = null;
          }
        }
        String? thumbEntry;
        final thumb = d.thumbnailPath;
        if (thumb != null && await _files.exists(thumb)) {
          try {
            final bytes = await _files.read(_files.absolute(thumb));
            thumbEntry = '${dataDir}thumbs/$i.jpg';
            await w.addBytes(bytes, thumbEntry);
          } on VaultIntegrityException {
            thumbEntry = null; // A thumbnail is regenerated anyway.
          }
        }
        entries.add({
          'path': path,
          'name': d.name,
          'format': d.format.name,
          'folderId': dir == null ? null : d.folderId,
          'category': d.category?.name,
          'expiresAt': d.expiresAt?.toIso8601String(),
          'slot': d.slot,
          'favorite': d.favorite,
          'pageCount': d.pageCount,
          'createdAt': d.createdAt.toIso8601String(),
          'thumb': thumbEntry,
        });
        doneBytes += d.sizeBytes + 1;
        report(0, i);
      }

      cancel?.throwIfCancelled();
      onProgress?.call(const BackupProgress(BackupStage.appData, 0.96));
      final notes = includeDocuments
          ? await _notes?.all() ?? const <Note>[]
          : const <Note>[];
      if (notes.isNotEmpty) {
        await w.addBytes(
          _json({
            'version': 1,
            'notes': [for (final n in notes) noteToJson(n)],
          }),
          notesPath,
        );
      }
      final sectionInfo = <String, Object?>{};
      final sectionCounts = <String, int>{};
      for (final s in sections) {
        cancel?.throwIfCancelled();
        final data = await s.export();
        if (data == null) continue;
        final path = sectionPath(s.key);
        await w.addBytes(
          _json({'key': s.key, 'version': data.version, 'data': data.data}),
          path,
        );
        sectionInfo[s.key] = {
          'path': path,
          'label': s.label,
          'version': data.version,
          'count': data.count,
        };
        sectionCounts[s.key] = data.count;
      }

      onProgress?.call(const BackupProgress(BackupStage.finishing, 0.98));
      await w.addBytes(
        _json({
          'app': 'IDSnap',
          'version': manifestVersion,
          'exportedAt': now.toIso8601String(),
          'protected': password != null,
          'folders': folderEntries,
          'documents': entries,
          'notes': {'path': notesPath, 'count': notes.length},
          'sections': sectionInfo,
          'notIncluded': notIncluded,
        }),
        manifestName,
      );
      cancel?.throwIfCancelled();
      final size = await w.close();
      unregister?.call();
      onProgress?.call(const BackupProgress(BackupStage.finishing, 1));
      _log.info('exported', {
        'documents': entries.length,
        'folders': folderEntries.length,
        'notes': notes.length,
        'sections': sectionCounts.length,
        'protected': password != null,
      });
      return Ok(
        BackupResult(
          path: outPath,
          fileName: name,
          sizeBytes: size,
          protected: password != null,
          documents: entries.length,
          folders: folderEntries.length,
          notes: notes.length,
          sections: sectionCounts,
        ),
      );
    } on Object catch (e, st) {
      unregister?.call();
      await writer?.abort();
      final copy = plainCopy;
      if (copy != null) await shredFile(copy);
      if (outDir != null) await shredDirectory(outDir);
      final failure = backupFailure(e, st, exporting: true);
      _log.warn('export_failed', {'code': failure.code});
      return Err(failure);
    }
  }

  /// `IDSnap backup 2026-10-06.zip`.
  static String defaultFileName(DateTime now) =>
      'IDSnap backup ${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}.zip';

  static Uint8List _json(Object value) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
  );

  /// A unique, file-system-safe ZIP directory per folder, parents first.
  static Map<String, String> _directories(FolderTree tree, Set<String> used) {
    final out = <String, String>{};
    void visit(String? parentId, String prefix) {
      for (final f in tree.children(parentId)) {
        if (out.containsKey(f.id)) continue;
        final base = '$prefix${safeFileName(f.name)}';
        var dir = base;
        for (var n = 2; !used.add('${dir.toLowerCase()}/'); n++) {
          dir = '$base ($n)';
        }
        out[f.id] = dir;
        visit(f.id, '$dir/');
      }
    }

    visit(null, '');
    return out;
  }

  // ── Import ────────────────────────────────────────────────────────────

  @override
  Future<Result<ImportSummary>> importBackup(
    String zipPath, {
    String? password,
    List<BackupSection> sections = const [],
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  }) async {
    ArchiveReader? reader;
    String? work;
    var documents = 0;
    var notesAdded = 0;
    try {
      final codec = _requireCodec;
      cancel?.throwIfCancelled();
      onProgress?.call(const BackupProgress(BackupStage.preparing, 0));
      final r = reader = await codec.openReader(zipPath);

      // Everything below the next block changes the vault: first make sure
      // the password is right and the version is readable.
      var manifest = const <String, dynamic>{};
      final manifestEntry = r.entry(manifestName);
      if (manifestEntry != null) {
        if (manifestEntry.encrypted && password == null) {
          throw const ArchiveException(ArchiveErrorKind.passwordRequired);
        }
        final raw = await r.readBytes(manifestName, password: password);
        final Object? json;
        try {
          json = jsonDecode(utf8.decode(raw));
        } on FormatException {
          throw const ArchiveException(
            ArchiveErrorKind.corrupt,
            'Unreadable manifest',
          );
        }
        if (json is! Map<String, dynamic>) {
          throw const ArchiveException(
            ArchiveErrorKind.corrupt,
            'Unreadable manifest',
          );
        }
        manifest = json;
      } else if (r.hasEncryptedEntries) {
        if (password == null) {
          throw const ArchiveException(ArchiveErrorKind.passwordRequired);
        }
        // Check the password on the smallest encrypted entry.
        final probe = r.entries
            .where((e) => e.encrypted)
            .reduce((a, b) => a.size <= b.size ? a : b);
        if (probe.size <= 32 * 1024 * 1024) {
          await r.readBytes(probe.name, password: password);
        }
      }
      final version = (manifest['version'] as int?) ?? 1;
      if (version > manifestVersion) {
        throw const AppFailure(
          FailureCode.unsupportedFormat,
          message:
              'This backup was made by a newer version of IDSnap. Update '
              'IDSnap from the store, then import it again.',
          action: FailureAction.none,
        );
      }

      // 1. App data first (small, and the authenticator matters most).
      onProgress?.call(const BackupProgress(BackupStage.appData, 0.01));
      final sectionCounts = <String, int>{};
      final failedSections = <String, AppFailure>{};
      final info = manifest['sections'];
      for (final s in sections) {
        cancel?.throwIfCancelled();
        final meta = info is Map ? info[s.key] : null;
        final path = meta is Map && meta['path'] is String
            ? meta['path'] as String
            : sectionPath(s.key);
        if (r.entry(path) == null) continue;
        try {
          final json = jsonDecode(
            utf8.decode(await r.readBytes(path, password: password)),
          );
          if (json is! Map) continue;
          final v = json['version'];
          sectionCounts[s.key] = await s.restore(
            json['data'],
            version: v is int ? v : 1,
          );
        } on ArchiveException catch (e) {
          if (e.kind == ArchiveErrorKind.cancelled) rethrow;
          failedSections[s.label] = backupFailure(e, null, exporting: false);
        } on Object catch (e, st) {
          failedSections[s.label] = backupFailure(e, st, exporting: false);
        }
      }
      notesAdded = await _importNotes(r, password);

      // 2. Folders (reusing same-named ones), locks re-applied.
      final folders = _FolderImporter(_repo);
      final idMap = await folders.restore(
        version >= 2 ? manifest['folders'] : null,
      );

      // 3. Documents, one entry at a time.
      final docMeta = <String, Map<String, dynamic>>{
        for (final e in (manifest['documents'] as List<dynamic>? ?? const []))
          if (e is Map<String, dynamic> && e['path'] is String)
            e['path'] as String: e,
      };
      final existing = {
        for (final d in await _repo.all()) '${d.name}|${d.sizeBytes}',
      };
      final files = [
        for (final e in r.entries)
          if (!e.isDirectory && !_reserved(e.name)) e,
      ];
      final totalBytes =
          files.fold<int>(0, (a, e) => a + e.size) + files.length + 1;
      var doneBytes = 0;
      var skipped = 0;
      void report(int extra, int index) => onProgress?.call(
        BackupProgress(
          BackupStage.documents,
          0.05 + 0.93 * ((doneBytes + extra) / totalBytes).clamp(0, 1),
          item: '${index + 1} of ${files.length}',
        ),
      );

      for (final (i, entry) in files.indexed) {
        cancel?.throwIfCancelled();
        report(0, i);
        doneBytes += entry.size + 1;
        final meta = docMeta[entry.name] ?? const <String, dynamic>{};
        final name =
            (meta['name'] as String?) ??
            p.posix.basenameWithoutExtension(entry.name);
        if (entry.size == 0 || existing.contains('$name|${entry.size}')) {
          skipped++;
          continue;
        }
        final target = work = await _files.newWorkPath('part');
        await r.extract(
          entry.name,
          target,
          password: password,
          cancel: cancel,
          onBytes: (n) => report(n, i),
        );
        final format = DocumentFormat.sniff(
          await _head(target),
          nameHint: entry.name,
        );
        if (format == DocumentFormat.unknown || format == DocumentFormat.zip) {
          await shredFile(target); // Never import what we can't identify.
          work = null;
          skipped++;
          continue;
        }

        final dirs = p.posix.split(p.posix.dirname(entry.name))
          ..removeWhere((s) => s == '.' || s.isEmpty);
        final v1Category = version < 2 && dirs.isNotEmpty
            ? categoryForFolder(dirs.first)
            : null;
        final String? folderId;
        final mapped = idMap[meta['folderId']];
        if (mapped != null) {
          folderId = mapped;
        } else if (dirs.isEmpty ||
            (version < 2 &&
                dirs.length == 1 &&
                dirs.first == uncategorizedFolder)) {
          folderId = null;
        } else {
          folderId = await folders.ensurePath(
            dirs,
            topTemplateKey: v1Category?.name,
          );
        }

        final relative = await _files.commit(target, format.extension);
        work = null;
        final id = newId();
        String? thumbPath;
        final thumb = meta['thumb'];
        if (thumb is String && r.entry(thumb) != null) {
          try {
            final bytes = await r.readBytes(
              thumb,
              password: password,
              maxBytes: 8 * 1024 * 1024,
            );
            thumbPath = await _files.writeThumbnail(id, bytes);
          } on ArchiveException catch (e) {
            if (e.kind == ArchiveErrorKind.cancelled) rethrow;
            thumbPath = null; // Optional.
          }
        }
        final now = _clock();
        final added = await _repo.add(
          Document(
            id: id,
            name: name,
            format: format,
            relativePath: relative,
            sizeBytes: entry.size,
            pageCount: meta['pageCount'] as int?,
            favorite: (meta['favorite'] as bool?) ?? false,
            folderId: folderId,
            category:
                DocumentCategory.values.asNameMap()[meta['category']] ??
                v1Category,
            expiresAt: DateTime.tryParse('${meta['expiresAt']}'),
            slot: meta['slot'] as String?,
            thumbnailPath: thumbPath,
            createdAt: DateTime.tryParse('${meta['createdAt']}') ?? now,
            updatedAt: now,
          ),
        );
        if (added case Err(:final failure)) {
          await _files.delete(relative);
          if (thumbPath != null) await _files.delete(thumbPath);
          throw failure;
        }
        existing.add('$name|${entry.size}');
        documents++;
      }
      onProgress?.call(const BackupProgress(BackupStage.finishing, 1));
      // The picker's copy of the backup (possibly unencrypted) isn't needed
      // any more; a file outside the app's scratch space is left alone.
      await r.close();
      await _files.discardImportedSource(zipPath);
      final summary = ImportSummary(
        documents: documents,
        notes: notesAdded,
        folders: folders.created,
        skipped: skipped,
        sections: sectionCounts,
        failedSections: failedSections,
        pinLockedFolders: folders.pinLocked,
        manifestVersion: version,
      );
      _log.info('imported', {
        'documents': documents,
        'notes': notesAdded,
        'sections': sectionCounts.length,
        'failedSections': failedSections.length,
        'version': version,
      });
      return Ok(summary);
    } on Object catch (e, st) {
      final w = work;
      if (w != null) await shredFile(w);
      var failure = backupFailure(e, st, exporting: false);
      if (failure.code == FailureCode.processingCancelled) {
        failure = AppFailure(
          FailureCode.processingCancelled,
          message: documents + notesAdded == 0
              ? 'Import stopped. Nothing was imported.'
              : 'Import stopped after ${documents + notesAdded} items. '
                    'Import the same backup again to finish — nothing is '
                    'added twice.',
          action: FailureAction.none,
        );
      }
      _log.warn('import_failed', {'code': failure.code});
      return Err(failure);
    } finally {
      try {
        await reader?.close();
      } on Object {
        // Already closed.
      }
    }
  }

  static Future<Uint8List> _head(String path) async {
    final raf = await File(path).open();
    try {
      return await raf.read(64);
    } finally {
      await raf.close();
    }
  }

  /// Restores the notes (v3 `.idsnap/`, v2 root); returns the notes added.
  Future<int> _importNotes(ArchiveReader r, String? password) async {
    final repo = _notes;
    final path = r.entry(notesPath) != null
        ? notesPath
        : (r.entry(notesName) != null ? notesName : null);
    if (repo == null || path == null) return 0;
    final Object? json;
    try {
      json = jsonDecode(
        utf8.decode(await r.readBytes(path, password: password)),
      );
    } on FormatException {
      return 0;
    }
    if (json is! Map<String, dynamic> || json['notes'] is! List) return 0;
    var added = 0;
    for (final e in json['notes'] as List) {
      final note = e is Map<String, dynamic> ? noteFromJson(e) : null;
      if (note == null) continue;
      final res = await repo.restore(note);
      if (res case Err(:final failure)) throw failure;
      if (res.valueOrNull ?? false) added++;
    }
    return added;
  }

  static Map<String, Object?> noteToJson(Note n) => {
    'id': n.id,
    'title': n.title,
    'body': n.body,
    'tag': n.tag,
    'template': n.template.name,
    'pinned': n.pinned,
    'locked': n.isLocked,
    'createdAt': n.createdAt.toIso8601String(),
    'updatedAt': n.updatedAt.toIso8601String(),
  };

  static Note? noteFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final created = DateTime.tryParse('${j['createdAt']}');
    if (id is! String || created == null) return null;
    return Note(
      id: id,
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      tag: j['tag'] as String?,
      template: NoteTemplate.byName(j['template'] as String?),
      pinned: (j['pinned'] as bool?) ?? false,
      // A note PIN never leaves the keystore: locked notes come back
      // locked with the device lock.
      lockMode: (j['locked'] as bool?) ?? false
          ? FolderLockMode.device
          : FolderLockMode.none,
      createdAt: created,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? created,
    );
  }

  /// Folder name for a category, safe on every file system.
  static String folderName(DocumentCategory c) => safeFileName(c.label);

  static DocumentCategory? categoryForFolder(String folder) {
    for (final c in DocumentCategory.values) {
      if (folderName(c) == folder) return c;
    }
    return null;
  }

  /// `folder/name.ext` (`name.ext` when [folder] is empty), suffixed ` (2)`,
  /// ` (3)`… when already used.
  static String uniquePath(
    String folder,
    String name,
    String ext,
    Set<String> used,
  ) {
    final prefix = folder.isEmpty ? '' : '$folder/';
    var candidate = '$prefix$name.$ext';
    var n = 2;
    while (!used.add(candidate.toLowerCase())) {
      candidate = '$prefix$name ($n).$ext';
      n++;
    }
    return candidate;
  }
}

/// Maps anything a backup job throws to a specific, actionable failure
/// (audit H-05: not everything is "Not enough storage").
AppFailure backupFailure(Object e, StackTrace? st, {required bool exporting}) {
  if (e is AppFailure) return e;
  if (e is ArchiveException) {
    return switch (e.kind) {
      ArchiveErrorKind.passwordRequired => AppFailure(
        FailureCode.passwordProtected,
        cause: e,
        message:
            'This backup is protected. Enter the password you chose '
            'when you exported it.',
        action: FailureAction.retry,
      ),
      ArchiveErrorKind.wrongPassword => AppFailure(
        FailureCode.wrongPassword,
        cause: e,
        message:
            "That password doesn't open this backup. Passwords are "
            'case-sensitive.',
      ),
      ArchiveErrorKind.corrupt => AppFailure(
        FailureCode.corruptFile,
        cause: e,
        message: exporting
            ? "The backup couldn't be written correctly. Try again."
            : "This backup is damaged or incomplete, or it isn't an IDSnap "
                  'backup. Try another copy of the file.',
      ),
      ArchiveErrorKind.unsupported => AppFailure(
        exporting ? FailureCode.wrongPassword : FailureCode.unsupportedFormat,
        cause: e,
        message: exporting
            ? (e.message ??
                  'Use only English letters, digits and standard symbols.')
            : "This ZIP uses a format IDSnap can't read (ZIP64 or legacy "
                  'encryption). Unzip it on a computer and zip it again.',
      ),
      ArchiveErrorKind.tooLarge => AppFailure(
        FailureCode.memoryLimitExceeded,
        cause: e,
        message:
            'A backup can hold up to 4 GB and 65,535 files. Move some '
            'large files out of IDSnap first.',
        action: FailureAction.none,
      ),
      ArchiveErrorKind.noSpace => AppFailure(
        FailureCode.insufficientStorage,
        cause: e,
        message: exporting
            ? 'The backup needs about as much free space as your vault. '
                  'Free up space and try again.'
            : 'Importing needs about as much free space as the backup. '
                  'Free up space and try again.',
      ),
      ArchiveErrorKind.permission => AppFailure(
        FailureCode.permissionDenied,
        cause: e,
        message:
            "IDSnap couldn't read or write the file. Choose it again "
            'or pick another place.',
        action: FailureAction.retry,
      ),
      ArchiveErrorKind.notFound => AppFailure(FailureCode.notFound, cause: e),
      ArchiveErrorKind.cancelled => AppFailure(
        FailureCode.processingCancelled,
        cause: e,
        message: exporting ? 'Export cancelled. Nothing was saved.' : null,
      ),
      ArchiveErrorKind.io => AppFailure(
        FailureCode.unknown,
        cause: e,
        stackTrace: st,
      ),
    };
  }
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    final text = '${e.osError?.message} ${e.message}'.toLowerCase();
    final kind =
        text.contains('no space') ||
            code == 28 ||
            (Platform.isWindows && (code == 112 || code == 39))
        ? ArchiveErrorKind.noSpace
        : (code == 13 || code == 1 || (Platform.isWindows && code == 5))
        ? ArchiveErrorKind.permission
        : code == 2
        ? ArchiveErrorKind.notFound
        : ArchiveErrorKind.io;
    return backupFailure(
      ArchiveException(kind, e.osError?.message),
      st,
      exporting: exporting,
    );
  }
  if (e is VaultIntegrityException) {
    return AppFailure(
      FailureCode.corruptFile,
      cause: e,
      message: exporting
          ? 'A file in your vault failed its integrity check, so the '
                'export stopped. Open the vault to find the damaged file.'
          : null,
    );
  }
  return AppFailure(FailureCode.unknown, cause: e, stackTrace: st);
}

/// Recreates folders during import, reusing a same-named sibling that
/// already exists so importing the same backup twice doesn't duplicate the
/// tree. New folders get their lock back: a PIN can't travel, so PIN-locked
/// folders are locked with the phone's screen lock instead.
class _FolderImporter {
  _FolderImporter(this._repo);

  final DriftDocumentRepository _repo;
  int created = 0;
  int pinLocked = 0;

  Future<(String, bool)> _child(
    String? parentId,
    String rawName, {
    String? templateKey,
    String? icon,
    String? color,
  }) async {
    var name = FolderNames.clean(rawName);
    if (name.isEmpty) name = 'Folder';
    if (name.length > FolderNames.maxLength) {
      name = name.substring(0, FolderNames.maxLength).trim();
    }
    final lower = name.toLowerCase();
    final siblings = FolderTree(await _repo.allFolders()).children(parentId);
    for (final s in siblings) {
      if (s.name.toLowerCase() == lower) return (s.id, false);
    }
    final template = FolderTemplate.byKey(templateKey);
    final result = await _repo.createFolder(
      name: name,
      parentId: parentId,
      templateKey: templateKey,
      icon: icon ?? template?.icon,
      color: color ?? template?.color,
    );
    final folder = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw failure,
    };
    created++;
    return (folder.id, true);
  }

  /// Restores manifest v2+ folders; returns old id → new id.
  Future<Map<String, String>> restore(Object? folders) async {
    final out = <String, String>{};
    if (folders is! List) return out;
    final pending = [
      for (final f in folders)
        if (f is Map<String, dynamic> &&
            f['id'] is String &&
            f['name'] is String)
          f,
    ];
    // Parents first; entries whose parent isn't in the backup go to the top.
    final ids = {for (final f in pending) f['id'] as String};
    while (pending.isNotEmpty) {
      final ready = pending.where((f) {
        final parent = f['parentId'];
        return parent == null ||
            !ids.contains(parent) ||
            out.containsKey(parent);
      }).toList();
      if (ready.isEmpty) break; // A cycle: drop the rest.
      for (final f in ready) {
        pending.remove(f);
        final (id, isNew) = await _child(
          out[f['parentId']],
          f['name'] as String,
          templateKey: f['templateKey'] as String?,
          icon: f['icon'] as String?,
          color: f['color'] as String?,
        );
        out[f['id'] as String] = id;
        final mode = FolderLockMode.values.asNameMap()[f['lockMode']];
        final locked =
            (mode != null && mode != FolderLockMode.none) ||
            (mode == null && f['locked'] == true);
        if (isNew && locked) {
          final r = await _repo.setFolderLockMode(id, FolderLockMode.device);
          if (r case Err(:final failure)) throw failure;
          if (mode == FolderLockMode.pin) pinLocked++;
        }
      }
    }
    return out;
  }

  /// Ensures the chain of folders named [segments] exists; returns the last.
  Future<String?> ensurePath(
    List<String> segments, {
    String? topTemplateKey,
  }) async {
    String? parent;
    for (final (i, segment) in segments.indexed) {
      (parent, _) = await _child(
        parent,
        segment,
        templateKey: i == 0 ? topTemplateKey : null,
      );
    }
    return parent;
  }
}
