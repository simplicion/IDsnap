import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/vault/plaintext_scratch.dart';
import 'package:docscan_data/src/vault/shred.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// [FileStore] in app-private storage:
/// `<root>/documents`, `originals`, `thumbs` (the vault) and, under
/// [cacheRoot], `tmp` (work in progress), `view` (decrypted copies for
/// path-based APIs) and `share` (decrypted copies handed to other apps).
/// File names are random UUIDs so no user text ends up in paths.
///
/// With a [cipher] (ADR-0010) every vault file is encrypted: [commit],
/// [importOriginal] and [writeThumbnail] encrypt on the way in, [read],
/// [readText] and [size] decrypt transparently, and [decryptToTemp] /
/// [exportCopy] make short-lived plaintext copies in the cache that are
/// shredded by [releaseTemp] and at the next launch ([clearTemp]).
///
/// [scratch] lists the app-owned places where pickers and the document
/// scanner leave plaintext sources (audit H-07): [importOriginal] shreds a
/// source that lives there once it is encrypted, and [clearTemp] sweeps
/// them. Files elsewhere (e.g. picked straight from Downloads) are never
/// deleted.
class LocalFileStore implements FileStore, PlainFileAccess {
  LocalFileStore(
    this.root, {
    String? cacheRoot,
    FileCipher? cipher,
    this.scratch = PlaintextScratch.none,
  }) : cacheRoot = cacheRoot ?? root,
       _cipher = cipher;

  /// Picker / scanner scratch space outside the vault.
  final PlaintextScratch scratch;

  final String root;

  /// App cache (never backed up, never shared storage).
  final String cacheRoot;
  final FileCipher? _cipher;

  /// True when vault files are encrypted.
  bool get encrypts => _cipher != null;

  /// Files at most this big are decrypted on the calling isolate.
  static const _inlineLimit = 1024 * 1024;

  String get _documents => p.join(root, 'documents');
  String get _originals => p.join(root, 'originals');
  String get _thumbs => p.join(root, 'thumbs');
  String get _tmp => p.join(cacheRoot, 'tmp');
  String get _view => p.join(cacheRoot, 'view');
  String get _share => p.join(cacheRoot, 'share');

  /// Directories holding vault files (for migration and erase).
  List<String> get vaultDirectories => [
    _documents,
    _originals,
    _thumbs,
    p.join(root, 'signatures'),
  ];

  /// Scratch space for the migrator's verification copies.
  String get scratchDirectory => p.join(_tmp, 'verify');

  /// Creates the directory layout. Call once before use.
  Future<void> ensureLayout() async {
    for (final d in [_documents, _originals, _thumbs, _tmp]) {
      await Directory(d).create(recursive: true);
    }
  }

  @override
  String absolute(String relativePath) =>
      p.isAbsolute(relativePath) ? relativePath : p.join(root, relativePath);

  Future<bool> _isEncrypted(String path) async {
    final c = _cipher;
    if (c == null) return false;
    final raf = await File(path).open();
    try {
      return c.isEncrypted(await raf.read(c.headerLength));
    } finally {
      await raf.close();
    }
  }

  @override
  Future<Uint8List> read(String absolutePath) async {
    final path = absolute(absolutePath);
    final c = _cipher;
    if (c == null || !await _isEncrypted(path)) {
      return await File(path).readAsBytes();
    }
    final file = File(path);
    if (await file.length() <= _inlineLimit) {
      return await c.decryptBytes(await file.readAsBytes());
    }
    return await c.decryptFileToBytes(path);
  }

  @override
  Future<String> readText(String absolutePath) async =>
      utf8.decode(await read(absolutePath));

  @override
  Future<bool> exists(String absolutePath) =>
      Future.value(File(absolute(absolutePath)).existsSync());

