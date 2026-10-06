import 'dart:io';

import 'package:engine_pdf/src/protect/zip_stream.dart';

export 'package:engine_pdf/src/protect/zip_stream.dart'
    show
        ZipLimitException,
        ZipPasswordException,
        deriveAe256Keys,
        zipPasswordBytes;

// AES-256 encrypted ZIP archives in the WinZip AE-2 format
// (https://www.winzip.com/en/support/aes-encryption/):
//  * each entry: local header (method 99, extra field 0x9901 with vendor
//    version 2, vendor "AE", strength 3 = AES-256, and the real method),
//    then salt (16 bytes) || password verifier (2 bytes) || AES-256-CTR
//    ciphertext of the (optionally deflated) data || first 10 bytes of the
//    HMAC-SHA1 of the ciphertext;
//  * keys: PBKDF2-HMAC-SHA1(password, salt, 1000 iterations) → 66 bytes =
//    AES key (32) || HMAC key (32) || verifier (2);
//  * AE-2 stores CRC-32 = 0: integrity comes from the HMAC, and the CRC
//    of the plaintext would leak information.
// Legacy ZipCrypto is never written. The entry writer lives in
// zip_stream.dart and is shared with the full backup (ZipArchiveCodec).
// Limits: no ZIP64, so every entry and the whole archive must stay under
// 4 GiB, and at most 65,535 entries.

/// Unique, safe entry names: path separators and control characters are
/// replaced, and duplicates (case-insensitive) become `name (2).ext`.
List<String> uniqueEntryNames(List<String> names) {
  final used = <String>{};
  final out = <String>[];
  for (final raw in names) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (name.isEmpty || name == '.' || name == '..') name = 'file';
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = name;
    var n = 2;
    while (!used.add(candidate.toLowerCase())) {
      candidate = '$stem ($n)$ext';
      n++;
    }
    out.add(candidate);
  }
  return out;
}

/// Writes [paths] (stored as [names]) into an AE-2 archive at [outputPath].
/// [onProgress] receives 0..1 by input bytes. Returns the archive size.
/// Synchronous: call it from a background isolate.
int writeAe2ZipSync(
  List<String> paths,
  List<String> names,
  String password,
  String outputPath, {
  void Function(double progress)? onProgress,
  DateTime? now,
}) {
  if (paths.isEmpty) throw ArgumentError('No files');
  if (paths.length != names.length) throw ArgumentError('names');
  if (paths.length > 0xFFFF) {
    throw const ZipLimitException('Too many files for one ZIP (max 65,535).');
  }
  zipPasswordBytes(password); // Validate before creating the file.
  final entryNames = uniqueEntryNames(names);
  final files = [for (final p in paths) File(p)];
  final sizes = [for (final f in files) f.lengthSync()];
  final total = sizes.fold<int>(0, (a, b) => a + b);
  if (sizes.any((s) => s >= 0xFFFFFFFF - 64) || total >= 0xFFFFFFFF) {
    throw const ZipLimitException('Files over 4 GB can’t go into a ZIP here.');
  }

  final writer = ZipStreamWriter.create(outputPath, password: password);
  var done = 0;
  var lastReported = -1.0;
  void report() {
    if (onProgress == null || total == 0) return;
    final p = done / total;
    if (p - lastReported >= 0.01 || p >= 1) {
      lastReported = p;
      onProgress(p);
    }
  }

  try {
    for (var i = 0; i < files.length; i++) {
      writer.beginEntry(
        entryNames[i],
        compress: sizes[i] != 0 && shouldDeflate(entryNames[i]),
        modified: _modified(files[i], now),
      );
      final input = files[i].openSync();
      try {
        while (true) {
          final chunk = input.readSync(zipChunkSize);
          if (chunk.isEmpty) break;
          writer.write(chunk);
          done += chunk.length;
          report();
        }
      } finally {
        input.closeSync();
      }
      writer.endEntry();
    }
    final length = writer.finish();
    onProgress?.call(1);
    return length;
  } on Object {
    writer.discard();
    rethrow;
  }
}

DateTime _modified(File f, DateTime? now) {
  try {
    return now ?? f.lastModifiedSync();
  } on FileSystemException {
    return now ?? DateTime.now();
  }
}
