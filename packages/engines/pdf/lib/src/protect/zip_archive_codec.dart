import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/protect/zip_stream.dart';

/// [ArchiveCodec] on the streaming ZIP core (plain or AES-256 AE-2). Each
/// writer or reader owns one background isolate; file contents move through
/// it in 1 MiB chunks, so memory stays flat whatever the archive size, and
/// [ArchiveWriter.abort] / a [JobCancelToken] stop within one chunk.
class ZipArchiveCodec implements ArchiveCodec {
  const ZipArchiveCodec();

  @override
  Future<ArchiveWriter> createWriter(
    String outputPath, {
    String? password,
  }) async {
    if (password != null) {
      try {
        zipPasswordBytes(password);
      } on ZipPasswordException catch (e) {
        throw ArchiveException(ArchiveErrorKind.unsupported, e.message);
      }
    }
    final worker = await _Worker.spawn(_writerMain, [outputPath, password]);
    return _IsolateWriter(worker, outputPath);
  }

  @override
  Future<ArchiveReader> openReader(String path) async {
    final worker = await _Worker.spawn(_readerMain, [path]);
    final raw = worker.initial! as List<Object?>;
    final entries = [
      for (final e in raw)
        if (e case [
          final String name,
          final int size,
          final int comp,
          final bool encrypted,
        ])
          ArchiveEntryInfo(
            name: name,
            size: size,
            compressedSize: comp,
            encrypted: encrypted,
          ),
    ];
    return _IsolateReader(worker, entries);
  }
}

// ── Main-isolate side ───────────────────────────────────────────────────

class _Pending {
  _Pending(this.onBytes);
  final completer = Completer<Object?>();
  final void Function(int bytes)? onBytes;
}

class _Worker {
  _Worker._(this._receive);

  // Results, exit and uncaught errors share one port so they arrive in the
  // order the worker sent them.
  final ReceivePort _receive;
  late final SendPort _send;
  Object? initial;
  final _pending = <int, _Pending>{};
  var _nextId = 1;
  var _dead = false;

  static Future<_Worker> spawn(
    Future<void> Function(List<Object?>) entry,
    List<Object?> args,
  ) async {
    final receive = ReceivePort();
    final worker = _Worker._(receive);
    final ready = Completer<void>();
    void stopped() {
      worker._shutdown();
      if (!ready.isCompleted) {
        ready.completeError(
          const ArchiveException(ArchiveErrorKind.io, 'Worker stopped'),
        );
      }
    }

    receive.listen((m) {
      if (m == null) return stopped(); // onExit
      if (m is! List || m.isEmpty) return;
      switch (m[0]) {
        case 'ready':
          worker
            .._send = m[1] as SendPort
            ..initial = m[2];
          ready.complete();
        case 'fail':
          worker._shutdown();
          if (!ready.isCompleted) {
            ready.completeError(_exception(m[1], m[2]));
          }
        case 'ok':
          worker._pending.remove(m[1])?.completer.complete(m[2]);
        case 'err':
          worker._pending
              .remove(m[1])
              ?.completer
              .completeError(_exception(m[2], m[3]));
        case 'bytes':
          worker._pending[m[1]]?.onBytes?.call(m[2] as int);
        default: // onError: [error, stack]
          stopped();
      }
    });
    try {
      await Isolate.spawn(
        entry,
        [receive.sendPort, ...args],
        onError: receive.sendPort,
        onExit: receive.sendPort,
      );
    } on Object {
      worker._shutdown();
      rethrow;
    }
    await ready.future;
    return worker;
  }

  static ArchiveException _exception(Object? kind, Object? message) =>
      ArchiveException(
        ArchiveErrorKind.values[kind is int ? kind : 0],
        message as String?,
      );

  void _shutdown() {
    if (_dead) return;
    _dead = true;
    for (final p in _pending.values) {
      p.completer.completeError(
        const ArchiveException(ArchiveErrorKind.io, 'Worker stopped'),
      );
    }
    _pending.clear();
    _receive.close();
  }

  bool get isDead => _dead;

  Future<Object?> call(
    String op,
    List<Object?> args, {
    void Function(int bytes)? onBytes,
  }) {
    if (_dead) {
      return Future.error(
        const ArchiveException(ArchiveErrorKind.cancelled, 'Closed'),
      );
    }
    final id = _nextId++;
    final p = _Pending(onBytes);
    _pending[id] = p;
    _send.send([op, id, ...args]);
    return p.completer.future;
  }