  @override
  Future<int> size(String absolutePath) async {
    final path = absolute(absolutePath);
    final length = await File(path).length();
    final c = _cipher;
    return c != null && await _isEncrypted(path)
        ? c.plaintextLength(length)
        : length;
  }

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
    final c = _cipher;
    if (c == null) {
      await File(externalPath).copy(target);
    } else {
      await c.encryptFile(externalPath, target);
    }
    await discardImportedSource(externalPath);
    return target;
  }

  /// Shreds [path] when it is a plaintext source in app-owned scratch space
  /// (scanner output, picker copies) — never a vault file and never a file
  /// outside the app's own cache/app-specific folders. Returns true when
  /// it was removed. Call after the source has been safely imported.
  Future<bool> discardImportedSource(String path) async {
    final work =
        p.isWithin(_tmp, path) || p.isWithin(_view, path) || _isShare(path);
    if (!work && !scratch.owns(path)) return false;
    // Never a vault file, whatever the scratch roots say.
    for (final d in vaultDirectories) {
      if (p.isWithin(d, path)) return false;
    }
    if (!File(path).existsSync()) return false;
    await shredFile(path);
    return true;
  }

  /// Sweeps picker/scanner leftovers ([scannerOnly]: scanner output only).
  Future<int> sweepScratch({bool scannerOnly = false}) =>
      scratch.sweep(scannerOnly: scannerOnly);

  /// A fresh private directory for an export (`share/<id>/`): released
  /// with [releaseTemp], swept after [plainCopyMaxAge] and at launch.
  Future<String> newExportDirectory() async {
    final dir = Directory(p.join(_share, newId()));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// A new path in the work directory (`tmp/`), shredded at launch.
  Future<String> newWorkPath(String extension) async {
    await Directory(_tmp).create(recursive: true);
    return p.join(_tmp, '${newId()}.${_ext(extension)}');
  }

  /// A plaintext path for [relativePath]: the file itself when it isn't
  /// encrypted (`isCopy` false), otherwise a decrypted copy in `tmp/` that
  /// the caller shreds with [delete].
  Future<({String path, bool isCopy})> plainPathForRead(
    String relativePath,
  ) async {
    final source = absolute(relativePath);
    if (!await _isEncrypted(source)) return (path: source, isCopy: false);
    final target = await newWorkPath(p.extension(source));
    await _cipher!.decryptFile(source, target);
    return (path: target, isCopy: true);
  }

  @override
  Future<String> commit(String tempPath, String extension) async {
    await Directory(_documents).create(recursive: true);
    final name = '${newId()}.${_ext(extension)}';
    final target = p.join(_documents, name);
    final c = _cipher;
    if (c == null) {
      await _move(File(tempPath), target);
    } else {
      await c.encryptFile(tempPath, target);
      await shredFile(tempPath);
    }
    return p.join('documents', name);
  }

  @override
  Future<String> writeThumbnail(String documentId, Uint8List jpegBytes) async {
    await Directory(_thumbs).create(recursive: true);
    final name = '$documentId.jpg';
    final tmp = p.join(_thumbs, '$name.part');
    final c = _cipher;
    await File(tmp).writeAsBytes(
      c == null ? jpegBytes : await c.encryptBytes(jpegBytes),
      flush: true,
    );
    await _move(File(tmp), p.join(_thumbs, name));
    return p.join('thumbs', name);
  }

  @override
  Future<String> exportCopy(String relativePath, String fileName) async {
    final dir = Directory(p.join(_share, newId()));
    await dir.create(recursive: true);
    final target = p.join(dir.path, safeFileName(fileName));
    final source = absolute(relativePath);
    if (await _isEncrypted(source)) {
      await _cipher!.decryptFile(source, target);
    } else {
      await File(source).copy(target);
    }
    return target;
  }

  /// How long a decrypted copy may outlive its use when nobody releases it
  /// (tool inputs): later [decryptToTemp] calls shred older copies.
  static const plainCopyMaxAge = Duration(minutes: 30);

  @override
  Future<String> decryptToTemp(String path, {String? fileName}) async {
    final source = absolute(path);
    if (!await _isEncrypted(source)) return source;
    unawaited(sweepPlainCopies());
    final dir = Directory(p.join(_view, newId()));
    await dir.create(recursive: true);
    final target = p.join(
      dir.path,
      fileName == null ? p.basename(source) : safeFileName(fileName),
    );
    await _cipher!.decryptFile(source, target);
    return target;
  }

  /// Shreds decrypted copies (view and share) older than [maxAge].
  Future<void> sweepPlainCopies({Duration maxAge = plainCopyMaxAge}) async {
    final cutoff = DateTime.now().subtract(maxAge);
    for (final d in [_view, _share]) {
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && e.lastModifiedSync().isBefore(cutoff)) {
            await releaseTemp(e.path);
          }
        }
      } on FileSystemException {
        // Raced with another sweep or release; the next one catches up.
      }
    }
  }

  bool _isShare(String path) => p.isWithin(_share, path);

  bool _isPlainCopy(String path) =>
      p.isWithin(_view, path) || p.isWithin(_share, path);

  @override
  Future<void> releaseTemp(
    String path, {
    Duration grace = Duration.zero,
  }) async {
    if (!_isPlainCopy(path)) return;
    Future<void> shred() async {
      await shredFile(path);
      final parent = Directory(p.dirname(path));
      if (parent.path != _view &&
          parent.path != _share &&
          parent.existsSync() &&
          parent.listSync().isEmpty) {
        await parent.delete();
      }
    }

    if (grace == Duration.zero) return await shred();
    // The receiving app may still be reading the file after the share
    // sheet returns; the next launch shreds it if the app is killed first.
    Timer(grace, () => unawaited(shred()));
  }

  @override
  Future<void> delete(String absoluteOrRelativePath) async {
    final path = absolute(absoluteOrRelativePath);
    // Never delete outside the store root or its cache.
    if (!p.isWithin(root, path) && !p.isWithin(cacheRoot, path)) return;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (_isPlainCopy(path) || p.isWithin(_tmp, path)) {
      await shredFile(path);
    } else {
      await File(path).delete();
    }
  }

  /// Shreds everything in `tmp/`, `view/` and `share/`, and the picker and
  /// scanner leftovers in [scratch].
  @override
  Future<void> clearTemp() async {
    await clearVaultTemp();
    await sweepScratch();
  }

  /// Shreds everything in `tmp/`, `view/` and `share/`.
  Future<void> clearVaultTemp() async {
    for (final d in [_tmp, _view, _share]) {
      await shredDirectory(d);
    }
    await Directory(_tmp).create(recursive: true);
  }

  @override
  Future<StorageUsage> usage() async => StorageUsage(
    documents: await _dirSize(_documents) + await _dirSize(_thumbs),
    originals: await _dirSize(_originals),
    temp: await _dirSize(_tmp) + await _dirSize(_view) + await _dirSize(_share),
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
