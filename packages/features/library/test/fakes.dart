import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class FakeRepository implements DocumentRepository, FolderRepository {
  FakeRepository(List<Document> docs, {List<Folder> folders = const []})
    : _docs = [...docs],
      _folders = {for (final f in folders) f.id: f};

  final List<Document> _docs;
  final Map<String, Folder> _folders;
  final removed = <String>[];
  final _changes = StreamController<void>.broadcast();

  List<Document> get documents => List.unmodifiable(_docs);
  List<Folder> get folders => _folders.values.toList();
  FolderTree get tree => FolderTree(_folders.values);

  void _changed() => _changes.add(null);

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  bool _matches(Document d, DocumentFilter filter) => switch (filter) {
    DocumentFilter.all => true,
    DocumentFilter.pdf => d.format == DocumentFormat.pdf,
    DocumentFilter.images => d.format.isImage,
    DocumentFilter.text => d.format.isText,
    DocumentFilter.favorites => d.favorite,
  };

  bool _nameMatches(Document d, String search) =>
      search.isEmpty || d.name.toLowerCase().contains(search.toLowerCase());

  List<Document> _apply(DocumentQuery q) {
    final hidden = tree.hiddenContentIds(const {});
    return _docs.where((d) {
      if (!_nameMatches(d, q.search)) return false;
      if (q.folderId != null && d.folderId != q.folderId) return false;
      if (q.folderId == null && hidden.contains(d.folderId)) return false;
      if (q.category != null && d.category != q.category) return false;
      return _matches(d, q.filter);
    }).toList();
  }

  @override
  Stream<List<Document>> watch(DocumentQuery query) =>
      _live(() => _apply(query));

  @override
  Future<Document?> byId(String id) async =>
      _docs.where((d) => d.id == id).firstOrNull;

  @override
  Future<Result<void>> add(Document document) async {
    _docs.add(document);
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> update(Document document) async {
    final i = _docs.indexWhere((d) => d.id == document.id);
    _docs[i] = document;
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> remove(String id) async {
    removed.add(id);
    _docs.removeWhere((d) => d.id == id);
    _changed();
    return const Ok(null);
  }

  @override
  Stream<List<Folder>> watchFolders() => _live(() => folders);

  @override
  Future<Result<Folder>> addFolder(String name) => createFolder(name: name);

  @override
  Future<Result<void>> removeFolder(String id) async => (await deleteFolder(
    id,
    FolderDeleteMode.moveContentsToParent,
  )).map<void>((_) {});

  // ── FolderRepository ────────────────────────────────────────────────────

  @override
  Stream<List<Folder>> watchAllFolders() => _live(() => folders);

  @override
  Future<List<Folder>> allFolders() async => folders;

  @override
  Future<Result<Folder>> createFolder({
    required String name,
    String? parentId,
    String? templateKey,
    String? icon,
    String? color,
  }) async {
    final error = FolderNames.validate(
      name,
      tree.children(parentId).map((f) => f.name),
    );
    if (error != null) {
      return Err(AppFailure(FailureCode.unknown, message: error));
    }
    final f = Folder(
      id: newId(),
      name: FolderNames.clean(name),
      createdAt: DateTime(2026),
      parentId: parentId,
      templateKey: templateKey,
      icon: icon,
      color: color,
    );
    _folders[f.id] = f;
    _changed();
    return Ok(f);
  }

  @override
  Future<Result<void>> renameFolder(String id, String name) async {
    final f = _folders[id]!;
    _folders[id] = f.copyWith(name: FolderNames.clean(name));
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> setFolderStyle(
    String id, {
    required String? icon,
    required String? color,
  }) async {
    _folders[id] = _folders[id]!.copyWith(icon: icon, color: color);
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> setFolderLockMode(String id, FolderLockMode mode) async {
    _folders[id] = _folders[id]!.copyWith(lockMode: mode);
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> moveFolder(String id, String? newParentId) async {
    if (newParentId != null && tree.isWithin(newParentId, id)) {
      return const Err(AppFailure(FailureCode.unknown, message: 'cycle'));
    }
    _folders[id] = _folders[id]!.copyWith(
      parentId: newParentId,
      clearParent: newParentId == null,
    );
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<List<Document>>> deleteFolder(
    String id,
    FolderDeleteMode mode,
  ) async {
    final t = tree;
    final parent = t[id]?.parentId;
    final out = <Document>[];
    if (mode == FolderDeleteMode.deleteContents) {
      final sub = t.subtreeIds(id);
      out.addAll(_docs.where((d) => sub.contains(d.folderId)));
      _docs.removeWhere((d) => sub.contains(d.folderId));
      sub.forEach(_folders.remove);
    } else {
      for (final (i, d) in _docs.indexed.toList()) {
        if (d.folderId == id) {
          _docs[i] = d.copyWith(folderId: parent, clearFolder: parent == null);
        }
      }
      for (final c in t.children(id)) {
        _folders[c.id] = c.copyWith(
          parentId: parent,
          clearParent: parent == null,
        );
      }
      _folders.remove(id);
    }
    _changed();
    return Ok(out);
  }

  @override
  Stream<FolderContents> watchContents(
    String? folderId, {
    DocumentSort sort = DocumentSort.newest,
    DocumentFilter filter = DocumentFilter.all,
  }) => _live(() {
    final t = tree;
    return FolderContents(
      folders: t.children(folderId),
      documents: [
        for (final d in _docs)
          if ((folderId == null
                  ? !t.contains(d.folderId)
                  : d.folderId == folderId) &&
              _matches(d, filter))
            d,
      ],
    );
  });

  @override
  Stream<Map<String?, int>> watchDirectCounts() => _live(() {
    final t = tree;
    final out = <String?, int>{};
    for (final d in _docs) {
      final key = t.contains(d.folderId) ? d.folderId : null;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  });

  @override
  Future<List<Folder>> breadcrumb(String folderId) async =>
      tree.pathTo(folderId);

  @override
  Stream<List<Document>> watchSearch(FolderSearch query) => _live(() {
    final t = tree;
    final hidden = t.hiddenContentIds(query.unlockedFolderIds);
    final within = query.withinFolderId;
    final scope = within == null ? null : t.subtreeIds(within);
    return [
      for (final d in _docs)
        if (_nameMatches(d, query.text) &&
            _matches(d, query.filter) &&
            !hidden.contains(d.folderId) &&
            (scope == null || scope.contains(d.folderId)))
          d,
    ];
  });

  @override
  Future<Result<void>> moveDocuments(
    List<String> documentIds,
    String? folderId,
  ) async {
    for (final (i, d) in _docs.indexed.toList()) {
      if (documentIds.contains(d.id)) {
        _docs[i] = d.copyWith(
          folderId: folderId,
          clearFolder: folderId == null,
        );
      }
    }
    _changed();
    return const Ok(null);
  }
}

class FakeFileStore implements FileStore {
  FakeFileStore({this.texts = const {}});

  final Map<String, String> texts;
  final deleted = <String>[];

  @override
  String absolute(String relativePath) => '/abs/$relativePath';

  @override
  Future<String> readText(String absolutePath) async =>
      texts[absolutePath] ?? '';

  @override
  Future<Uint8List> read(String absolutePath) async =>
      Uint8List.fromList(utf8.encode(texts[absolutePath] ?? ''));

  @override
  Future<void> delete(String absoluteOrRelativePath) async =>
      deleted.add(absoluteOrRelativePath);

  @override
  Future<bool> exists(String absolutePath) async => true;

  @override
  Future<int> size(String absolutePath) async =>
      utf8.encode(texts[absolutePath] ?? '').length;

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async =>
      '/tmp/x.$extension';

  @override
  Future<String> importOriginal(String externalPath) async => externalPath;

  @override
  Future<String> commit(String tempPath, String extension) async =>
      'documents/x.$extension';

  @override
  Future<String> writeThumbnail(String documentId, Uint8List jpegBytes) async =>
      'thumbs/$documentId.jpg';

  @override
  Future<String> exportCopy(String relativePath, String fileName) async =>
      '/tmp/$fileName';

  @override
  Future<void> clearTemp() async {}

  @override
  Future<StorageUsage> usage() async =>
      const StorageUsage(documents: 0, originals: 0, temp: 0);
}

class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.settings = const AppSettings()]);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings s) async => settings = s;
}

class FakeReminders implements ReminderScheduler {
  final scheduled = <String>[];
  final cancelled = <String>[];

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<void>> requestPermission() async => const Ok(null);

  @override
  Future<Result<void>> scheduleExpiry(Document document) async {
    scheduled.add(document.id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancel(String documentId) async {
    cancelled.add(documentId);
    return const Ok(null);
  }
}

Document doc(
  String id,
  String name,
  DocumentFormat format, {
  bool favorite = false,
  String? folderId,
  DocumentCategory? category,
  String? slot,
  DateTime? expiresAt,
}) => Document(
  id: id,
  name: name,
  format: format,
  relativePath: 'documents/$id.${format.extension}',
  sizeBytes: 2048,
  pageCount: format == DocumentFormat.pdf ? 2 : null,
  favorite: favorite,
  folderId: folderId,
  category: category,
  slot: slot,
  expiresAt: expiresAt,
  createdAt: DateTime(2026, 9),
  updatedAt: DateTime(2026, 9),
);

Folder folder(
  String id,
  String name, {
  String? parentId,
  FolderLockMode lockMode = FolderLockMode.none,
  String? templateKey,
}) => Folder(
  id: id,
  name: name,
  parentId: parentId,
  lockMode: lockMode,
  templateKey: templateKey,
  createdAt: DateTime(2026),
);

class MemorySecrets implements SecretStore {
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

/// The real PIN store on in-memory "keystore", with cheap hashing.
KeystoreFolderPinStore testPinStore([MemorySecrets? secrets]) =>
    KeystoreFolderPinStore(
      secrets ?? MemorySecrets(),
      iterations: 10,
      runInIsolate: false,
    );

class FakeAppLock implements AppLock {
  FakeAppLock({this.result = true});

  bool result;
  int prompts = 0;

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async {
    prompts++;
    return Ok(result);
  }
}

class FakeMediaPicker implements MediaPicker {
  FakeMediaPicker(this.files);

  final List<PickedFile> files;
  Set<DocumentFormat>? requested;
  bool? multiple;

  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      Ok(files);

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async {
    requested = formats;
    this.multiple = multiple;
    return Ok(files);
  }
}

class _MockPdf extends Mock implements PdfEngine {}

class _MockImages extends Mock implements ImageProcessor {}

/// Records commits instead of validating real files; adds a document.
class FakeCommit extends CommitOutput {
  FakeCommit(FakeRepository repo)
    : _repo = repo,
      super(
        files: FakeFileStore(),
        repository: repo,
        pdf: _MockPdf(),
        images: _MockImages(),
      );

  final FakeRepository _repo;
  final commits = <({String name, DocumentFormat format, String? folderId})>[];

  @override
  Future<Result<Document>> call(OutputFile output, {String? folderId}) async {
    commits.add((
      name: output.suggestedName,
      format: output.format,
      folderId: folderId,
    ));
    final d = Document(
      id: newId(),
      name: output.suggestedName,
      format: output.format,
      relativePath: 'documents/${output.suggestedName}',
      sizeBytes: output.bytes.length,
      folderId: folderId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await _repo.add(d);
    return Ok(d);
  }
}

/// A router with the library's real routes, for navigation tests.
Widget routedHarness({
  required List<Override> overrides,
  String initialLocation = '/files',
}) {
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/files',
        builder: (_, _) => const FilesScreen(),
        routes: libraryRoutes(rootKey),
      ),
      GoRoute(
        path: '/scan',
        builder: (_, state) =>
            Scaffold(body: Text('scan ${state.uri.queryParameters['folder']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

/// Phone-sized but tall viewport so the vault landing and list both fit.
void useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget harness(Widget child, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

List<Override> baseOverrides(
  FakeRepository repo,
  FakeFileStore files, {
  FolderPinStore? pins,
  AppLock? appLock,
}) => [
  documentRepositoryProvider.overrideWithValue(repo),
  fileStoreProvider.overrideWithValue(files),
  settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
  folderPinStoreProvider.overrideWithValue(pins ?? testPinStore()),
  appLockProvider.overrideWithValue(appLock ?? FakeAppLock()),
  folderSecureSetterProvider.overrideWithValue(_recordSecure),
];

Future<void> _recordSecure({required bool enabled}) async =>
    secureCalls.add(enabled);

/// FLAG_SECURE toggles requested by the library in the current test.
final secureCalls = <bool>[];