  /// Sent out of band: the worker sees it between chunks.
  void signal(String op) {
    if (!_dead) _send.send([op, 0]);
  }

  /// Stops listening once the worker said goodbye.
  void release() => _shutdown();
}

class _IsolateWriter implements ArchiveWriter {
  _IsolateWriter(this._worker, this._path);

  final _Worker _worker;
  final String _path;
  var _finished = false;

  @override
  Future<void> addDirectory(String name) => _worker.call('dir', [name]);

  @override
  Future<void> addFile(
    String sourcePath,
    String name, {
    void Function(int bytes)? onBytes,
  }) => _worker.call('file', [sourcePath, name], onBytes: onBytes);

  @override
  Future<void> addBytes(Uint8List bytes, String name) =>
      _worker.call('bytes', [bytes, name]);

  @override
  Future<int> close() async {
    final length = await _worker.call('close', const []);
    _finished = true;
    _worker.release();
    return length! as int;
  }

  @override
  Future<void> abort() async {
    if (_finished) return;
    _finished = true;
    if (!_worker.isDead) {
      _worker.signal('abort');
      try {
        await _worker
            .call('discard', const [])
            .timeout(const Duration(seconds: 10));
      } on Object {
        // Worker already gone; delete below.
      }
      _worker.release();
    }
    try {
      final f = File(_path);
      if (f.existsSync()) await f.delete();
    } on FileSystemException {
      // Best effort: the export directory is swept with the cache.
    }
  }
}

class _IsolateReader implements ArchiveReader {
  _IsolateReader(this._worker, this.entries);

  final _Worker _worker;

  @override
  final List<ArchiveEntryInfo> entries;

  @override
  bool get hasEncryptedEntries => entries.any((e) => e.encrypted);

  @override
  ArchiveEntryInfo? entry(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }

