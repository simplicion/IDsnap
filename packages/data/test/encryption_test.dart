import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:engine_pdf/zip.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// In-memory keystore.
class _Keys implements VaultKeyStore {
  VaultKey? key;
  int created = 0;

  @override
  Future<VaultKey> create() async {
    created++;
    final r = Random.secure();
    return key = VaultKey(
      id: 1,
      bytes: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
    );
  }

  @override
  Future<void> delete() async => key = null;

  @override
  Future<VaultKey?> read() async => key;
}

const _crypto = AesGcmVaultCrypto(pureDart: true, runInIsolate: false);

Uint8List _bytes(int n, [int seed = 1]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

bool _sealed(String path) =>
    VaultFormat.isEncrypted(File(path).readAsBytesSync().take(8).toList());

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

ZipLibraryArchiver _archiver(DataLayer d) => ZipLibraryArchiver(
  repository: d.documents,
  files: d.files,
  notes: d.notes,
  codec: const ZipArchiveCodec(),
);

Future<Document> _addDoc(DataLayer data, Uint8List bytes, String name) async {
  final temp = await data.files.writeTemp(bytes, 'pdf');
  final rel = await data.files.commit(temp, 'pdf');
  final thumb = await data.files.writeThumbnail(
    'thumb-$name',
    Uint8List.fromList(utf8.encode('thumbnail of $name')),
  );
  final now = DateTime(2026);
  final doc = Document(
    id: newId(),
    name: name,
    format: DocumentFormat.pdf,
    relativePath: rel,
    sizeBytes: bytes.length,
    thumbnailPath: thumb,
    createdAt: now,
    updatedAt: now,
  );
  expect((await data.documents.add(doc)).isOk, isTrue);
  return doc;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late String root;
  late String cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('docscan_enc');
    root = p.join(tmp.path, 'vault');
    cache = p.join(tmp.path, 'cache');
  });
  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // SQLCipher's background isolate may still hold a handle on Windows.
    }
  });

  group('encrypted LocalFileStore', () {
    late LocalFileStore files;
    setUp(() async {
      files = LocalFileStore(
        root,
        cacheRoot: cache,
        cipher: _crypto.fileCipher(await _Keys().create()),
      );
      await files.ensureLayout();
    });

    test('commit, thumbnails and originals are encrypted on disk', () async {
      final plain = Uint8List.fromList(
        utf8.encode('%PDF-1.7 passport number X1234567 ${'a' * 3000}'),
      );
      final temp = await files.writeTemp(plain, 'pdf');
      expect(p.isWithin(cache, temp), isTrue);
      final rel = await files.commit(temp, 'pdf');
      expect(File(temp).existsSync(), isFalse);
      final onDisk = File(files.absolute(rel)).readAsBytesSync();
      expect(_sealed(files.absolute(rel)), isTrue);
      expect(_contains(onDisk, utf8.encode('X1234567')), isFalse);
      expect(await files.read(rel), plain);
      expect(await files.readText(rel), utf8.decode(plain));
      expect(await files.size(rel), plain.length);

      final thumb = await files.writeThumbnail('d1', Uint8List(50));
      expect(_sealed(files.absolute(thumb)), isTrue);
      expect(await files.read(thumb), Uint8List(50));

      final ext = File(p.join(tmp.path, 'camera.JPG'))
        ..writeAsBytesSync(_bytes(5000));
      final original = await files.importOriginal(ext.path);
      expect(_sealed(original), isTrue);
      expect(await files.read(original), _bytes(5000));
    });

    test('large files decrypt through the streaming path', () async {
      final plain = _bytes(1500 * 1024);
      final rel = await files.commit(
        await files.writeTemp(plain, 'pdf'),
        'pdf',
      );
      expect(await files.read(rel), plain);
    });

    test(
      'decryptToTemp makes a private plaintext copy; release shreds it',
      () async {
        final plain = _bytes(3000);
        final rel = await files.commit(
          await files.writeTemp(plain, 'pdf'),
          'pdf',
        );
        final view = await files.decryptToTemp(rel, fileName: 'Scan.pdf');
        expect(p.isWithin(p.join(cache, 'view'), view), isTrue);
        expect(p.basename(view), 'Scan.pdf');
        expect(File(view).readAsBytesSync(), plain);
        await files.releaseTemp(view);
        expect(File(view).existsSync(), isFalse);

        // Not encrypted (e.g. a picked file): returned as is, never deleted.
        final outside = File(p.join(tmp.path, 'picked.pdf'))
          ..writeAsBytesSync(plain);
        expect(await files.decryptToTemp(outside.path), outside.path);
        await files.releaseTemp(outside.path);
        expect(outside.existsSync(), isTrue);
      },
    );

    test('exportCopy decrypts into the share folder', () async {
      final plain = _bytes(999);
      final rel = await files.commit(
        await files.writeTemp(plain, 'pdf'),
        'pdf',
      );
      final shared = await files.exportCopy(rel, 'My: scan?.pdf');
      expect(p.isWithin(p.join(cache, 'share'), shared), isTrue);
      expect(p.basename(shared), 'My_ scan_.pdf');
      expect(File(shared).readAsBytesSync(), plain);
      await files.releaseTemp(shared, grace: const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(File(shared).existsSync(), isFalse);
    });

    test('clearTemp shreds work files and every plaintext copy', () async {
      final rel = await files.commit(
        await files.writeTemp(_bytes(10), 'pdf'),
        'pdf',
      );
      final view = await files.decryptToTemp(rel);
      final shared = await files.exportCopy(rel, 'x.pdf');
      final work = await files.writeTemp(_bytes(10), 'bin');
      await files.clearTemp();
      for (final f in [view, shared, work]) {
        expect(File(f).existsSync(), isFalse, reason: f);
      }
      expect(await files.read(rel), _bytes(10));
      expect((await files.usage()).temp, 0);
    });

    test('shredFile overwrites before deleting', () async {
      final f = File(p.join(tmp.path, 's.bin'))..writeAsBytesSync(_bytes(100));
      await shredFile(f.path);
      expect(f.existsSync(), isFalse);
      await shredFile(f.path); // Missing file: no error.
    });
  });

  group('openDataLayer with encryption', () {
    Future<DataLayer> open(_Keys keys, {bool memory = false}) => openDataLayer(
      rootOverride: root,
      cacheOverride: cache,
      executor: memory ? NativeDatabase.memory() : null,
      security: VaultSecurity(keys: keys, crypto: _crypto),
    );

    test(
      'a fresh vault gets a key, an encrypted DB and encrypted files',
      () async {
        final keys = _Keys();
        final data = await open(keys);
        expect(data.encrypted, isTrue);
        expect(keys.created, 1);
        final doc = await _addDoc(data, _bytes(2000), 'Passport');
        await data.close();

        final dbPath = p.join(root, 'library.sqlite');
        expect(EncryptedDatabase.isPlaintext(dbPath), isFalse);
        expect(
          _contains(File(dbPath).readAsBytesSync(), utf8.encode('Passport')),
          isFalse,
        );
        expect(File(VaultStateFile.path(root)).existsSync(), isTrue);

        // Same key: everything reads back; no second key is created.
        final again = await open(keys);
        expect(keys.created, 1);
        final back = await again.documents.byId(doc.id);
        expect(back?.name, 'Passport');
        expect(await again.files.read(back!.relativePath), _bytes(2000));
        await again.close();
      },
    );

    test('fails closed when the key is missing or different', () async {
      final keys = _Keys();
      final data = await open(keys);
      await _addDoc(data, _bytes(10), 'A');
      await data.close();

      await expectLater(
        open(_Keys()),
        throwsA(
          isA<VaultUnavailableException>().having(
            (e) => e.reason,
            'reason',
            VaultUnavailableReason.keyMissing,
          ),
        ),
      );
      final other = _Keys();
      await other.create();
      await expectLater(
        open(other),
        throwsA(
          isA<VaultUnavailableException>().having(
            (e) => e.reason,
            'reason',
            VaultUnavailableReason.keyMismatch,
          ),
        ),
      );
      // Even without vault.json, encrypted files alone block key creation.
      File(VaultStateFile.path(root)).deleteSync();
      expect(await hasEncryptedContent(root), isTrue);
      await expectLater(
        open(_Keys()),
        throwsA(isA<VaultUnavailableException>()),
      );
    });

    test('erase vault starts fresh', () async {
      final keys = _Keys();
      final data = await open(keys, memory: true);
      await _addDoc(data, _bytes(10), 'A');
      await data.close();
      await eraseVault(root: root, cacheRoot: cache, keys: keys);
      expect(keys.key, isNull);
      expect(Directory(root).existsSync(), isFalse);
      final fresh = await open(_Keys(), memory: true);
      expect(await fresh.documents.all(), isEmpty);
      await fresh.close();
    });

    test('an existing plaintext vault is migrated: files and DB', () async {
      final legacy = await openDataLayer(
        rootOverride: root,
        cacheOverride: cache,
      );
      final plain = Uint8List.fromList(
        utf8.encode('%PDF secret ${'z' * 5000}'),
      );
      final doc = await _addDoc(legacy, plain, 'Bank letter');
      final original = await legacy.files.importOriginal(
        (File(p.join(tmp.path, 'c.jpg'))..writeAsBytesSync(_bytes(300))).path,
      );
      Directory(p.join(root, 'signatures')).createSync();
      File(p.join(root, 'signatures', 'sig.png')).writeAsBytesSync(_bytes(64));
      await legacy.close();
      expect(
        EncryptedDatabase.isPlaintext(p.join(root, 'library.sqlite')),
        isTrue,
      );
      expect(_sealed(p.join(root, doc.relativePath)), isFalse);

      final progress = <(int, int)>[];
      final keys = _Keys();
      final data = await openDataLayer(
        rootOverride: root,
        cacheOverride: cache,
        security: VaultSecurity(keys: keys, crypto: _crypto),
        onMigration: (d, t) => progress.add((d, t)),
      );
      expect(progress.last, (4, 4)); // Document, thumbnail, original, sig.
      for (final f in [
        p.join(root, doc.relativePath),
        p.join(root, doc.thumbnailPath),
        original,
        p.join(root, 'signatures', 'sig.png'),
      ]) {
        expect(_sealed(f), isTrue, reason: f);
      }
      expect(
        EncryptedDatabase.isPlaintext(p.join(root, 'library.sqlite')),
        isFalse,
      );
      final back = await data.documents.byId(doc.id);
      expect(back?.name, 'Bank letter');
      expect(await data.files.read(back!.relativePath), plain);
      expect(await data.files.read(original), _bytes(300));
      final leftovers = Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.plain-old') ||
                f.path.endsWith('.enc-part') ||
                f.path.endsWith('.enc-tmp'),
          );
      expect(leftovers, isEmpty);
      await data.close();
    });
  });

  group('file migration crash safety', () {
    for (final step in ['encrypted', 'renamedOld', 'renamedNew']) {
      test('killed after "$step" loses nothing and resumes', () async {
        final dir = Directory(p.join(root, 'documents'))
          ..createSync(recursive: true);
        final originals = {
          for (var i = 0; i < 3; i++)
            p.join(dir.path, 'f$i.pdf'): _bytes(4000 + i, i),
        }..forEach((path, b) => File(path).writeAsBytesSync(b));
        final cipher = _crypto.fileCipher(await _Keys().create());
        var calls = 0;
        final crashing = VaultFileMigrator(
          cipher: cipher,
          directories: [dir.path],
          scratchDirectory: p.join(cache, 'verify'),
          onStep: (s, path) {
            // Crash on the second file, after [step].
            if (s == step && ++calls == 2) throw StateError('killed');
          },
        );
        await expectLater(crashing.run(), throwsStateError);

        final resumed = VaultFileMigrator(
          cipher: cipher,
          directories: [dir.path],
          scratchDirectory: p.join(cache, 'verify'),
        );
        expect(await resumed.pending(), isNotEmpty);
        await resumed.run();
        expect(await resumed.pending(), isEmpty);
        for (final e in originals.entries) {
          expect(_sealed(e.key), isTrue);
          expect(await cipher.decryptFileToBytes(e.key), e.value);
        }
        final names = dir.listSync().map((f) => p.basename(f.path)).toSet();
        expect(names, {'f0.pdf', 'f1.pdf', 'f2.pdf'});
      });
    }

    test('a stale partial cipher output is removed', () async {
      final dir = Directory(p.join(root, 'thumbs'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'a.jpg')).writeAsBytesSync(_bytes(10));
      File(p.join(dir.path, 'a.jpg.enc-part.part')).writeAsBytesSync([1, 2]);
      File(p.join(dir.path, 'b.jpg.part')).writeAsBytesSync([1, 2]);
      final cipher = _crypto.fileCipher(await _Keys().create());
      await VaultFileMigrator(
        cipher: cipher,
        directories: [dir.path],
        scratchDirectory: p.join(cache, 'verify'),
      ).run();
      expect(dir.listSync().map((f) => p.basename(f.path)), ['a.jpg']);
      expect(
        await cipher.decryptFileToBytes(p.join(dir.path, 'a.jpg')),
        _bytes(10),
      );
    });
  });

  group('SQLCipher', () {
    late String dbPath;
    late String hex;

    setUp(() {
      Directory(root).createSync(recursive: true);
      dbPath = p.join(root, 'library.sqlite');
      hex = EncryptedDatabase.hexKey(_bytes(32, 9));
      final db = sqlite3.open(dbPath)
        ..execute('CREATE TABLE t (x TEXT)')
        ..execute('CREATE TABLE u (y INTEGER)')
        ..execute('PRAGMA user_version = 4');
      for (var i = 0; i < 50; i++) {
        db.execute("INSERT INTO t VALUES ('secret row $i')");
      }
      db.close();
    });

    int count(String table) {
      final db = sqlite3.open(dbPath);
      try {
        EncryptedDatabase.applyKey(db, hex);
        return db.select('SELECT count(*) AS n FROM $table').first['n'] as int;
      } finally {
        db.close();
      }
    }

    test('this host links SQLCipher', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(db.select('PRAGMA cipher_version').first.values.first, isNotEmpty);
    });

    test('plaintext → SQLCipher keeps every row; the wrong key fails', () {
      expect(EncryptedDatabase.migrateSync(dbPath, hex), isTrue);
      expect(EncryptedDatabase.isPlaintext(dbPath), isFalse);
      expect(count('t'), 50);
      final db = sqlite3.open(dbPath);
      addTearDown(db.close);
      expect(
        () => EncryptedDatabase.applyKey(
          db,
          EncryptedDatabase.hexKey(_bytes(32)),
        ),
        throwsA(isA<SqliteException>()),
      );
      final v = sqlite3.open(dbPath);
      EncryptedDatabase.applyKey(v, hex);
      expect(v.select('PRAGMA user_version').first.values.first, 4);
      v.close();
      // Idempotent.
      expect(EncryptedDatabase.migrateSync(dbPath, hex), isFalse);
    });

    for (final step in ['exported', 'renamedOld', 'renamedNew']) {
      test('interrupted after "$step" resumes without data loss', () {
        expect(
          () => EncryptedDatabase.migrateSync(dbPath, hex, crashAt: step),
          throwsA(anything),
        );
        EncryptedDatabase.migrateSync(dbPath, hex);
        expect(EncryptedDatabase.isPlaintext(dbPath), isFalse);
        expect(count('t'), 50);
        for (final s in EncryptedDatabase.tmpSuffixes) {
          expect(File('$dbPath$s').existsSync(), isFalse, reason: s);
        }
      });
    }
  });

  group('notes', () {
    late DataLayer data;
    setUp(() async {
      data = await openDataLayer(
        rootOverride: root,
        executor: NativeDatabase.memory(),
      );
    });
    tearDown(() => data.close());

    test('create, save, pin order, search hides locked, delete', () async {
      final notes = data.notes;
      final wifi = (await notes.create(
        title: 'Home Wi-Fi',
        body: NoteTemplate.wifi.body,
        template: NoteTemplate.wifi,
      )).valueOrNull!;
      final bank = (await notes.create(
        title: 'Bank',
        tag: ' Finance ',
      )).valueOrNull!;
      expect(bank.tag, 'Finance');
      await notes.save(bank.copyWith(body: 'Account number: 12345'));
      await notes.setPinned(wifi.id, pinned: true);

      var list = await notes.watch().first;
      expect(list.map((n) => n.title), ['Home Wi-Fi', 'Bank']);
      expect((await notes.watch(search: '12345').first).single.id, bank.id);
      expect((await notes.watch(search: 'finance').first).single.id, bank.id);

      await notes.setLockMode(bank.id, FolderLockMode.pin);
      expect(await notes.watch(search: '12345').first, isEmpty);
      expect(await notes.watch(search: 'Bank').first, isEmpty);
      list = await notes.watch().first;
      expect(list, hasLength(2)); // Still listed, without a preview.
      expect(list.last.isLocked, isTrue);
      expect(list.last.preview, isEmpty);

      await notes.delete(wifi.id);
      expect(await notes.byId(wifi.id), isNull);
      expect((await notes.save(wifi)).isOk, isFalse);
    });

    test('export and import include notes', () async {
      await data.notes.create(title: 'Recovery', body: '- [ ] code-1');
      final locked = (await data.notes.create(title: 'PIN hint')).valueOrNull!;
      await data.notes.setLockMode(locked.id, FolderLockMode.pin);
      final exported = await _archiver(data).exportBackup();
      final zip = File(exported.valueOrNull!.path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zip);
      expect(archive.findFile(ZipLibraryArchiver.notesPath), isNotNull);

      final other = await openDataLayer(
        rootOverride: p.join(tmp.path, 'other'),
        executor: NativeDatabase.memory(),
      );
      addTearDown(other.close);
      final path = p.join(tmp.path, 'backup.zip');
      File(path).writeAsBytesSync(zip);
      expect((await _archiver(other).importBackup(path)).valueOrNull!.notes, 2);
      final restored = await other.notes.all();
      expect(restored.map((n) => n.title).toSet(), {'Recovery', 'PIN hint'});
      expect(
        restored.singleWhere((n) => n.title == 'PIN hint').lockMode,
        FolderLockMode.device,
      );
      // Importing again adds nothing.
      expect((await _archiver(other).importBackup(path)).valueOrNull!.total, 0);
    });

    test('v4 → v5 migration adds the notes table and keeps data', () async {
      final file = p.join(tmp.path, 'v4.sqlite');
      final v5 = AppDatabase(NativeDatabase(File(file)));
      await DriftDocumentRepository(v5).createFolder(name: 'Kept');
      await v5.customStatement('DROP TABLE notes');
      await v5.customStatement('PRAGMA user_version = 4');
      await v5.close();

      final db = AppDatabase(NativeDatabase(File(file)));
      addTearDown(db.close);
      final repo = DriftNotesRepository(db);
      expect((await repo.create(title: 'New')).isOk, isTrue);
      expect(
        (await DriftDocumentRepository(db).allFolders()).single.name,
        'Kept',
      );
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(version, 5);
    });
  });
}
