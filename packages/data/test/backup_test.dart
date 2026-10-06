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
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_pdf/zip.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Full backup (audit H-04/H-05), "Erase everything" (H-06) and plaintext
// scratch cleanup (H-07) on an encrypted vault with in-memory keystores.

class _Keys implements VaultKeyStore {
  VaultKey? key;

  @override
  Future<VaultKey> create() async {
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

class _Secrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

/// Stands in for the signature / QR sections that live in feature packages.
class _MemorySection implements BackupSection {
  _MemorySection(this.key, this.label);

  @override
  final String key;
  @override
  final String label;
  List<String> items = [];

  @override
  Future<BackupSectionData?> export() async => items.isEmpty
      ? null
      : BackupSectionData(version: 1, data: items, count: items.length);

  @override
  Future<int> restore(Object? data, {required int version}) async {
    var added = 0;
    for (final i in (data! as List).cast<String>()) {
      if (!items.contains(i)) {
        items.add(i);
        added++;
      }
    }
    return added;
  }

  @override
  Future<void> erase() async => items = [];
}

const _crypto = AesGcmVaultCrypto(pureDart: true, runInIsolate: false);
const _codec = ZipArchiveCodec();

Uint8List _pdf(String text) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7 $text'));

Future<Document> _addDoc(
  DataLayer data,
  String name,
  Uint8List bytes, {
  String? folderId,
  bool thumb = false,
}) async {
  final temp = await data.files.writeTemp(bytes, 'pdf');
  final rel = await data.files.commit(temp, 'pdf');
  final id = newId();
  final thumbPath = thumb
      ? await data.files.writeThumbnail(
          id,
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]),
        )
      : null;
  final now = DateTime(2026, 10);
  final doc = Document(
    id: id,
    name: name,
    format: DocumentFormat.pdf,
    relativePath: rel,
    sizeBytes: bytes.length,
    folderId: folderId,
    thumbnailPath: thumbPath,
    expiresAt: DateTime(2031, 5, 6),
    createdAt: now,
    updatedAt: now,
  );
  expect((await data.documents.add(doc)).isOk, isTrue);
  return doc;
}