  @override
  Future<void> extract(
    String name,
    String targetPath, {
    String? password,
    void Function(int bytes)? onBytes,
    JobCancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final off = cancel?.onCancel(() => _worker.signal('stop'));
    try {
      await _worker.call('extract', [
        name,
        targetPath,
        password,
      ], onBytes: onBytes);
    } finally {
      off?.call();
    }
  }

  @override
  Future<Uint8List> readBytes(
    String name, {
    String? password,
    int maxBytes = 32 * 1024 * 1024,
  }) async =>
      (await _worker.call('read', [name, password, maxBytes]))! as Uint8List;

  @override
  Future<void> close() async {
    if (_worker.isDead) return;
    try {
      await _worker.call('close', const []);
    } finally {
      _worker.release();
    }
  }
}

// ── Worker isolates ─────────────────────────────────────────────────────

List<Object?> _classify(Object e) => switch (e) {
  ArchiveException(:final kind, :final message) => [kind.index, message],
  ZipLimitException(:final message) => [
    ArchiveErrorKind.tooLarge.index,
    message,
  ],
  ZipPasswordException(:final message) => [
    ArchiveErrorKind.unsupported.index,
    message,
  ],
  FileSystemException() => [_fsKind(e).index, e.osError?.message ?? e.message],
  FormatException() => [ArchiveErrorKind.corrupt.index, 'Damaged data'],
  _ => [ArchiveErrorKind.io.index, e.runtimeType.toString()],
};

/// Maps an OS error to a kind (errno on Android/iOS/Linux/macOS, Win32
/// codes on Windows).
ArchiveErrorKind _fsKind(FileSystemException e) {
  final code = e.osError?.errorCode;
  final text = '${e.osError?.message} ${e.message}'.toLowerCase();
  if (text.contains('no space') || text.contains('disk full')) {
    return ArchiveErrorKind.noSpace;
  }
  if (Platform.isWindows) {
    return switch (code) {
      112 || 39 => ArchiveErrorKind.noSpace,
      5 || 32 => ArchiveErrorKind.permission,
      2 || 3 => ArchiveErrorKind.notFound,
      _ => ArchiveErrorKind.io,
    };
  }
  return switch (code) {
    28 || 122 => ArchiveErrorKind.noSpace, // ENOSPC, EDQUOT (Linux)
    13 || 1 || 30 => ArchiveErrorKind.permission, // EACCES, EPERM, EROFS
    2 => ArchiveErrorKind.notFound,
    _ => ArchiveErrorKind.io,
  };
}

/// Lets the worker's message loop run (abort/stop signals) between chunks.
Future<void> _yield() => Future<void>.delayed(Duration.zero);

Future<void> _writerMain(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final ZipStreamWriter writer;
  try {
    writer = ZipStreamWriter.create(
      args[1]! as String,
      password: args[2] as String?,
    );
  } on Object catch (e) {
    reply.send(['fail', ..._classify(e)]);
    return;
  }
  final inbox = ReceivePort();
  var aborted = false;
  var broken = false;
  var tail = Future<void>.value();

  Future<void> handle(List<Object?> m) async {
    final op = m[0]! as String;
    final id = m[1]! as int;
    try {
      if (op == 'discard') {
        writer.discard();
        reply.send(['ok', id, null]);
        inbox.close();
        return;
      }
      if (aborted) throw const ArchiveException(ArchiveErrorKind.cancelled);
      if (broken) throw const ArchiveException(ArchiveErrorKind.io, 'Failed');
      switch (op) {
        case 'dir':
          writer.addDirectory(m[2]! as String);
          reply.send(['ok', id, null]);
        case 'bytes':
          writer.addBytes(m[3]! as String, m[2]! as Uint8List);
          reply.send(['ok', id, null]);
        case 'file':
          final source = File(m[2]! as String);
          final name = m[3]! as String;
          final input = source.openSync();
          try {
            final length = input.lengthSync();
            writer.beginEntry(
              name,
              compress: length != 0 && shouldDeflate(name),
            );
            var read = 0;
            while (true) {
              final chunk = input.readSync(zipChunkSize);
              if (chunk.isEmpty) break;
              writer.write(chunk);
              read += chunk.length;
              reply.send(['bytes', id, read]);
              await _yield();
              if (aborted) {
                throw const ArchiveException(ArchiveErrorKind.cancelled);
              }
            }
            writer.endEntry();
          } finally {
            input.closeSync();
          }
          reply.send(['ok', id, null]);
        case 'close':
          final length = writer.finish();
          reply.send(['ok', id, length]);
          inbox.close();
      }
    } on Object catch (e) {
      broken = true;
      reply.send(['err', id, ..._classify(e)]);
    }
  }

  inbox.listen((m) {
    if (m is! List) return;
    if (m[0] == 'abort') {
      aborted = true;
      return;
    }
    tail = tail.then((_) => handle(m.cast<Object?>()));
  });
  reply.send(['ready', inbox.sendPort, null]);
}

Future<void> _readerMain(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final ZipStreamReader reader;
  try {
    reader = ZipStreamReader.open(args[1]! as String);
  } on Object catch (e) {
    reply.send(['fail', ..._classify(e)]);
    return;
  }
  final inbox = ReceivePort();
  var stop = false;
  var tail = Future<void>.value();

  ZipRecord find(String name) =>
      reader.record(name) ??
      (throw const ArchiveException(ArchiveErrorKind.notFound));

  Future<void> handle(List<Object?> m) async {
    final op = m[0]! as String;
    final id = m[1]! as int;
    try {
      switch (op) {
        case 'extract':
          stop = false;
          final r = find(m[2]! as String);
          final target = m[3]! as String;
          final part = File('$target.part');
          part.parent.createSync(recursive: true);
          final out = part.openSync(mode: FileMode.write);
          var written = 0;
          try {
            final job = reader.begin(r, (d) {
              out.writeFromSync(d);
              written += d.length;
            }, password: m[4] as String?);
            while (job.step()) {
              reply.send(['bytes', id, written]);
              await _yield();
              if (stop) {
                throw const ArchiveException(ArchiveErrorKind.cancelled);
              }
            }
            job.finish();
            out
              ..flushSync()
              ..closeSync();
            part.renameSync(target);
          } on Object {
            try {
              out.closeSync();
            } on Object {
              // Already closed.
            }
            if (part.existsSync()) part.deleteSync();
            rethrow;
          }
          reply.send(['ok', id, null]);
        case 'read':
          final r = find(m[2]! as String);
          final bytes = reader.readBytes(
            r,
            password: m[3] as String?,
            maxBytes: m[4] as int?,
          );
          reply.send(['ok', id, bytes]);
        case 'close':
          reader.close();
          reply.send(['ok', id, null]);
          inbox.close();
      }
    } on Object catch (e) {
      reply.send(['err', id, ..._classify(e)]);
    }
  }

  inbox.listen((m) {
    if (m is! List) return;
    if (m[0] == 'stop') {
      stop = true;
      return;
    }
    tail = tail.then((_) => handle(m.cast<Object?>()));
  });
  reply.send([
    'ready',
    inbox.sendPort,
    [
      for (final r in reader.records)
        [r.name, r.size, r.compressedSize, r.encrypted],
    ],
  ]);
}
