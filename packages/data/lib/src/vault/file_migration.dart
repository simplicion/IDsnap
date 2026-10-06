import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/vault/shred.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Encrypts plaintext vault files in place (ADR-0010), one file at a time.
///
/// Per file `x`: encrypt to `x.enc-part` (fsynced by the cipher), verify by
/// decrypting it and comparing with `x`, rename `x` → `x.plain-old`, rename
/// `x.enc-part` → `x`, shred `x.plain-old`. Every intermediate state is
/// visible on disk, so [run] resumes after a crash without a journal and
/// never loses a file.
class VaultFileMigrator {
  VaultFileMigrator({
    required this.cipher,
    required this.directories,
    required this.scratchDirectory,
    RedactedLogger? logger,
    @visibleForTesting this.onStep,
  }) : _log = logger ?? RedactedLogger('vault_migration');

  static const encPart = '.enc-part';
  static const plainOld = '.plain-old';

  final FileCipher cipher;

  /// Vault directories to migrate (recursively).
  final List<String> directories;

  /// Private cache directory for verification copies.
  final String scratchDirectory;

  /// Test hook: called after each step (`encrypted`, `renamedOld`,
  /// `renamedNew`) and may throw to simulate the app being killed.
  final void Function(String step, String path)? onStep;

  final RedactedLogger _log;

  Future<bool> _encrypted(String path) async {
    final raf = await File(path).open();
    try {
      return cipher.isEncrypted(await raf.read(cipher.headerLength));
    } finally {
      await raf.close();
    }
  }

  Future<List<String>> _files() async {
    final out = <String>[];
    for (final d in directories) {
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) out.add(e.path);
      }
    }
    out.sort();
    return out;
  }

  /// Base paths that need work (plaintext, or an interrupted step).
  Future<List<String>> pending() async {
    final files = await _files();
    final present = files.toSet();
    final work = <String>{};
    for (final f in files) {
      if (f.endsWith('$encPart.part')) {
        work.add(f.substring(0, f.length - '$encPart.part'.length));
      } else if (f.endsWith(encPart)) {
        work.add(f.substring(0, f.length - encPart.length));
      } else if (f.endsWith(plainOld)) {
        work.add(f.substring(0, f.length - plainOld.length));
      } else if (f.endsWith('.part')) {
        // A stale partial write (thumbnail, cipher output): never complete.
        work.add(f);
      } else if (!await _encrypted(f)) {
        work.add(f);
      }
    }
    return [
      for (final w in work.toList()..sort())
        if (!w.endsWith('.part') || present.contains(w)) w,
    ];
  }

  /// Migrates everything; returns the number of files encrypted.
  Future<int> run({void Function(int done, int total)? onProgress}) async {
    final work = await pending();
    if (work.isEmpty) return 0;
    await Directory(scratchDirectory).create(recursive: true);
    var encrypted = 0;
    for (final (i, path) in work.indexed) {
      onProgress?.call(i, work.length);
      if (await _migrateOne(path)) encrypted++;
    }
    onProgress?.call(work.length, work.length);
    _log.info('migrated', {'files': encrypted});
    return encrypted;
  }

  Future<bool> _migrateOne(String path) async {
    if (path.endsWith('.part')) {
      await shredFile(path);
      return false;
    }
    final main = File(path);
    final part = File('$path$encPart');
    final old = File('$path$plainOld');
    await shredFile('${part.path}.part');

    // Recover an interrupted swap.
    if (!main.existsSync()) {
      if (old.existsSync() && part.existsSync() && await _verifies(part.path)) {
        await part.rename(path);
      } else if (old.existsSync()) {
        if (part.existsSync()) await part.delete();
        await old.rename(path);
      } else if (part.existsSync()) {
        // No plaintext left: keep the part only if it is a sound vault file.
        if (await _verifies(part.path)) {
          await part.rename(path);
        } else {
          await part.delete();
        }
        return false;
      } else {
        return false;
      }
    }

    if (await _encrypted(path)) {
      if (part.existsSync()) await part.delete();
      await shredFile(old.path);
      return false;
    }

    // Plaintext: encrypt, verify, swap, shred.
    if (part.existsSync()) await part.delete();
    await cipher.encryptFile(path, part.path);
    onStep?.call('encrypted', path);
    if (!await _verifies(part.path, original: path)) {
      await part.delete();
      throw StateError('Encrypted copy failed verification');
    }
    await main.rename(old.path);
    onStep?.call('renamedOld', path);
    await part.rename(path);
    onStep?.call('renamedNew', path);
    await shredFile(old.path);
    return true;
  }

  /// Decrypts [sealed] into the scratch directory and, with [original],
  /// compares it byte for byte.
  Future<bool> _verifies(String sealed, {String? original}) async {
    final check = p.join(scratchDirectory, '${newId()}.verify');
    try {
      await cipher.decryptFile(sealed, check);
      if (original == null) return true;
      return await _sameContent(check, original);
    } on Object {
      return false;
    } finally {
      await shredFile(check);
    }
  }

  static Future<bool> _sameContent(String a, String b) async {
    final fa = File(a);
    final fb = File(b);
    if (await fa.length() != await fb.length()) return false;
    final ra = await fa.open();
    final rb = await fb.open();
    try {
      while (true) {
        final x = await ra.read(256 * 1024);
        final y = await rb.read(256 * 1024);
        if (x.length != y.length) return false;
        if (x.isEmpty) return true;
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
      }
    } finally {
      await ra.close();
      await rb.close();
    }
  }
}
