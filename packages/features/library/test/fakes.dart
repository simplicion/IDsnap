import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

class FakeRepository implements DocumentRepository {
  FakeRepository(List<Document> docs) : _docs = [...docs];

  final List<Document> _docs;
  final List<Folder> _folders = [];
  final removed = <String>[];
  final _changes = StreamController<void>.broadcast();

  List<Document> _apply(DocumentQuery q) {
    final out = _docs.where((d) {
      if (q.search.isNotEmpty &&
          !d.name.toLowerCase().contains(q.search.toLowerCase())) {
        return false;
      }
      if (q.folderId != null && d.folderId != q.folderId) return false;
      return switch (q.filter) {
        DocumentFilter.all => true,
        DocumentFilter.pdf => d.format == DocumentFormat.pdf,
        DocumentFilter.images => d.format.isImage,
        DocumentFilter.text => d.format.isText,
        DocumentFilter.favorites => d.favorite,
      };
    }).toList();
    return out;
  }

  @override
  Stream<List<Document>> watch(DocumentQuery query) async* {
    yield _apply(query);
    await for (final _ in _changes.stream) {
      yield _apply(query);
    }
  }

  @override
  Future<Document?> byId(String id) async =>
      _docs.where((d) => d.id == id).firstOrNull;

  @override
  Future<Result<void>> add(Document document) async {
    _docs.add(document);
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> update(Document document) async {
    final i = _docs.indexWhere((d) => d.id == document.id);
    _docs[i] = document;
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> remove(String id) async {
    removed.add(id);
    _docs.removeWhere((d) => d.id == id);
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Stream<List<Folder>> watchFolders() => Stream.value(_folders);

  @override
  Future<Result<Folder>> addFolder(String name) async {
    final f = Folder(id: newId(), name: name, createdAt: DateTime(2026));
    _folders.add(f);
    return Ok(f);
  }

  @override
  Future<Result<void>> renameFolder(String id, String name) async =>
      const Ok(null);

  @override
  Future<Result<void>> removeFolder(String id) async => const Ok(null);
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
  Future<int> size(String absolutePath) async => 0;

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

Document doc(
  String id,
  String name,
  DocumentFormat format, {
  bool favorite = false,
}) => Document(
  id: id,
  name: name,
  format: format,
  relativePath: 'documents/$id.${format.extension}',
  sizeBytes: 2048,
  pageCount: format == DocumentFormat.pdf ? 2 : null,
  favorite: favorite,
  createdAt: DateTime(2026, 9),
  updatedAt: DateTime(2026, 9),
);

Widget harness(Widget child, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

List<Override> baseOverrides(FakeRepository repo, FakeFileStore files) => [
  documentRepositoryProvider.overrideWithValue(repo),
  fileStoreProvider.overrideWithValue(files),
];
