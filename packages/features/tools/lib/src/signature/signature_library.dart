import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// [SignatureLibrary] stored as PNG files plus a small JSON index in
/// `<app documents>/signatures/` (deliberately outside the Drift database).
///
/// Writes go to a temp file and are renamed into place, so a crash never
/// leaves a half-written index. A missing or damaged index is rebuilt from
/// the PNG files that exist. Operations are serialised.
///
/// With a [cipher] (the app's vault cipher, ADR-0010) the PNGs and the index
/// are encrypted at rest; plaintext files from older versions still read.
class FileSignatureLibrary implements SignatureLibrary {
  FileSignatureLibrary(
    this.directory, {
    DateTime Function()? clock,
    String Function()? ids,
    this.cipher,
  }) : _clock = clock ?? DateTime.now,
       _ids = ids ?? newId;

  final FileCipher? cipher;

  Future<Uint8List> _readBytes(File file) async {
    final bytes = await file.readAsBytes();
    final c = cipher;
    return c != null && c.isEncrypted(bytes)
        ? await c.decryptBytes(bytes)
        : bytes;
  }

  Future<Uint8List> _seal(Uint8List bytes) async {
    final c = cipher;
    return c == null ? bytes : await c.encryptBytes(bytes);
  }

  /// Absolute path of the signatures folder.
  final String directory;
  final DateTime Function() _clock;
  final String Function() _ids;
  Future<void> _tail = Future.value();

  static const indexName = 'index.json';
  static const _version = 1;

  String _path(String name) => '$directory${Platform.pathSeparator}$name';

