import 'dart:io';
import 'dart:isolate';

import 'package:docscan_data/src/vault/shred.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLCipher for the Drift database (ADR-0010).
///
/// The DB key is a raw 256-bit key (`PRAGMA key = "x'…'"`), so SQLCipher
/// skips its PBKDF2 step and opening stays fast.
abstract final class EncryptedDatabase {
  static const _sqliteMagic = 'SQLite format 3\u0000';

  /// Suffixes of the crash-safe plaintext → SQLCipher swap.
  static const tmpSuffix = '.enc-tmp';
  static const oldSuffix = '.plain-old';
  static const _sidecars = ['-wal', '-shm', '-journal'];

  static String hexKey(Uint8List key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// True when [path] is an unencrypted SQLite file.
  static bool isPlaintext(String path) {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 16) return false;
    final raf = f.openSync();
    try {
      return String.fromCharCodes(raf.readSync(16)) == _sqliteMagic;
    } finally {
      raf.closeSync();
    }
  }

  /// Applies the key and proves the build really is SQLCipher (a plain
  /// SQLite build would silently ignore `PRAGMA key`) and that the key
  /// opens the file. Throws otherwise.
  static void applyKey(Database db, String hex) {
    db.execute('PRAGMA key = "x\'$hex\'"');
    final version = db.select('PRAGMA cipher_version');
    if (version.isEmpty || '${version.first.values.first}'.isEmpty) {
      throw StateError('SQLCipher is not available in this build');
    }
    // Fails with SQLITE_NOTADB when the key is wrong.
    db.select('SELECT count(*) FROM sqlite_master');
  }

  /// A Drift executor for the encrypted database at [file].
  static QueryExecutor open(File file, Uint8List key) {
    final hex = hexKey(key);
    return NativeDatabase.createInBackground(
      file,
      setup: (db) => applyKey(db, hex),
    );
  }

  /// Migrates a plaintext database at [path] to SQLCipher, or finishes a
  /// migration that was interrupted. Idempotent; runs in a background
  /// isolate. Returns true when a plaintext database was converted.
  static Future<bool> migrate(String path, Uint8List key) {
    final hex = hexKey(key);
    return Isolate.run(() => migrateSync(path, hex));
  }

  /// Synchronous body of [migrate]. [crashAt] simulates the app being killed
  /// after the named step (`exported`, `renamedOld`, `renamedNew`).
  @visibleForTesting
  static bool migrateSync(String path, String hex, {String? crashAt}) {
    final main = File(path);
    final tmp = File('$path$tmpSuffix');
    final old = File('$path$oldSuffix');

    // 1. Recover from an interrupted swap.
    if (!main.existsSync()) {
      if (old.existsSync() && tmp.existsSync()) {
        if (_verify(tmp.path, hex, source: null)) {
          tmp.renameSync(path);
        } else {
          tmp.deleteSync();
          old.renameSync(path);
        }
      } else if (old.existsSync()) {
        old.renameSync(path);
      } else if (tmp.existsSync()) {
        tmp.deleteSync();
      }
    }
    if (!main.existsSync()) return false; // Fresh install.

    if (!isPlaintext(path)) {
      // Encrypted already: finish the cleanup.
      if (tmp.existsSync()) tmp.deleteSync();
      _shredSync(old.path);
      return false;
    }

    // 2. Export to the temporary encrypted copy.
    if (tmp.existsSync()) tmp.deleteSync();
    final src = sqlite3.open(path);
    try {
      // Fold any WAL into the main file so the rename below never leaves a
      // plaintext -wal next to the encrypted database.
      src
        ..execute('PRAGMA wal_checkpoint(TRUNCATE)')
        ..execute('PRAGMA journal_mode = DELETE');
      final version = src.select('PRAGMA user_version').first.values.first;
      src
        ..execute("ATTACH DATABASE ? AS encrypted KEY \"x'$hex'\"", [tmp.path])
        ..select("SELECT sqlcipher_export('encrypted')")
        ..execute('PRAGMA encrypted.user_version = $version')
        ..execute('DETACH DATABASE encrypted');
    } finally {
      src.close();
    }
    if (crashAt == 'exported') throw const _SimulatedCrash();

    // 3. Verify before touching the original.
    if (!_verify(tmp.path, hex, source: path)) {
      tmp.deleteSync();
      throw StateError('Encrypted database copy failed verification');
    }

    // 4. Swap.
    for (final s in _sidecars) {
      _shredSync('$path$s');
    }
    main.renameSync(old.path);
    if (crashAt == 'renamedOld') throw const _SimulatedCrash();
    tmp.renameSync(path);
    if (crashAt == 'renamedNew') throw const _SimulatedCrash();

    // 5. Shred the plaintext.
    _shredSync(old.path);
    return true;
  }

  /// Opens [encrypted] with the key; checks integrity and, with [source],
  /// that every table has the same row count and the same user_version.
  static bool _verify(String encrypted, String hex, {required String? source}) {
    Database? db;
    Database? plain;
    try {
      db = sqlite3.open(encrypted);
      applyKey(db, hex);
      if (db.select('PRAGMA cipher_integrity_check').isNotEmpty) return false;
      final ok = db.select('PRAGMA integrity_check').first.values.first;
      if (ok != 'ok') return false;
      if (source == null) return true;
      plain = sqlite3.open(source, mode: OpenMode.readOnly);
      final tables = plain
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'] as String)
          .toList();
      for (final t in tables) {
        final q = 'SELECT count(*) AS n FROM "${t.replaceAll('"', '""')}"';
        if (plain.select(q).first['n'] != db.select(q).first['n']) {
          return false;
        }
      }
      const v = 'PRAGMA user_version';
      return plain.select(v).first.values.first ==
          db.select(v).first.values.first;
    } on Object {
      return false;
    } finally {
      db?.close();
      plain?.close();
    }
  }

  static void _shredSync(String path) {
    final f = File(path);
    if (!f.existsSync()) return;
    try {
      final raf = f.openSync(mode: FileMode.append)..setPositionSync(0);
      final len = f.lengthSync();
      final zeros = Uint8List(64 * 1024);
      for (var left = len; left > 0; left -= zeros.length) {
        raf.writeFromSync(zeros, 0, left < zeros.length ? left : zeros.length);
      }
      raf
        ..flushSync()
        ..closeSync();
    } on Object {
      // Best effort.
    }
    try {
      f.deleteSync();
    } on FileSystemException {
      // Retried at the next launch.
    }
  }

  /// Async shred of the database and its side files (erase vault).
  static Future<void> delete(String path) async {
    for (final s in ['', ...tmpSuffixes, ..._sidecars]) {
      await shredFile('$path$s');
    }
  }

  static const tmpSuffixes = [tmpSuffix, oldSuffix];
}

class _SimulatedCrash implements Exception {
  const _SimulatedCrash();
}
