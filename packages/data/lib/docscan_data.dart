/// Data layer: Drift (SQLCipher) metadata, the encrypted app-private file
/// store, JSON stores for drafts and settings. Implements domain ports.
library;

import 'dart:async';
import 'dart:io';

import 'package:docscan_data/src/database.dart';
import 'package:docscan_data/src/drift_document_repository.dart';
import 'package:docscan_data/src/drift_notes_repository.dart';
import 'package:docscan_data/src/json_stores.dart';
import 'package:docscan_data/src/local_file_store.dart';
import 'package:docscan_data/src/vault/encrypted_database.dart';
import 'package:docscan_data/src/vault/file_migration.dart';
import 'package:docscan_data/src/vault/plaintext_scratch.dart';
import 'package:docscan_data/src/vault/vault_opener.dart';
import 'package:docscan_data/src/zip_library_archiver.dart';
import 'package:docscan_domain/docscan_domain.dart'
    show ArchiveCodec, FileCipher;
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'src/backup/data_sections.dart';
export 'src/backup/data_vault_eraser.dart';
export 'src/database.dart' show AppDatabase;
export 'src/drift_authenticator_repository.dart';
export 'src/drift_document_repository.dart';
export 'src/drift_notes_repository.dart';
export 'src/json_stores.dart';
export 'src/local_file_store.dart';
export 'src/vault/encrypted_database.dart' show EncryptedDatabase;
export 'src/vault/file_migration.dart' show VaultFileMigrator;
export 'src/vault/plaintext_scratch.dart';
export 'src/vault/shred.dart';
export 'src/vault/vault_opener.dart'
    show
        VaultSecurity,
        VaultStateFile,
        VaultUnavailableException,
        VaultUnavailableReason,
        eraseVault,
        hasEncryptedContent;
export 'src/zip_library_archiver.dart';

/// Everything the app needs from the data layer.
class DataLayer {
  DataLayer({
    required this.database,
    required this.documents,
    required this.notes,
    required this.drafts,
    required this.settings,
    required this.files,
    required this.archiver,
    this.fileCipher,
  });

  final AppDatabase database;
  final DriftDocumentRepository documents;
  final DriftNotesRepository notes;
  final JsonDraftStore drafts;
  final JsonSettingsStore settings;
  final LocalFileStore files;

  /// Full backup export/import (roadmap B4, audit H-04/H-05).
  final ZipLibraryArchiver archiver;

  /// The vault cipher (ADR-0010) for stores outside [files] (saved
  /// signatures, QR history); null when the layer isn't encrypted (tests).
  final FileCipher? fileCipher;

  /// True when files and the database are encrypted (ADR-0010).
  bool get encrypted => fileCipher != null;

  Future<void> close() => database.close();
}

/// Progress of the one-time encryption of an existing vault.
typedef VaultMigrationProgress = void Function(int done, int total);

/// Default vault root: `<app documents>/docscan`.
Future<String> defaultVaultRoot() async =>
    p.join((await getApplicationDocumentsDirectory()).path, 'docscan');

/// Default cache root for plaintext work files: `<app cache>/docscan`.
Future<String> defaultVaultCache() async =>
    p.join((await getTemporaryDirectory()).path, 'docscan');

/// Opens the data layer under `<app documents>/docscan` (or [rootOverride]),
/// with plaintext work files under `<app cache>/docscan` (or
/// [cacheOverride]; defaults to the root when [rootOverride] is set).
///
/// With [security] (the app always passes it) files and the database are
/// encrypted (ADR-0010): the master key is loaded or created, existing
/// plaintext files are migrated ([onMigration] reports progress when there
/// is work) and the database is opened with SQLCipher. Throws
/// [VaultUnavailableException] when encrypted data exists but can't be
/// unlocked on this phone. Pass [executor] (e.g. `NativeDatabase.memory()`)
/// in tests.
///
/// [archiveCodec] streams backups (the app passes `ZipArchiveCodec`).
/// [scratch] lists the picker/scanner plaintext locations to clean up
/// (audit H-07); it defaults to the phone's real ones when no override is
/// given and to none in tests.
Future<DataLayer> openDataLayer({
  String? rootOverride,
  String? cacheOverride,
  QueryExecutor? executor,
  VaultSecurity? security,
  VaultMigrationProgress? onMigration,
  ArchiveCodec? archiveCodec,
  PlaintextScratch? scratch,
}) async {
  final root = rootOverride ?? await defaultVaultRoot();
  final cache = cacheOverride ?? rootOverride ?? await defaultVaultCache();
  await Directory(root).create(recursive: true);
  final dbFile = File(p.join(root, 'library.sqlite'));

  final vault = security == null ? null : await openVault(root, security);
  final files = LocalFileStore(
    root,
    cacheRoot: cache,
    cipher: vault?.cipher,
    scratch:
        scratch ??
        (rootOverride == null
            ? await PlaintextScratch.platformDefault()
            : PlaintextScratch.none),
  );
  await files.ensureLayout();
  // Stale work files and plaintext copies from a previous session are never
  // needed: shred them. Picker/scanner leftovers go in the background.
  await files.clearVaultTemp();
  unawaited(files.sweepScratch().then((_) {}, onError: (Object _) {}));

  var db = executor;
  if (vault != null) {
    await VaultFileMigrator(
      cipher: vault.cipher,
      directories: files.vaultDirectories,
      scratchDirectory: files.scratchDirectory,
    ).run(onProgress: onMigration);
    if (db == null) {
      await EncryptedDatabase.migrate(dbFile.path, vault.databaseKey);
      db = EncryptedDatabase.open(dbFile, vault.databaseKey);
    }
  }
  final database = AppDatabase(db ?? NativeDatabase.createInBackground(dbFile));
  final documents = DriftDocumentRepository(database);
  final notes = DriftNotesRepository(database);
  return DataLayer(
    database: database,
    documents: documents,
    notes: notes,
    // A finished or discarded scan: sweep the scanner's plaintext output.
    drafts: JsonDraftStore(
      root,
      onCleared: () => files.sweepScratch(scannerOnly: true),
    ),
    settings: JsonSettingsStore(root),
    files: files,
    archiver: ZipLibraryArchiver(
      repository: documents,
      files: files,
      notes: notes,
      codec: archiveCodec,
    ),
    fileCipher: vault?.cipher,
  );
}
