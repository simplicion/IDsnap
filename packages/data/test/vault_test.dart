import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:engine_pdf/zip.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1 schema exactly as Drift created it before the vault migration.
const _createDocuments =
    'CREATE TABLE documents (id TEXT NOT NULL, name TEXT NOT NULL, '
    'format TEXT NOT NULL, relative_path TEXT NOT NULL, '
    'size_bytes INTEGER NOT NULL, page_count INTEGER NULL, '
    'folder_id TEXT NULL, favorite INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("favorite" IN (0, 1)), thumbnail_path TEXT NULL, '
    'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
    'PRIMARY KEY (id))';
const _createFolders =
    'CREATE TABLE folders (id TEXT NOT NULL, name TEXT NOT NULL, '
    'created_at INTEGER NOT NULL, PRIMARY KEY (id))';
const _insertDocument =
    "INSERT INTO documents VALUES ('d1', 'Old scan', 'pdf', "
    "'documents/a.pdf', 1234, 2, NULL, 1, NULL, 1700000000, 1700000000)";
const _v1 = <String>[
  _createDocuments,
  _createFolders,
  _insertDocument,
  "INSERT INTO folders VALUES ('f1', 'Work', 1700000000)",
  'PRAGMA user_version = 1',
];

const _v3s0 =
    'CREATE TABLE totp_accounts (id TEXT NOT NULL, label TEXT NOT NULL, '
    'issuer TEXT NULL, secret_key_id TEXT NOT NULL UNIQUE, '
    'digits INTEGER NOT NULL DEFAULT 6, period INTEGER NOT NULL DEFAULT 30, '
    "algorithm TEXT NOT NULL DEFAULT 'sha1', "
    "type TEXT NOT NULL DEFAULT 'totp', counter INTEGER NOT NULL DEFAULT 0, "
    'sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, '
    'PRIMARY KEY (id))';
const _v3s1 =
    "INSERT INTO documents VALUES ('d1', 'Passport', 'pdf', 'documents/1.pdf', "
    "10, 1, NULL, 0, NULL, 1700000000, 1700000000, 'ids', NULL, 'passport')";
const _v3s2 =
    "INSERT INTO documents VALUES ('d2', 'Report', 'pdf', 'documents/2.pdf', "
    "10, 1, NULL, 0, NULL, 1700000000, 1700000000, 'medical', NULL, NULL)";
const _v3s3 =
    "INSERT INTO documents VALUES ('d3', 'Plan', 'pdf', 'documents/3.pdf', "
    "10, 1, 'f1', 0, NULL, 1700000000, 1700000000, NULL, NULL, NULL)";
const _v3s4 =
    "INSERT INTO documents VALUES ('d4', 'Badge', 'pdf', 'documents/4.pdf', "
    "10, 1, 'f1', 0, NULL, 1700000000, 1700000000, 'ids', NULL, NULL)";
const _v3s5 =
    "INSERT INTO documents VALUES ('d5', 'Loose', 'txt', 'documents/5.txt', "
    '10, NULL, NULL, 0, NULL, 1700000000, 1700000000, NULL, NULL, NULL)';
const _v3s6 =
    'INSERT INTO totp_accounts (id, label, secret_key_id, created_at) '
    "VALUES ('t1', 'GitHub', 'otp.t1', 1700000000)";

/// v3 schema: v1 plus the v2 vault columns and the v3 authenticator table.
const _v3 = <String>[
  _createDocuments,
  _createFolders,
  'ALTER TABLE documents ADD COLUMN category TEXT NULL',
  'ALTER TABLE documents ADD COLUMN expires_at INTEGER NULL',
  'ALTER TABLE documents ADD COLUMN slot TEXT NULL',
  'ALTER TABLE folders ADD COLUMN system_key TEXT',
  'CREATE UNIQUE INDEX idx_folders_system_key ON folders (system_key)',
  _v3s0,
  "INSERT INTO folders VALUES ('f1', 'Work', 1700000000, NULL)",
  "INSERT INTO folders VALUES ('fs', 'My IDs', 1700000000, 'ids')",
  _v3s1,
  _v3s2,
  _v3s3,
  _v3s4,
  _v3s5,
  _v3s6,
  'PRAGMA user_version = 3',
];

