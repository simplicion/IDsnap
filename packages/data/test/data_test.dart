import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Document _doc(
  String name, {
  DocumentFormat format = DocumentFormat.pdf,
  int size = 100,
  int ageMinutes = 0,
  bool favorite = false,
  String? folderId,
}) {
  final t = DateTime(2026).add(Duration(minutes: -ageMinutes));
  return Document(
    id: newId(),
    name: name,
    format: format,
    relativePath: 'documents/$name',
    sizeBytes: size,
    favorite: favorite,
    folderId: folderId,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  late Directory tmp;
  late DataLayer data;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('docscan_data');
    data = await openDataLayer(
      rootOverride: tmp.path,
      executor: NativeDatabase.memory(),
    );
  });

  tearDown(() async {
    await data.close();
    await tmp.delete(recursive: true);
  });

  group('DriftDocumentRepository', () {
    Future<List<Document>> q(DocumentQuery query) =>
        data.documents.watch(query).first;

    test('CRUD', () async {
      final d = _doc('Invoice');
      expect((await data.documents.add(d)).isOk, isTrue);
      expect((await data.documents.byId(d.id))?.name, 'Invoice');
      await data.documents.update(
        d.copyWith(name: 'Invoice 2', favorite: true),
      );
      final u = await data.documents.byId(d.id);
      expect(u?.name, 'Invoice 2');
      expect(u?.favorite, isTrue);
      await data.documents.remove(d.id);
      expect(await data.documents.byId(d.id), isNull);
      expect(
        (await data.documents.update(d)).failureOrNull?.code,
        FailureCode.notFound,
      );
    });

    test('search, filter, sort, limit', () async {
      await data.documents.add(
        _doc('Bank statement', size: 300, ageMinutes: 5),
      );
      await data.documents.add(
        _doc(
          'receipt 50%',
          format: DocumentFormat.jpeg,
          size: 10,
          favorite: true,
        ),
      );
      await data.documents.add(
        _doc('Notes', format: DocumentFormat.txt, size: 50, ageMinutes: 10),
      );

      expect(
        (await q(const DocumentQuery(search: 'bank'))).single.name,
        'Bank statement',
      );
      expect(
        (await q(const DocumentQuery(search: '50%'))).single.name,
        'receipt 50%',
      );
      expect((await q(const DocumentQuery(search: '%'))).length, 1);
      expect(
        (await q(const DocumentQuery(filter: DocumentFilter.images))).length,
        1,
      );
      expect(
        (await q(const DocumentQuery(filter: DocumentFilter.text))).single.name,
        'Notes',
      );
      expect(
        (await q(const DocumentQuery(filter: DocumentFilter.favorites))).length,
        1,
      );
      expect(
        (await q(const DocumentQuery(filter: DocumentFilter.pdf))).length,
        1,
      );

      expect((await q(const DocumentQuery())).first.name, 'receipt 50%');
      expect(
        (await q(const DocumentQuery(sort: DocumentSort.oldest))).first.name,
        'Notes',
      );
      expect(
        (await q(const DocumentQuery(sort: DocumentSort.nameAz))).first.name,
        'Bank statement',
      );
      expect(
        (await q(
          const DocumentQuery(sort: DocumentSort.largest),
        )).first.sizeBytes,
        300,
      );
      expect((await q(const DocumentQuery(limit: 2))).length, 2);
    });

    test('folders: add, rename, filter, remove moves docs to root', () async {
      final folder = (await data.documents.addFolder(' Taxes ')).valueOrNull!;
      expect(folder.name, 'Taxes');
      final d = _doc('W2', folderId: folder.id);
      await data.documents.add(d);
      await data.documents.add(_doc('Other'));
      expect((await q(DocumentQuery(folderId: folder.id))).single.id, d.id);

      await data.documents.renameFolder(folder.id, '2026 Taxes');
      expect(
        (await data.documents.watchFolders().first).single.name,
        '2026 Taxes',
      );

      await data.documents.removeFolder(folder.id);
      expect(await data.documents.watchFolders().first, isEmpty);
      expect((await data.documents.byId(d.id))?.folderId, isNull);
    });
  });

  group('LocalFileStore', () {
    test('writeTemp → commit → exportCopy → delete', () async {
      final files = data.files;
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final temp = await files.writeTemp(bytes, '.PDF');
      expect(temp, endsWith('.pdf'));
      final rel = await files.commit(temp, 'pdf');
      expect(rel, startsWith('documents'));
      expect(File(temp).existsSync(), isFalse);
      expect(await files.read(files.absolute(rel)), bytes);
      expect(await files.size(rel), 4);

      final exported = await files.exportCopy(rel, 'My: scan?.pdf');
      expect(p.basename(exported), 'My_ scan_.pdf');
      expect(File(exported).readAsBytesSync(), bytes);

      await files.delete(rel);
      expect(await files.exists(rel), isFalse);
    });

    test('delete refuses paths outside root', () async {
      final outside = File(
        p.join(Directory.systemTemp.path, 'keep_${newId()}.txt'),
      )..writeAsStringSync('x');
      addTearDown(outside.deleteSync);
      await data.files.delete(outside.path);
      expect(outside.existsSync(), isTrue);
    });

    test('importOriginal, thumbnail, usage and clearTemp', () async {
      final files = data.files;
      final ext = File(p.join(tmp.path, 'external.JPG'))
        ..writeAsBytesSync(List.filled(10, 1));
      final original = await files.importOriginal(ext.path);
      expect(p.isWithin(p.join(tmp.path, 'originals'), original), isTrue);
      expect(original, endsWith('.jpg'));

      final thumb = await files.writeThumbnail('abc', Uint8List(5));
      expect(thumb, p.join('thumbs', 'abc.jpg'));

      await files.writeTemp(Uint8List(7), 'bin');
      final usage = await files.usage();
      expect(usage.originals, 10);
      expect(usage.documents, 5);
      expect(usage.temp, 7);
      expect(usage.total, 22);

      await files.clearTemp();
      expect((await files.usage()).temp, 0);
    });
  });

  group('JSON stores', () {
    test('draft round-trip and clear deletes owned images only', () async {
      final owned = File(p.join(tmp.path, 'originals', 'a.jpg'))
        ..createSync(recursive: true);
      final external = File(
        p.join(Directory.systemTemp.path, 'ext_${newId()}.jpg'),
      )..writeAsStringSync('x');
      addTearDown(external.deleteSync);

      final draft = ScanDraft(
        id: 'd1',
        createdAt: DateTime(2026, 9),
        pages: [
          ScanPage(
            id: 'p1',
            originalPath: owned.path,
            edits: const PageEdits(
              quad: Quad.full,
              quarterTurns: 1,
              filter: EnhancementFilter.blackWhite,
            ),
          ),
          ScanPage(id: 'p2', originalPath: external.path),
        ],
      );
      await data.drafts.save(draft);
      final loaded = (await data.drafts.load())!;
      expect(loaded.pages.first.edits, draft.pages.first.edits);
      expect(loaded.pages.length, 2);

      await data.drafts.clear();
      expect(await data.drafts.load(), isNull);
      expect(owned.existsSync(), isFalse);
      expect(external.existsSync(), isTrue);
    });

    test('corrupt draft is discarded', () async {
      File(p.join(tmp.path, 'drafts', 'current.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      expect(await data.drafts.load(), isNull);
    });

    test('settings round-trip with defaults', () async {
      expect((await data.settings.load()).theme, ThemePreference.system);
      await data.settings.save(
        const AppSettings(
          theme: ThemePreference.dark,
          ocrScript: OcrScript.devanagari,
        ),
      );
      final s = await data.settings.load();
      expect(s.theme, ThemePreference.dark);
      expect(s.ocrScript, OcrScript.devanagari);
    });
  });
}
