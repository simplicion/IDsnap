import 'dart:io';
import 'dart:typed_data';

/// Best-effort shred: overwrite with zeros, fsync, delete. On flash storage
/// with wear levelling the old blocks may survive; the guarantee we rely on
/// is that plaintext only ever lives briefly in the app cache (ADR-0010).
Future<void> shredFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final length = await file.length();
    // `append` opens read/write without truncating; setPosition rewinds.
    final raf = await file.open(mode: FileMode.append);
    try {
      await raf.setPosition(0);
      final zeros = Uint8List(64 * 1024);
      var left = length;
      while (left > 0) {
        final n = left < zeros.length ? left : zeros.length;
        await raf.writeFrom(zeros, 0, n);
        left -= n;
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
  } on Object {
    // Overwrite failed (locked, read-only): still try to delete.
  }
  try {
    await file.delete();
  } on FileSystemException {
    // Already gone or locked; the next launch retries.
  }
}

/// Shreds every file below [path], then removes the directory tree.
Future<void> shredDirectory(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) return;
  try {
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) await shredFile(e.path);
    }
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Best effort.
  }
}
