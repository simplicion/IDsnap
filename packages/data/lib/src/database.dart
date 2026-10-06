import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('DocumentRow')
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get format => text()();
  TextColumn get relativePath => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get folderId => text().nullable()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // v2: vault (roadmap B1).
  TextColumn get category => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get slot => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  // v2: stable key for system folders. Since v4 every folder is
  // user-owned: the migration moves this value to [templateKey] and clears
  // it. Kept (always null) so older rows and exports stay readable.
  TextColumn get systemKey => text().nullable().unique()();

  // v4: nested, user-created folders.

  /// Parent folder (`null` = top level). The repository cascades deletes
  /// and prevents cycles.
  TextColumn get parentId => text().nullable().references(Folders, #id)();

  /// `FolderIcons` key; `null` = default icon.
  TextColumn get icon => text().nullable()();

  /// `FolderColors` key; `null` = theme accent.
  TextColumn get color => text().nullable()();

  /// `FolderTemplate.key` the folder was created from.
  TextColumn get templateKey => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// `FolderLockMode.name`. A PIN's salted hash lives in the platform
  /// keystore, never here.
  TextColumn get lockMode => text().withDefault(const Constant('none'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v3: offline authenticator accounts (PRD Module 2). Metadata only: the
/// shared secret and recovery codes live in the platform keystore under
/// [secretKeyId], never in SQLite.
@DataClassName('TotpAccountRow')
class TotpAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get issuer => text().nullable()();

  /// flutter_secure_storage key of the Base32 secret.
  TextColumn get secretKeyId => text().unique()();
  IntColumn get digits => integer().withDefault(const Constant(6))();
  IntColumn get period => integer().withDefault(const Constant(30))();
  TextColumn get algorithm => text().withDefault(const Constant('sha1'))();

  /// `totp` or `hotp`.
  TextColumn get type => text().withDefault(const Constant('totp'))();

  /// HOTP moving factor (unused for TOTP).
  IntColumn get counter => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v5: secure notes (feature_notes). Encrypted at rest with the rest of the
/// database (SQLCipher, ADR-0010).
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Plain text; `- [ ] ` / `- [x] ` lines are checklist items.
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Optional category / folder tag.
  TextColumn get tag => text().nullable()();

  /// `NoteTemplate.name`.
  TextColumn get template => text().withDefault(const Constant('custom'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// `FolderLockMode.name`. A PIN's salted hash lives in the keystore.
  TextColumn get lockMode => text().withDefault(const Constant('none'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Library metadata (SQLCipher-encrypted SQLite). Binary files live in the
/// file store.
@DriftDatabase(tables: [Documents, Folders, TotpAccounts, Notes])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_documents_updated ON documents (updated_at)',
      );
      await _createFolderIndexes();
      await _createNoteIndexes();
    },
    // Additive only: every step keeps existing rows untouched.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(documents, documents.category);
        await m.addColumn(documents, documents.expiresAt);
        await m.addColumn(documents, documents.slot);
        // SQLite can't ADD a UNIQUE column; add it plain, then a unique index.
        await customStatement('ALTER TABLE folders ADD COLUMN system_key TEXT');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_system_key '
          'ON folders (system_key)',
        );
      }
      if (from < 3) {
        await m.createTable(totpAccounts);
      }
      if (from < 4) {
        await m.addColumn(folders, folders.parentId);
        await m.addColumn(folders, folders.icon);
        await m.addColumn(folders, folders.color);
        await m.addColumn(folders, folders.templateKey);
        await m.addColumn(folders, folders.sortOrder);
        await m.addColumn(folders, folders.lockMode);
        await m.addColumn(folders, folders.updatedAt);
        await _createFolderIndexes();
        await migrateCategoriesToFolders(this);
      }
      if (from < 5) {
        await m.createTable(notes);
        await _createNoteIndexes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

extension on AppDatabase {
  Future<void> _createNoteIndexes() => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes (pinned, updated_at)',
  );

  Future<void> _createFolderIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders (parent_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_documents_folder ON documents (folder_id)',
    );
  }
}

/// v3 → v4: nothing stays hardcoded and nothing is lost.
///
/// 1. Former system folders become ordinary top-level folders: their
///    `system_key` moves to `template_key` (and is cleared).
/// 2. Documents that had a vault category but no folder are filed into the
///    top-level folder for that category: one made from the same template,
///    else one with the template's name, else a new folder created from the
///    template. `documents.category` itself is kept.
Future<void> migrateCategoriesToFolders(AppDatabase db) async {
  await db.customStatement(
    'UPDATE folders SET template_key = system_key, system_key = NULL '
    'WHERE system_key IS NOT NULL',
  );
  final loose =
      await (db.selectOnly(db.documents, distinct: true)
            ..addColumns([db.documents.category])
            ..where(
              db.documents.category.isNotNull() &
                  db.documents.folderId.isNull(),
            ))
          .map((r) => r.read(db.documents.category)!)
          .get();
  if (loose.isEmpty) return;
  final topLevel = await (db.select(
    db.folders,
  )..where((t) => t.parentId.isNull())).get();
  final now = DateTime.now();
  for (final key in loose) {
    final template = FolderTemplate.byKey(key);
    final category = DocumentCategory.values.asNameMap()[key];
    final label = template?.label ?? category?.label ?? key;
    final folder =
        topLevel.where((f) => f.templateKey == key).firstOrNull ??
        topLevel
            .where((f) => f.name.toLowerCase() == label.toLowerCase())
            .firstOrNull;
    final String folderId;
    if (folder != null) {
      folderId = folder.id;
    } else {
      folderId = newId();
      final row = FoldersCompanion.insert(
        id: folderId,
        name: label,
        createdAt: now,
        templateKey: Value(key),
        icon: Value(template?.icon),
        color: Value(template?.color),
        updatedAt: Value(now),
      );
      await db.into(db.folders).insert(row);
      topLevel.add(
        await (db.select(
          db.folders,
        )..where((t) => t.id.equals(folderId))).getSingle(),
      );
    }
    await (db.update(db.documents)
          ..where((t) => t.category.equals(key) & t.folderId.isNull()))
        .write(DocumentsCompanion(folderId: Value(folderId)));
  }
}
