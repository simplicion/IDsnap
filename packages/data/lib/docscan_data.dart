/// Data layer: Drift (SQLite) metadata, app-private file store, JSON stores
/// for drafts and settings. Implements domain ports.
library;

import 'dart:io';

import 'package:docscan_data/src/database.dart';
import 'package:docscan_data/src/drift_document_repository.dart';
import 'package:docscan_data/src/json_stores.dart';
import 'package:docscan_data/src/local_file_store.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'src/database.dart' show AppDatabase;
export 'src/drift_document_repository.dart';
export 'src/json_stores.dart';
export 'src/local_file_store.dart';

/// Everything the app needs from the data layer.
class DataLayer {
  DataLayer({
    required this.database,
    required this.documents,
    required this.drafts,
    required this.settings,
    required this.files,
  });

  final AppDatabase database;
  final DriftDocumentRepository documents;
  final JsonDraftStore drafts;
  final JsonSettingsStore settings;
  final LocalFileStore files;

  Future<void> close() => database.close();
}

/// Opens the data layer under `<app documents>/docscan` (or [rootOverride]).
/// Pass [executor] (e.g. `NativeDatabase.memory()`) in tests.
Future<DataLayer> openDataLayer({
  String? rootOverride,
  QueryExecutor? executor,
}) async {
  final root =
      rootOverride ??
      p.join((await getApplicationDocumentsDirectory()).path, 'docscan');
  final files = LocalFileStore(root);
  await files.ensureLayout();
  // Stale work files from a previous session are never needed.
  await files.clearTemp();
  final db = AppDatabase(
    executor ??
        NativeDatabase.createInBackground(File(p.join(root, 'library.sqlite'))),
  );
  return DataLayer(
    database: db,
    documents: DriftDocumentRepository(db),
    drafts: JsonDraftStore(root),
    settings: JsonSettingsStore(root),
    files: files,
  );
}