List<String> _filesUnder(String dir) => Directory(dir).existsSync()
    ? [
        for (final e in Directory(dir).listSync(recursive: true))
          if (e is File) e.path,
      ]
    : const [];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late String root;
  late String cache;
  late _Keys keys;
  late _Secrets secrets;
  late DataLayer data;
  late DriftAuthenticatorRepository auth;
  late _MemorySection signatures;
  late _MemorySection qr;
  late List<BackupSection> sections;
  late DataVaultEraser eraser;
  late ZipLibraryArchiver archiver;

  Future<void> open() async {
    data = await openDataLayer(
      rootOverride: root,
      cacheOverride: cache,
      executor: NativeDatabase.memory(),
      security: VaultSecurity(keys: keys, crypto: _crypto),
      archiveCodec: _codec,
    );
    auth = DriftAuthenticatorRepository(
      data.database,
      secrets: secrets,
      codec: const OtpCodecImpl(),
    );
    sections = [
      AuthenticatorBackupSection(auth),
      signatures,
      qr,
      SettingsBackupSection(data.settings),
    ];
    eraser = DataVaultEraser(
      database: data.database,
      documents: data.documents,
      files: data.files,
      drafts: data.drafts,
      settings: data.settings,
      targets: [
        ...sections,
        SecretPrefixEraser(secrets, const [
          'folder_pin.',
          'folder_pin_attempts.',
        ], label: 'PINs'),
      ],
    );
    archiver = data.archiver;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('docscan_backup');
    root = p.join(tmp.path, 'vault');
    cache = p.join(tmp.path, 'cache');
    keys = _Keys();
    secrets = _Secrets();
    signatures = _MemorySection('signatures', 'Saved signatures');
    qr = _MemorySection('qr-history', 'QR history');
    await open();
  });

  tearDown(() async {
    await data.close();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A background isolate may still hold a handle on Windows.
    }
  });

  /// A vault with everything a user could lose when moving phones.
  Future<void> populate() async {
    final repo = data.documents;
    final ids = (await repo.createFolder(
      name: 'IDs & Proofs',
      templateKey: 'ids',
    )).valueOrNull!;
    final secret = (await repo.createFolder(
      name: 'Private',
      parentId: ids.id,
    )).valueOrNull!;
    await repo.createFolder(name: 'Empty');
    await _addDoc(data, 'Passport', _pdf('passport'), folderId: ids.id);
    await _addDoc(data, 'Bank card', _pdf('bank'), folderId: secret.id);
    await _addDoc(data, 'Loose', _pdf('loose'), thumb: true);
    // Locked with a PIN: hidden from the normal listings.
    await repo.setFolderLockMode(secret.id, FolderLockMode.pin);
    secrets.values['folder_pin.${secret.id}'] = 'hash';

    await data.notes.create(title: 'Wi-Fi', body: 'password: hunter2');

    final gh = (await auth.add(
      const NewOtpAccount(
        label: 'me@example.com',
        issuer: 'GitHub',
        secret: 'JBSWY3DPEHPK3PXP',
      ),
    )).valueOrNull!;
    await auth.saveRecoveryCodes(gh, const [
      RecoveryCode('aaaa-1111'),
      RecoveryCode('bbbb-2222', used: true),
    ]);
    await auth.add(
      const NewOtpAccount(
        label: 'counter',
        secret: 'GEZDGNBVGY3TQOJQ',
        type: OtpType.hotp,
        counter: 7,
      ),
    );

    signatures.items = ['sig-png-base64'];
    qr.items = ['https://example.com'];
    await data.settings.save(
      const AppSettings(theme: ThemePreference.dark, appLock: true),
    );
    // Licence data lives in its own storage; this stands in for any other
    // keystore entry that must survive "Erase everything".
    secrets.values['billing.trial'] = 'keep me';
  }

  test('full export → erase everything → import restores everything', () async {
    await populate();
    final progress = <BackupProgress>[];
    final exported = await archiver.exportBackup(
      password: 'Moving-Phones-2026',
      sections: sections,
      onProgress: progress.add,
    );
    final backup = exported.valueOrNull!;
    expect(exported.failureOrNull, isNull);
    expect(backup.protected, isTrue);
    expect(backup.documents, 3);
    expect(backup.notes, 1);
    expect(backup.sections, {
      'authenticator': 2,
      'signatures': 1,
      'qr-history': 1,
      'settings': 1,
    });
    expect(progress.last.fraction, 1);
    // Keep a copy outside the cache (the user saves it elsewhere).
    final saved = p.join(tmp.path, 'saved.zip');
    File(backup.path).copySync(saved);
    final raw = File(saved).readAsBytesSync();
    for (final secretText in ['JBSWY3DPEHPK3PXP', 'hunter2', 'aaaa-1111']) {
      expect(latin1.decode(raw).contains(secretText), isFalse);
    }
    // Readable by an independent AE-2 reader with the password.
    final independent = ZipDecoder().decodeBytes(
      raw,
      password: 'Moving-Phones-2026',
    );
    final manifest =
        jsonDecode(
              utf8.decode(independent.findFile('manifest.json')!.readBytes()!),
            )
            as Map<String, dynamic>;
    expect(manifest['version'], 3);
    expect(
      independent.findFile('IDs & Proofs/Private/Bank card.pdf'),
      isNotNull,
    );

    // ── Erase everything ──
    final erased = await eraser.eraseEverything();
    expect(erased.failureOrNull, isNull);
    expect(await data.documents.all(), isEmpty);
    expect(await data.documents.allFolders(), isEmpty);
    expect(await data.notes.all(), isEmpty);
    expect(await auth.watchAccounts().first, isEmpty);
    expect(secrets.values.keys, ['billing.trial']);
    expect(keys.key, isNotNull, reason: 'vault key is kept');
    expect(signatures.items, isEmpty);
    expect(qr.items, isEmpty);
    expect((await data.settings.load()).theme, ThemePreference.system);
    for (final d in data.files.vaultDirectories) {
      expect(_filesUnder(d), isEmpty, reason: d);
    }
    expect(_filesUnder(cache), isEmpty);

    // ── Import: password first, nothing changes until it's right ──
    final noPw = await archiver.importBackup(saved, sections: sections);
    expect(noPw.failureOrNull?.code, FailureCode.passwordProtected);
    final wrong = await archiver.importBackup(
      saved,
      password: 'nope',
      sections: sections,
    );
    expect(wrong.failureOrNull?.code, FailureCode.wrongPassword);
    expect(await data.documents.all(), isEmpty);
    expect(await auth.watchAccounts().first, isEmpty);

    final imported = await archiver.importBackup(
      saved,
      password: 'Moving-Phones-2026',
      sections: sections,
    );
    final summary = imported.valueOrNull!;
    expect(imported.failureOrNull, isNull);
    expect(summary.documents, 3);
    expect(summary.notes, 1);
    expect(summary.folders, 3);
    expect(summary.pinLockedFolders, 1);
    expect(summary.failedSections, isEmpty);
    expect(summary.sections['authenticator'], 2);

    final docs = await data.documents.all();
    expect(docs.map((d) => d.name).toSet(), {'Passport', 'Bank card', 'Loose'});
    final bank = docs.singleWhere((d) => d.name == 'Bank card');
    expect(
      utf8.decode(
        await data.files.read(data.files.absolute(bank.relativePath)),
      ),
      '%PDF-1.7 bank',
    );
    expect(bank.expiresAt, DateTime(2031, 5, 6));
    expect(docs.singleWhere((d) => d.name == 'Loose').thumbnailPath, isNotNull);
    final tree = FolderTree(await data.documents.allFolders());
    final private = tree.all.singleWhere((f) => f.name == 'Private');
    expect(private.lockMode, FolderLockMode.device);
    expect(tree.all.singleWhere((f) => f.name == 'Empty'), isNotNull);
    expect((await data.notes.all()).single.body, 'password: hunter2');

    final accounts = await auth.watchAccounts().first;
    expect(accounts.map((a) => a.title).toSet(), {'GitHub', 'counter'});
    final gh = accounts.singleWhere((a) => a.title == 'GitHub');
    expect(secrets.values[gh.secretKeyId], 'JBSWY3DPEHPK3PXP');
    final codes = (await auth.readRecoveryCodes(gh)).valueOrNull!;
    expect(codes.map((c) => (c.code, c.used)), [
      ('aaaa-1111', false),
      ('bbbb-2222', true),
    ]);
    final hotp = accounts.singleWhere((a) => a.title == 'counter');
    expect(hotp.type, OtpType.hotp);
    expect(hotp.counter, 7);
    expect(signatures.items, ['sig-png-base64']);
    expect(qr.items, ['https://example.com']);
    final settings = await data.settings.load();
    expect(settings.theme, ThemePreference.dark);
    expect(settings.appLock, isTrue);

    // Idempotent: the same backup again adds nothing.
    final again = await archiver.importBackup(
      saved,
      password: 'Moving-Phones-2026',
      sections: sections,
    );
    expect(again.valueOrNull!.documents, 0);
    expect(again.valueOrNull!.notes, 0);
    expect(again.valueOrNull!.sections['authenticator'], 0);
    expect(await data.documents.all(), hasLength(3));
    expect(await auth.watchAccounts().first, hasLength(2));
    // No plaintext work files are left behind.
    expect(_filesUnder(p.join(cache, 'tmp')), isEmpty);
  });

  test('unprotected export opens in any unzip tool', () async {
    await populate();
    final r = await archiver.exportBackup(sections: sections);
    final backup = r.valueOrNull!;
    expect(backup.protected, isFalse);
    final archive = ZipDecoder().decodeBytes(
      File(backup.path).readAsBytesSync(),
    );
    expect(archive.findFile('IDs & Proofs/Passport.pdf'), isNotNull);
    expect(archive.findFile('.idsnap/authenticator.json'), isNotNull);
    // The file is in the share cache, shredded on release.
    await data.files.releaseTemp(backup.path);
    expect(File(backup.path).existsSync(), isFalse);
  });

  test('accounts-only export carries no documents or notes', () async {
    await populate();
    final r = await archiver.exportBackup(
      password: 'Only-Accounts-1',
      sections: [AuthenticatorBackupSection(auth)],
      includeDocuments: false,
      fileName: 'IDSnap accounts.zip',
    );
    final backup = r.valueOrNull!;
    expect(backup.fileName, 'IDSnap accounts.zip');
    expect(backup.documents, 0);
    expect(backup.notes, 0);
    final names = ZipDecoder()
        .decodeBytes(
          File(backup.path).readAsBytesSync(),
          password: 'Only-Accounts-1',
        )
        .files
        .map((f) => f.name)
        .toSet();
    expect(names, {'manifest.json', '.idsnap/authenticator.json'});

    // Restores into another vault through the normal import.
    await auth.eraseAll();
    final back = await archiver.importBackup(
      backup.path,
      password: 'Only-Accounts-1',
      sections: sections,
    );
    expect(back.valueOrNull!.sections['authenticator'], 2);
  });

  test(
    'version-2 backups (notes and folders at the root) still import',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.directory('Work/'))
        ..addFile(ArchiveFile.bytes('Work/Plan.pdf', _pdf('plan')))
        ..addFile(
          ArchiveFile.string(
            'secure-notes.json',
            jsonEncode({
              'version': 1,
              'notes': [
                {
                  'id': 'n1',
                  'title': 'Old note',
                  'body': 'from v2',
                  'locked': true,
                  'createdAt': '2026-01-01T00:00:00.000',
                },
              ],
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'version': 2,
              'folders': [
                {'id': 'f1', 'name': 'Work', 'locked': true},
              ],
              'documents': [
                {'path': 'Work/Plan.pdf', 'name': 'Plan', 'folderId': 'f1'},
              ],
            }),
          ),
        );
      final zip = p.join(tmp.path, 'v2.zip');
      File(zip).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final r = await archiver.importBackup(zip, sections: sections);
      expect(r.valueOrNull!.manifestVersion, 2);
      expect(r.valueOrNull!.documents, 1);
      expect(r.valueOrNull!.notes, 1);
      final folder = (await data.documents.allFolders()).single;
      expect(folder.name, 'Work');
      expect(folder.lockMode, FolderLockMode.device);
      expect((await data.notes.all()).single.lockMode, FolderLockMode.device);
    },
  );

  test(
    'a backup from a newer app version is refused, nothing changes',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('x.pdf', _pdf('x')))
        ..addFile(ArchiveFile.string('manifest.json', '{"version": 99}'));
      final zip = p.join(tmp.path, 'v99.zip');
      File(zip).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final r = await archiver.importBackup(zip, sections: sections);
      expect(r.failureOrNull?.code, FailureCode.unsupportedFormat);
      expect(r.failureOrNull?.recovery, contains('newer version'));
      expect(await data.documents.all(), isEmpty);
    },
  );

  test('a damaged backup reports corrupt, not "storage"', () async {
    await populate();
    final r = await archiver.exportBackup(password: 'pw-damage');
    final bytes = File(r.valueOrNull!.path).readAsBytesSync();
    final cut = p.join(tmp.path, 'cut.zip');
    File(cut).writeAsBytesSync(bytes.sublist(0, bytes.length - 100));
    final imp = await archiver.importBackup(cut, password: 'pw-damage');
    expect(imp.failureOrNull?.code, FailureCode.corruptFile);
    final notZip = p.join(tmp.path, 'not.zip');
    File(notZip).writeAsStringSync('hello');
    expect(
      (await archiver.importBackup(notZip)).failureOrNull?.code,
      FailureCode.corruptFile,
    );
  });

  test('cancelling an export midway leaves no partial files', () async {
    await populate();
    for (var i = 0; i < 4; i++) {
      await _addDoc(data, 'Big $i', _pdf('x' * (3 << 20)));
    }
    final token = JobCancelToken();
    final r = await archiver.exportBackup(
      password: 'cancel-me',
      sections: sections,
      cancel: token,
      onProgress: (pr) {
        if (pr.stage == BackupStage.documents && pr.fraction > 0.2) {
          token.cancel();
        }
      },
    );
    expect(r.failureOrNull?.code, FailureCode.processingCancelled);
    expect(_filesUnder(p.join(cache, 'share')), isEmpty);
    expect(_filesUnder(p.join(cache, 'tmp')), isEmpty);
  });

  test('cancelling an import midway leaves no partial files', () async {
    for (var i = 0; i < 4; i++) {
      await _addDoc(data, 'Big $i', _pdf('y' * (3 << 20)));
    }
    final exported = await archiver.exportBackup();
    final saved = p.join(tmp.path, 'big.zip');
    File(exported.valueOrNull!.path).copySync(saved);
    await eraser.eraseEverything();

    final token = JobCancelToken();
    final r = await archiver.importBackup(
      saved,
      cancel: token,
      onProgress: (pr) {
        if (pr.stage == BackupStage.documents && pr.fraction > 0.3) {
          token.cancel();
        }
      },
    );
    expect(r.failureOrNull?.code, FailureCode.processingCancelled);
    expect(_filesUnder(p.join(cache, 'tmp')), isEmpty);
    // Whatever was imported is complete; the rest comes with a re-import.
    final again = await archiver.importBackup(saved);
    expect(await data.documents.all(), hasLength(4));
    expect(again.valueOrNull!.skipped, lessThan(4));
  });

  test('"Delete all documents" includes locked folders', () async {
    await populate();
    expect(
      await data.documents.watch(const DocumentQuery()).first,
      hasLength(2),
      reason: 'the locked one is hidden from listings',
    );
    final deleted = <String>[];
    final r = await eraser.deleteAllDocuments(
      onDeleted: (d) async => deleted.add(d.name),
    );
    expect(r.valueOrNull, 3);
    expect(deleted, hasLength(3));
    expect(await data.documents.all(), isEmpty);
    expect(_filesUnder(p.join(root, 'documents')), isEmpty);
    expect(_filesUnder(p.join(root, 'thumbs')), isEmpty);
    // Folders, notes and accounts are untouched by this action.
    expect(await data.documents.allFolders(), hasLength(3));
    expect(await data.notes.all(), hasLength(1));
    expect(await auth.watchAccounts().first, hasLength(2));
  });

  group('plaintext scratch (H-07)', () {
    test('importOriginal shreds app-cache sources only', () async {
      final appCache = p.join(tmp.path, 'appcache');
      final userFiles = p.join(tmp.path, 'Download');
      final files = LocalFileStore(
        p.join(tmp.path, 'v2'),
        cacheRoot: p.join(appCache, 'docscan'),
        cipher: data.fileCipher,
        scratch: PlaintextScratch.forAndroid(cache: appCache),
      );
      await files.ensureLayout();
      final scanned = File(p.join(appCache, 'DOCUMENT_SCAN_1_x.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 9]);
      final picked = File(p.join(appCache, 'picked', 'id1', 'id.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 8]);
      final user = File(p.join(userFiles, 'passport.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 7]);

      final a = await files.importOriginal(scanned.path);
      final b = await files.importOriginal(picked.path);
      final c = await files.importOriginal(user.path);
      expect(scanned.existsSync(), isFalse);
      expect(picked.existsSync(), isFalse);
      expect(user.existsSync(), isTrue, reason: 'never delete user files');
      for (final o in [a, b, c]) {
        expect(await files.read(o), hasLength(4));
      }
      // A vault file is never "discarded".
      expect(await files.discardImportedSource(a), isFalse);
      expect(File(a).existsSync(), isTrue);
    });

    test('Android sweep removes picker/scanner leftovers only', () async {
      final cacheDir = p.join(tmp.path, 'android', 'cache');
      final pictures = p.join(tmp.path, 'android', 'ext', 'Pictures');
      File mk(String path) => File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('plain');
      final victims = [
        mk(p.join(cacheDir, 'picked', 'a', 'x.pdf')),
        mk(p.join(cacheDir, 'file_picker', '123', 'y.pdf')),
        mk(p.join(cacheDir, '0d8c3a44-1f5e-4c3b-9a0e-3b1b2c3d4e5f', 'p.jpg')),
        mk(p.join(cacheDir, 'image_picker123.jpg')),
        mk(p.join(cacheDir, 'scaled_456.jpg')),
        mk(p.join(cacheDir, 'mlkit_docscan_ui_client', 'page.jpg')),
        mk(p.join(pictures, 'DOCUMENT_SCAN_1_2026.jpg')),
      ];
      final keep = [
        mk(p.join(cacheDir, 'docscan', 'view', 'open.pdf')),
        mk(p.join(cacheDir, 'other_plugin', 'cache.bin')),
        mk(p.join(pictures, 'holiday.jpg')),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final scratch = PlaintextScratch.forAndroid(
        cache: cacheDir,
        scannerPictures: pictures,
      );

      // After a scan: scanner output only.
      expect(await scratch.sweep(scannerOnly: true), 2);
      expect(victims[5].existsSync(), isFalse);
      expect(victims[6].existsSync(), isFalse);
      expect(victims[0].existsSync(), isTrue);

      expect(await scratch.sweep(), 5);
      for (final v in victims) {
        expect(v.existsSync(), isFalse, reason: v.path);
      }
      for (final k in keep) {
        expect(k.existsSync(), isTrue, reason: k.path);
      }
    });

    test('iOS sweep clears tmp and the scanner cache', () async {
      final caches = p.join(tmp.path, 'ios', 'Library', 'Caches');
      final tmpDir = p.join(tmp.path, 'ios', 'tmp');
      final a = File(p.join(tmpDir, 'image_picker_1.jpg'))
        ..createSync(recursive: true);
      final b = File(p.join(tmpDir, 'ABC', 'picked.pdf'))
        ..createSync(recursive: true);
      final c = File(p.join(caches, 'cunning_document_scanner', 's.png'))
        ..createSync(recursive: true);
      final keep = File(p.join(caches, 'docscan', 'tmp', 'w.pdf'))
        ..createSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final scratch = PlaintextScratch.forIos(caches: caches);
      expect(scratch.owns(a.path), isTrue);
      expect(await scratch.sweep(), 3);
      expect([a, b, c].any((f) => f.existsSync()), isFalse);
      expect(keep.existsSync(), isTrue);
    });

    test('clearing a scan draft sweeps scanner output', () async {
      final cacheDir = p.join(tmp.path, 'draftcache');
      final scan = File(p.join(cacheDir, 'DOCUMENT_SCAN_9_x.jpg'))
        ..createSync(recursive: true);
      final pick = File(p.join(cacheDir, 'picked', 'z', 'p.jpg'))
        ..createSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final scratch = PlaintextScratch.forAndroid(cache: cacheDir);
      final drafts = JsonDraftStore(
        p.join(tmp.path, 'drafts-root'),
        onCleared: () => scratch.sweep(scannerOnly: true),
      );
      await drafts.clear();
      expect(scan.existsSync(), isFalse);
      expect(pick.existsSync(), isTrue);
    });
  });
}