  /// Runs [body] after every earlier operation finished.
  Future<Result<T>> _serial<T>(Future<Result<T>> Function() body) {
    final done = Completer<Result<T>>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await body());
      } on FileSystemException catch (e, st) {
        done.complete(
          Err(
            AppFailure(
              FailureCode.insufficientStorage,
              cause: e,
              stackTrace: st,
              message:
                  "Your signatures couldn't be saved. Free up some space "
                  'and try again.',
            ),
          ),
        );
      } on Object catch (e, st) {
        done.complete(
          Err(
            AppFailure(
              FailureCode.unknown,
              cause: e,
              stackTrace: st,
              heading: 'Signature not saved',
              message:
                  'Your saved signatures were not changed. Try again, or '
                  'restart IDSnap.',
            ),
          ),
        );
      }
    });
    return done.future;
  }

  @override
  Future<Result<List<SavedSignature>>> list() =>
      _serial(() async => Ok(_sorted(await _readIndex())));

  @override
  Future<Result<SavedSignature>> add(
    Uint8List png, {
    required int width,
    required int height,
  }) => _serial(() async {
    if (!_isPng(png)) {
      return const Err(
        AppFailure(
          FailureCode.corruptFile,
          detail: 'Signature image',
          message: 'The signature image could not be read. Create it again.',
        ),
      );
    }
    final index = await _readIndex();
    if (index.items.length >= SignatureLibrary.capacity) {
      return const Err(
        AppFailure(
          FailureCode.targetSizeUnreachable,
          action: FailureAction.none,
          message:
              'You can keep up to ${SignatureLibrary.capacity} signatures. '
              'Delete one in My signature to save another.',
        ),
      );
    }
    await Directory(directory).create(recursive: true);
    final id = _ids();
    final fileName = '$id.png';
    await _writeAtomic(_path(fileName), await _seal(png));
    final sig = SavedSignature(
      id: id,
      fileName: fileName,
      createdAt: _clock(),
      width: width,
      height: height,
    );
    final next = _Index([...index.items, sig], index.defaultId ?? id);
    await _writeIndex(next);
    return Ok(sig.copyWith(isDefault: next.defaultId == id));
  });

  @override
  Future<Result<Uint8List>> load(String id) => _serial(() async {
    final index = await _readIndex();
    final sig = index.byId(id);
    if (sig == null) return const Err(AppFailure(FailureCode.notFound));
    final file = File(_path(sig.fileName));
    if (!file.existsSync()) return const Err(AppFailure(FailureCode.notFound));
    return Ok(await _readBytes(file));
  });

  @override
  Future<Result<void>> delete(String id) => _serial(() async {
    final index = await _readIndex();
    final sig = index.byId(id);
    if (sig == null) return const Err(AppFailure(FailureCode.notFound));
    final rest = [...index.items]..removeWhere((s) => s.id == id);
    var defaultId = index.defaultId;
    if (defaultId == id) {
      defaultId = rest.isEmpty ? null : _sorted(_Index(rest, null)).first.id;
    }
    await _writeIndex(_Index(rest, defaultId));
    final file = File(_path(sig.fileName));
    if (file.existsSync()) await file.delete();
    return const Ok(null);
  });

  @override
  Future<Result<void>> setDefault(String id) => _serial(() async {
    final index = await _readIndex();
    if (index.byId(id) == null) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    await _writeIndex(_Index(index.items, id));
    return const Ok(null);
  });

  // ── Storage ────────────────────────────────────────────────────────────

  List<SavedSignature> _sorted(_Index index) {
    final items = [
      for (final s in index.items)
        s.copyWith(isDefault: s.id == index.defaultId),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<_Index> _readIndex() async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const _Index([], null);
    final file = File(_path(indexName));
    _Index? parsed;
    if (file.existsSync()) {
      try {
        parsed = _Index.fromJson(
          jsonDecode(utf8.decode(await _readBytes(file)))
              as Map<String, Object?>,
        );
      } on Object {
        parsed = null; // Damaged: rebuilt below.
      }
    }
    if (parsed == null) return await _rebuild(dir);
    // Drop entries whose PNG is gone (e.g. cleared by the OS).
    final present = [
      for (final s in parsed.items)
        if (File(_path(s.fileName)).existsSync()) s,
    ];
    final defaultId = present.any((s) => s.id == parsed!.defaultId)
        ? parsed.defaultId
        : (present.isEmpty ? null : present.last.id);
    return _Index(present, defaultId);
  }

  /// Recovers the library from the PNG files when the index is lost.
  Future<_Index> _rebuild(Directory dir) async {
    final items = <SavedSignature>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.toLowerCase().endsWith('.png')) continue;
      final name = e.uri.pathSegments.last;
      final Uint8List bytes;
      try {
        bytes = await _readBytes(e);
      } on Object {
        continue;
      }
      if (!_isPng(bytes)) continue;
      final (w, h) = _pngSize(bytes);
      items.add(
        SavedSignature(
          id: name.substring(0, name.length - 4),
          fileName: name,
          createdAt: e.lastModifiedSync(),
          width: w,
          height: h,
        ),
      );
      if (items.length >= SignatureLibrary.capacity) break;
    }
    final index = _Index(items, items.isEmpty ? null : items.first.id);
    if (items.isNotEmpty) await _writeIndex(index);
    return index;
  }

  Future<void> _writeIndex(_Index index) async {
    await Directory(directory).create(recursive: true);
    await _writeAtomic(
      _path(indexName),
      await _seal(Uint8List.fromList(utf8.encode(jsonEncode(index.toJson())))),
    );
  }

  static Future<void> _writeAtomic(String path, Uint8List bytes) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  static bool _isPng(Uint8List b) =>
      b.length > 24 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  /// Width and height from the IHDR chunk.
  static (int, int) _pngSize(Uint8List b) {
    int be(int o) =>
        (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    return (be(16), be(20));
  }
}

class _Index {
  const _Index(this.items, this.defaultId);

  factory _Index.fromJson(Map<String, Object?> json) {
    final raw = json['items'];
    final items = <SavedSignature>[
      if (raw is List)
        for (final e in raw.whereType<Map<String, Object?>>())
          SavedSignature(
            id: e['id']! as String,
            fileName: e['file']! as String,
            createdAt: DateTime.parse(e['createdAt']! as String),
            width: (e['width'] as num?)?.toInt() ?? 0,
            height: (e['height'] as num?)?.toInt() ?? 0,
          ),
    ];
    return _Index(items, json['defaultId'] as String?);
  }

  final List<SavedSignature> items;
  final String? defaultId;

  SavedSignature? byId(String id) {
    for (final s in items) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'version': FileSignatureLibrary._version,
    'defaultId': defaultId,
    'items': [
      for (final s in items)
        {
          'id': s.id,
          'file': s.fileName,
          'createdAt': s.createdAt.toIso8601String(),
          'width': s.width,
          'height': s.height,
        },
    ],
  };
}
