import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// [FileStore] in app-private storage:
/// `<root>/documents`, `originals`, `thumbs`, `tmp`.
/// File names are random UUIDs so no user text ends up in paths.
class LocalFileStore implements FileStore {
  LocalFileStore(this.root);

  final String root;

  String get _documents => p.join(root, 'documents');
  String get _originals => p.join(root, 'originals');
  String get _thumbs => p.join(root, 'thumbs');
  String get _tmp => p.join(root, 'tmp');

  /// Creates the directory layout. Call once before use.
  Future<void> ensureLayout() async {
    for (final d in [_documents, _originals, _thumbs, _tmp]) {
      await Directory(d).create(recursive: true);
    }
  }

  @override
  String absolute(String relativePath) =>
      p.isAbsolute(relativePath) ? relativePath : p.join(root, relativePath);

  @override
  Future<Uint8List> read(String absolutePath) =>
      File(absolute(absolutePath)).readAsBytes();

  @override
  Future<String> readText(String absolutePath) =>
      File(absolute(absolutePath)).readAsString();

  @override
  Future<bool> exists(String absolutePath) =>
      Future.value(File(absolute(absolutePath)).existsSync());

  @override
  Future<int> size(String absolutePath) =>
      File(absolute(absolutePath)).length();

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async {
    await Directory(_tmp).create(recursive: true);
    final path = p.join(_tmp, '${newId()}.${_ext(extension)}');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<String> importOriginal(String externalPath) async {
    await Directory(_originals).create(recursive: true);
    final ext = p.extension(externalPath).replaceFirst('.', '');
    final target = p.join(
      _originals,
      '${newId()}.${ext.isEmpty ? 'jpg' : ext.toLowerCase()}',
    );
    await File(externalPath).copy(target);
    return target;
  }

  @override
  Future<String> commit(String tempPath, String extension) async {
    await Directory(_documents).create(recursive: true);
    final name = '${newId()}.${_ext(extension)}';
    final target = p.join(_documents, name);
    await _move(File(tempPath), target);
    return p.join('documents', name);
  }

  @override
  Future<String> writeThumbnail(String documentId, Uint8List jpegBytes) async {
    await Directory(_thumbs).create(recursive: true);
    final name = '$documentId.jpg';
    final tmp = p.join(_thumbs, '$name.part');
    await File(tmp).writeAsBytes(jpegBytes, flush: true);
    await _move(File(tmp), p.join(_thumbs, name));
    return p.join('thumbs', name);
  }

  @override
  Future<String> exportCopy(String relativePath, String fileName) async {
    final dir = Directory(p.join(_tmp, 'export', newId()));
    await dir.create(recursive: true);
    final target = p.join(dir.path, safeFileName(fileName));
    await File(absolute(relativePath)).copy(target);
    return target;
  }

  @override
  Future<void> delete(String absoluteOrRelativePath) async {
    final path = absolute(absoluteOrRelativePath);
    // Never delete outside the store root.
    if (!p.isWithin(root, path)) return;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return;
    await (type == FileSystemEntityType.directory
            ? Directory(path)
            : File(path) as FileSystemEntity)
        .delete(recursive: true);
  }

  @override
  Future<void> clearTemp() async {
    final dir = Directory(_tmp);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }

  @override
  Future<StorageUsage> usage() async => StorageUsage(
    documents: await _dirSize(_documents) + await _dirSize(_thumbs),
    originals: await _dirSize(_originals),
    temp: await _dirSize(_tmp),
  );

  static Future<int> _dirSize(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Rename, falling back to copy+delete across volumes.
  static Future<void> _move(File source, String target) async {
    try {
      await source.rename(target);
    } on FileSystemException {
      await source.copy(target);
      await source.delete();
    }
  }

  static String _ext(String e) => e.replaceFirst('.', '').toLowerCase();
}

/// Strips characters that are invalid in file names on Android/iOS/Windows.
String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'document' : cleaned;
}
