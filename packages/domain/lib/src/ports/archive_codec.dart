import 'dart:typed_data';

import 'package:meta/meta.dart';

// Streaming ZIP archives (plain or AES-256 / WinZip AE-2) for the full
// backup (H-04/H-05). Implemented by `engine_pdf` next to the protected-ZIP
// writer, so both share one writer. Work runs off the UI isolate and memory
// stays at a few chunks whatever the archive size.

/// Cooperative cancellation for long jobs (export, import, archive I/O).
class JobCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  /// Requests cancellation; listeners run once.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
    _listeners.clear();
  }

  /// Runs [listener] on [cancel] (immediately when already cancelled).
  /// Returns a function that unregisters it.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Throws [ArchiveException] ([ArchiveErrorKind.cancelled]) when cancelled.
  void throwIfCancelled() {
    if (_cancelled) {
      throw const ArchiveException(ArchiveErrorKind.cancelled);
    }
  }
}

/// Why an archive operation failed.
enum ArchiveErrorKind {
  /// The entry is encrypted and no password was given.
  passwordRequired,

  /// The password doesn't open the entry.
  wrongPassword,

  /// Not a ZIP, truncated, or an entry failed its integrity check.
  corrupt,

  /// A ZIP feature this app doesn't read (ZIP64, other encryption, method).
  unsupported,

  /// More than 4 GB or 65,535 entries.
  tooLarge,

  /// The device ran out of space.
  noSpace,

  /// The file or folder can't be read or written (permissions).
  permission,

  /// A file disappeared.
  notFound,

  /// [JobCancelToken.cancel] or [ArchiveWriter.abort] was called.
  cancelled,

  /// Anything else (I/O error).
  io,
}

/// A failed archive operation. [message] is safe to log: it never contains
/// paths or content.
class ArchiveException implements Exception {
  const ArchiveException(this.kind, [this.message]);

  final ArchiveErrorKind kind;
  final String? message;

  @override
  String toString() =>
      'ArchiveException(${kind.name}${message == null ? '' : ': $message'})';
}

/// One entry of an archive.
@immutable
class ArchiveEntryInfo {
  const ArchiveEntryInfo({
    required this.name,
    required this.size,
    required this.compressedSize,
    required this.encrypted,
  });

  /// Path inside the archive, `/`-separated; directories end with `/`.
  final String name;

  /// Uncompressed size in bytes.
  final int size;
  final int compressedSize;
  final bool encrypted;

  bool get isDirectory => name.endsWith('/');
}

/// Writes one archive, entry by entry. Every call streams from or to disk
/// on a background isolate.
abstract interface class ArchiveWriter {
  /// An empty directory entry (`name` ends with `/`). Never encrypted.
  Future<void> addDirectory(String name);

  /// Streams the file at [sourcePath] into entry [name]. [onBytes] reports
  /// input bytes consumed so far for this entry.
  Future<void> addFile(
    String sourcePath,
    String name, {
    void Function(int bytes)? onBytes,
  });

  /// Small in-memory entries (JSON, thumbnails).
  Future<void> addBytes(Uint8List bytes, String name);

  /// Writes the central directory and closes the file; returns its size.
  Future<int> close();

  /// Stops at the next chunk, closes and deletes the partial file. A
  /// pending call fails with [ArchiveErrorKind.cancelled]. Safe to call
  /// more than once and after a failure.
  Future<void> abort();
}

/// Reads one archive. Entries are listed from the central directory;
/// contents are streamed and verified (CRC-32, or the AE-2 HMAC).
abstract interface class ArchiveReader {
  List<ArchiveEntryInfo> get entries;

  /// True when any entry is encrypted.
  bool get hasEncryptedEntries;

  ArchiveEntryInfo? entry(String name);

  /// Streams entry [name] into [targetPath] (written atomically; nothing is
  /// left behind on failure or cancellation).
  Future<void> extract(
    String name,
    String targetPath, {
    String? password,
    void Function(int bytes)? onBytes,
    JobCancelToken? cancel,
  });

  /// Reads a small entry into memory; [ArchiveErrorKind.tooLarge] above
  /// [maxBytes].
  Future<Uint8List> readBytes(
    String name, {
    String? password,
    int maxBytes = 32 * 1024 * 1024,
  });

  Future<void> close();
}

/// Creates archive readers and writers.
abstract interface class ArchiveCodec {
  /// A new archive at [outputPath] (replaced if it exists). With a
  /// [password] every file entry is AES-256 encrypted (WinZip AE-2, opens
  /// in 7-Zip, WinZip, Keka…); [ArchiveErrorKind.unsupported] when the
  /// password can't be used by every unzip app (non-ASCII).
  Future<ArchiveWriter> createWriter(String outputPath, {String? password});

  /// Opens [path]; [ArchiveErrorKind.corrupt] when it isn't a readable ZIP.
  Future<ArchiveReader> openReader(String path);
}