ZipLibraryArchiver _archiver(DataLayer d) => ZipLibraryArchiver(
  repository: d.documents,
  files: d.files,
  notes: d.notes,
  codec: const ZipArchiveCodec(),
);

Future<Document> _addFile(
  DataLayer data,
  String name,
  List<int> bytes,
  DocumentFormat format, {
  DocumentCategory? category,
  DateTime? expiresAt,
}) async {
  final temp = await data.files.writeTemp(
    Uint8List.fromList(bytes),
    format.extension,
  );
  final rel = await data.files.commit(temp, format.extension);
  final now = DateTime(2026, 9, 25);
  final d = Document(
    id: newId(),
    name: name,
    format: format,
    relativePath: rel,
    sizeBytes: bytes.length,
    category: category,
    expiresAt: expiresAt,
    createdAt: now,
    updatedAt: now,
  );
  expect((await data.documents.add(d)).isOk, isTrue);
  return d;
}

void main() {
  test('v1 → v2 migration keeps rows and adds vault columns', () async {
    var seeded = false;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          if (seeded) return;
          seeded = true;
          _v1.forEach(raw.execute);
        },
      ),
    );
    addTearDown(db.close);
    final repo = DriftDocumentRepository(db);
    final old = await repo.byId('d1');
    expect(old?.name, 'Old scan');
    expect(old?.pageCount, 2);
    expect(old?.favorite, isTrue);
    expect(old?.category, isNull);

    final updated = old!.copyWith(
      category: DocumentCategory.ids,
      expiresAt: DateTime(2030, 1, 2),
      slot: 'passport',
    );
    expect((await repo.update(updated)).isOk, isTrue);
    final back = await repo.byId('d1');
    expect(back?.category, DocumentCategory.ids);
    expect(back?.expiresAt, DateTime(2030, 1, 2));
    expect(back?.slot, 'passport');

    final folders = await repo.watchFolders().first;
    expect(folders.single.name, 'Work');
    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, db.schemaVersion);
  });

  test('v3 → v4 migration turns categories into ordinary folders', () async {
    var seeded = false;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          if (seeded) return;
          seeded = true;
          _v3.forEach(raw.execute);
        },
      ),
    );
    addTearDown(db.close);
    final repo = DriftDocumentRepository(db);
    final tree = FolderTree(await repo.allFolders());

    // The old system folder is now an ordinary top-level folder.
    final formerSystem = tree['fs']!;
    expect(formerSystem.templateKey, 'ids');
    expect(formerSystem.parentId, isNull);
    expect(formerSystem.lockMode, FolderLockMode.none);
    final systemKeys = await db
        .customSelect('SELECT system_key FROM folders')
        .map((r) => r.readNullable<String>('system_key'))
        .get();
    expect(systemKeys.every((k) => k == null), isTrue);

    // Loose categorized documents were filed; nothing else moved.
    expect((await repo.byId('d1'))?.folderId, 'fs');
    expect((await repo.byId('d1'))?.category, DocumentCategory.ids);
    final medical = tree.all.singleWhere((f) => f.templateKey == 'medical');
    expect(medical.name, 'Medical & Health');
    expect(medical.icon, FolderIcons.medical);
    expect((await repo.byId('d2'))?.folderId, medical.id);
    expect((await repo.byId('d3'))?.folderId, 'f1');
    expect((await repo.byId('d4'))?.folderId, 'f1');
    expect((await repo.byId('d5'))?.folderId, isNull);
    expect(tree.all.length, 3);

    // The authenticator table is untouched.
    final totp = await db.select(db.totpAccounts).get();
    expect(totp.single.label, 'GitHub');

    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, 5);

    // New columns work.
    final child = await repo.createFolder(name: 'Sub', parentId: 'f1');
    expect(child.isOk, isTrue);
  });

  group('vault', () {
    late Directory tmp;
    late DataLayer data;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('docscan_vault');
      data = await openDataLayer(
        rootOverride: tmp.path,
        executor: NativeDatabase.memory(),
      );
    });

    tearDown(() async {
      await data.close();
      await tmp.delete(recursive: true);
    });

    test('category filter and live counts', () async {
      await _addFile(
        data,
        'Passport',
        '%PDF-1.7 a'.codeUnits,
        DocumentFormat.pdf,
        category: DocumentCategory.ids,
      );
      await _addFile(
        data,
        'Licence',
        '%PDF-1.7 b'.codeUnits,
        DocumentFormat.pdf,
        category: DocumentCategory.ids,
      );
      await _addFile(
        data,
        'Report',
        '%PDF-1.7 c'.codeUnits,
        DocumentFormat.pdf,
        category: DocumentCategory.medical,
      );
      await _addFile(data, 'Loose', 'hello'.codeUnits, DocumentFormat.txt);

      final ids = await data.documents
          .watch(const DocumentQuery(category: DocumentCategory.ids))
          .first;
      expect(ids.map((d) => d.name), unorderedEquals(['Passport', 'Licence']));

      final counts = await data.documents.watchCategoryCounts().first;
      expect(counts[DocumentCategory.ids], 2);
      expect(counts[DocumentCategory.medical], 1);
      expect(counts.containsKey(DocumentCategory.tax), isFalse);
    });

    test(
      'a newly categorized document is filed into its template folder',
      () async {
        final repo = data.documents;
        final ids = (await repo.createFolder(
          name: 'IDs & Proofs',
          templateKey: 'ids',
        )).valueOrNull!;
        final card = await _addFile(
          data,
          'ID card',
          '%PDF-1.7 card'.codeUnits,
          DocumentFormat.pdf,
          category: DocumentCategory.ids,
        );
        expect((await repo.byId(card.id))?.folderId, ids.id);

        // Committed first, categorized afterwards (the ID card flow).
        final later = await _addFile(
          data,
          'Later',
          '%PDF-1.7 later'.codeUnits,
          DocumentFormat.pdf,
        );
        await repo.update(later.copyWith(category: DocumentCategory.ids));
        expect((await repo.byId(later.id))?.folderId, ids.id);

        // Moving it to the top level afterwards sticks.
        await repo.moveDocuments([later.id], null);
        final moved = (await repo.byId(later.id))!;
        await repo.update(moved.copyWith(favorite: true));
        expect((await repo.byId(later.id))?.folderId, isNull);

        // No matching folder: stays at the top level (nothing is created).
        final med = await _addFile(
          data,
          'Report',
          '%PDF-1.7 med'.codeUnits,
          DocumentFormat.pdf,
          category: DocumentCategory.medical,
        );
        expect((await repo.byId(med.id))?.folderId, isNull);
        expect((await repo.allFolders()).length, 1);
      },
    );

    test('archiver export → import keeps the nested folder tree', () async {
      final repo = data.documents;
      final ids = (await repo.createFolder(
        name: 'IDs & Proofs',
        templateKey: 'ids',
        icon: FolderIcons.badge,
        color: FolderColors.blue,
      )).valueOrNull!;
      final passports = (await repo.createFolder(
        name: 'Passport',
        parentId: ids.id,
      )).valueOrNull!;
      final empty = (await repo.createFolder(
        name: 'Empty one',
        parentId: passports.id,
      )).valueOrNull!;
      await repo.setFolderLockMode(ids.id, FolderLockMode.pin);
      final p1 = await _addFile(
        data,
        'Passport',
        '%PDF-1.7 passport'.codeUnits,
        DocumentFormat.pdf,
        category: DocumentCategory.ids,
        expiresAt: DateTime(2031, 5, 6),
      );
      await repo.moveDocuments([p1.id], passports.id);
      final p2 = await _addFile(
        data,
        'Passport',
        '%PDF-1.7 second copy!'.codeUnits,
        DocumentFormat.pdf,
      );
      await repo.moveDocuments([p2.id], passports.id);
      await _addFile(
        data,
        'Notes',
        'hello vault'.codeUnits,
        DocumentFormat.txt,
      );

      final exported = await _archiver(data).exportBackup();
      final zipBytes = File(exported.valueOrNull!.path).readAsBytesSync();
      final names = ZipDecoder()
          .decodeBytes(zipBytes)
          .files
          .map((f) => f.name)
          .toList();
      expect(names, contains('manifest.json'));
      expect(names, contains('IDs & Proofs/Passport/Passport.pdf'));
      expect(names, contains('IDs & Proofs/Passport/Passport (2).pdf'));
      expect(names, contains('IDs & Proofs/Passport/Empty one/'));
      expect(names, contains('Notes.txt'));

      final tmp2 = await Directory.systemTemp.createTemp('docscan_vault2');
      final fresh = await openDataLayer(
        rootOverride: tmp2.path,
        executor: NativeDatabase.memory(),
      );
      addTearDown(() async {
        await fresh.close();
        await tmp2.delete(recursive: true);
      });
      final zipFile = File('${tmp2.path}/backup.zip')
        ..writeAsBytesSync(zipBytes);
      final imported = await _archiver(fresh).importBackup(zipFile.path);
      expect(imported.valueOrNull!.documents, 3);
      expect(imported.valueOrNull!.pinLockedFolders, 1);

      final tree = FolderTree(await fresh.documents.allFolders());
      expect(tree.all.length, 3);
      final top = tree.children(null).single;
      expect(top.name, 'IDs & Proofs');
      expect(top.templateKey, 'ids');
      expect(top.icon, FolderIcons.badge);
      // The PIN never leaves the keystore: the folder comes back locked
      // with the phone's screen lock instead.
      expect(top.lockMode, FolderLockMode.device);
      final sub = tree.children(top.id).single;
      expect(sub.name, 'Passport');
      expect(tree.children(sub.id).single.name, empty.name);

      final inSub =
          (await fresh.documents.watchContents(sub.id).first).documents;
      expect(inSub, hasLength(2));
      final passport = inSub.firstWhere((d) => d.expiresAt != null);
      expect(passport.category, DocumentCategory.ids);
      expect(passport.expiresAt, DateTime(2031, 5, 6));
      final root = (await fresh.documents.watchContents(null).first).documents;
      final notes = root.single;
      expect(notes.name, 'Notes');
      expect(
        await fresh.files.readText(fresh.files.absolute(notes.relativePath)),
        'hello vault',
      );

      // Importing the same archive again adds nothing (dedupe by name+size)
      // and reuses the existing folders.
      final again = await _archiver(fresh).importBackup(zipFile.path);
      expect(again.valueOrNull!.documents, 0);
      expect((await fresh.documents.allFolders()).length, 3);
    });

    test('version-1 backups import category folders as folders', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes('IDs & Proofs/Card.pdf', '%PDF-1.7 v1'.codeUnits),
        )
        ..addFile(ArchiveFile.bytes('Other/Loose.txt', 'loose'.codeUnits))
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            '{"version": 1, "documents": [{"path": "IDs & Proofs/Card.pdf", '
                '"name": "Card", "category": "ids"}]}',
          ),
        );
      final zip = File('${tmp.path}/v1.zip')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final r1 = await _archiver(data).importBackup(zip.path);
      expect(r1.valueOrNull!.documents, 2);
      final folder = (await data.documents.allFolders()).single;
      expect(folder.name, 'IDs & Proofs');
      expect(folder.templateKey, 'ids');
      final inside =
          (await data.documents.watchContents(folder.id).first).documents;
      expect(inside.single.name, 'Card');
      final root = (await data.documents.watchContents(null).first).documents;
      expect(root.single.name, 'Loose');
    });

    test('import rejects a non-zip and skips unidentifiable entries', () async {
      final bad = File('${tmp.path}/bad.zip')..writeAsStringSync('nope');
      final r = await _archiver(data).importBackup(bad.path);
      expect(r.failureOrNull?.code, FailureCode.corruptFile);

      final archive = Archive()
        ..addFile(ArchiveFile.bytes('blob.bin', [0, 1, 2, 3, 0, 0]))
        ..addFile(ArchiveFile.bytes('ok.txt', 'fine'.codeUnits));
      final zip = File('${tmp.path}/mixed.zip')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final r2 = await _archiver(data).importBackup(zip.path);
      expect(r2.valueOrNull!.documents, 1);
    });
  });

  test('uniquePath dedupes case-insensitively', () {
    final used = <String>{};
    expect(ZipLibraryArchiver.uniquePath('A', 'x', 'pdf', used), 'A/x.pdf');
    expect(ZipLibraryArchiver.uniquePath('A', 'X', 'pdf', used), 'A/X (2).pdf');
    expect(ZipLibraryArchiver.uniquePath('', 'x', 'pdf', used), 'x.pdf');
  });
}
