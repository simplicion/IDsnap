import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/protect/ae2_zip_writer.dart';
import 'package:engine_pdf/src/protect/crypto.dart';
import 'package:engine_pdf/src/protect/pdf_encryptor.dart';
import 'package:engine_pdf/src/protect/pdf_security.dart';
import 'package:engine_pdf/src/stamp/pdf_syntax.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfProtector] and [ProtectedZipWriter]: AES-256 PDFs (security handler
/// R6, pure Dart) validated with PDFium, and AES-256 ZIPs (WinZip AE-2).
///
/// Passwords are only held for the duration of a call: never logged,
/// persisted or included in failures.
class PdfProtectionEngine implements PdfProtector, ProtectedZipWriter {
  PdfProtectionEngine({RedactedLogger? logger})
    : _log = logger ?? RedactedLogger('protect');

  final RedactedLogger _log;

  static const opTimeout = Duration(seconds: 90);

  // ── PDF ────────────────────────────────────────────────────────────────

  @override
  Future<Result<bool>> needsPassword(String path) async {
    final missing = _checkInput(path);
    if (missing != null) return Err(missing);
    rx.PdfDocument? doc;
    try {
      doc = await rx.PdfDocument.openFile(path).timeout(opTimeout);
      return const Ok(false);
    } on rx.PdfPasswordException {
      return const Ok(true);
    } on TimeoutException catch (e, st) {
      return Err(AppFailure(FailureCode.timeout, cause: e, stackTrace: st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    } finally {
      await doc?.dispose();
    }
  }

  @override
  Future<Result<ProtectedFile>> protectPdf(
    String inputPath,
    PdfProtection protection, {
    required String outputPath,
    String? currentPassword,
  }) async {
    final bad = validatePdfPassword(protection.openPassword);
    if (bad != null) return Err(_badPassword(bad));
    final owner = protection.ownerPassword;
    if (owner != null) {
      final badOwner = validatePdfPassword(owner);
      if (badOwner != null) return Err(_badPassword(badOwner));
      if (owner == protection.openPassword) {
        return Err(
          _badPassword(
            'The permissions password must be different from the open '
            'password.',
          ),
        );
      }
    }
    final opened = await _openFile(inputPath, currentPassword);
    if (opened case Err(:final failure)) return Err(failure);
    final doc = opened.valueOrNull!;
    try {
      final pages = doc.pages.length;
      final permissions = owner == null
          ? PdfPermissionBits.value(print: true, copy: true, edit: true)
          : PdfPermissionBits.value(
              print: protection.allowPrinting,
              copy: protection.allowCopying,
              edit: protection.allowEditing,
            );
      // A random owner password when none is set: every permission is
      // granted and nobody can change them.
      final ownerPassword = owner ?? _randomOwnerPassword();

      // Candidates, in order of fidelity: the original bytes; a full PDFium
      // re-save (decrypted, normalised); pages re-imported into a new file.
      final candidates = <Future<Uint8List?> Function()>[
        if (!doc.isEncrypted) () => File(inputPath).readAsBytes(),
        () => _tryEncode(doc, removeSecurity: true),
        () => _tryImportPages(doc),
      ];
      for (final (i, candidate) in candidates.indexed) {
        final base = await candidate();
        if (base == null) continue;
        final Uint8List encrypted;
        try {
          encrypted = await _runEncrypt(
            base,
            protection.openPassword,
            ownerPassword,
            permissions,
          );
        } on PdfSyntaxException catch (e) {
          _log.warn('protect_rewrite_unavailable', {
            'step': i,
            'reason': e.message,
          });
          continue;
        } on PdfEncryptedInputException {
          continue;
        }
        if (await _verifyProtected(encrypted, protection.openPassword, pages)) {
          await _write(outputPath, encrypted);
          _log.info('pdf_protected', {'pages': pages, 'step': i});
          return Ok(
            ProtectedFile(
              path: outputPath,
              format: DocumentFormat.pdf,
              sizeBytes: encrypted.length,
              pageCount: pages,
            ),
          );
        }
        _log.warn('protect_verify_failed', {'step': i});
      }
      return const Err(
        AppFailure(
          FailureCode.outputValidationFailed,
          message:
              "The protected PDF couldn't be verified, so nothing was saved. "
              'Your original is unchanged.',
        ),
      );
    } on Object catch (e, st) {
      return Err(_mapError(e, st));
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<Result<ProtectedFile>> removePdfPassword(
    String inputPath,
    String password, {
    required String outputPath,
  }) async {
    if (password.isEmpty) {
      return const Err(AppFailure(FailureCode.passwordProtected));
    }
    final opened = await _openFile(inputPath, password);
    if (opened case Err(:final failure)) return Err(failure);
    final doc = opened.valueOrNull!;
    try {
      if (!doc.isEncrypted) {
        return const Err(
          AppFailure(
            FailureCode.conversionFailed,
            detail: 'Not protected',
            message:
                "This PDF doesn't have a password, so there is nothing to "
                'remove.',
            action: FailureAction.pickDifferentFile,
          ),
        );
      }
      final pages = doc.pages.length;
      final candidates = <Future<Uint8List?> Function()>[
        // Pure-Dart R6 decryption keeps the file byte-for-byte otherwise.
        () async {
          try {
            final bytes = await File(inputPath).readAsBytes();
            return await Isolate.run(() => decryptPdfR6(bytes, password));
          } on Object {
            return null;
          }
        },
        () => _tryEncode(doc, removeSecurity: true),
        () => _tryImportPages(doc),
      ];
      for (final (i, candidate) in candidates.indexed) {
        final bytes = await candidate();
        if (bytes == null) continue;
        if (await _verifyOpen(bytes, pages)) {
          await _write(outputPath, bytes);
          _log.info('pdf_unlocked', {'pages': pages, 'step': i});
          return Ok(
            ProtectedFile(
              path: outputPath,
              format: DocumentFormat.pdf,
              sizeBytes: bytes.length,
              pageCount: pages,
            ),
          );
        }
      }
      return const Err(AppFailure(FailureCode.outputValidationFailed));
    } on Object catch (e, st) {
      return Err(_mapError(e, st));
    } finally {
      await doc.dispose();
    }
  }

  // ── ZIP ────────────────────────────────────────────────────────────────

  @override
  Future<Result<ProtectedFile>> writeProtectedZip(
    List<ZipSource> sources,
    String password, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (sources.isEmpty) {
      return const Err(
        AppFailure(FailureCode.conversionFailed, detail: 'No files'),
      );
    }
    for (final s in sources) {
      final missing = _checkInput(s.path, allowEmpty: true);
      if (missing != null) return Err(missing.withDetail(s.fileName));
    }
    try {
      zipPasswordBytes(password);
    } on ZipPasswordException catch (e) {
      return Err(_badPassword(e.message));
    }
    try {
      final size = await runWriteAe2Zip(
        [for (final s in sources) s.path],
        [for (final s in sources) s.fileName],
        password,
        outputPath,
        onProgress,
      );
      _log.info('zip_protected', {'files': sources.length, 'bytes': size});
      return Ok(
        ProtectedFile(
          path: outputPath,
          format: DocumentFormat.zip,
          sizeBytes: size,
        ),
      );
    } on Object catch (e, st) {
      try {
        final f = File(outputPath);
        if (f.existsSync()) f.deleteSync();
      } on Object {
        // Best effort: temp files are cleared on the next launch anyway.
      }
      return Err(_mapError(e, st));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static AppFailure? _checkInput(String path, {bool allowEmpty = false}) {
    final f = File(path);
    if (!f.existsSync()) return const AppFailure(FailureCode.notFound);
    if (!allowEmpty && f.lengthSync() == 0) {
      return const AppFailure(FailureCode.emptyFile);
    }
    return null;
  }

  static AppFailure _badPassword(String message) => AppFailure(
    FailureCode.conversionFailed,
    detail: 'Password',
    message: message,
    action: FailureAction.none,
  );

  /// Opens [path] with PDFium, using [password] only if one is needed.
  Future<Result<rx.PdfDocument>> _openFile(
    String path,
    String? password,
  ) async {
    final missing = _checkInput(path);
    if (missing != null) return Err(missing);
    try {
      final doc = await rx.PdfDocument.openFile(
        path,
        passwordProvider: _once(password),
      ).timeout(opTimeout);
      return Ok(doc);
    } on rx.PdfPasswordException catch (e, st) {
      return Err(
        AppFailure(
          password == null || password.isEmpty
              ? FailureCode.passwordProtected
              : FailureCode.wrongPassword,
          cause: e,
          stackTrace: st,
        ),
      );
    } on TimeoutException catch (e, st) {
      return Err(AppFailure(FailureCode.timeout, cause: e, stackTrace: st));
    } on Object catch (e, st) {
      _log.warn('protect_open_failed', {'type': e.runtimeType.toString()});
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    }
  }

  static rx.PdfPasswordProvider? _once(String? password) {
    if (password == null) return null;
    String? pending = password;
    return () {
      final p = pending;
      pending = null;
      return p;
    };
  }

  Future<Uint8List?> _tryEncode(
    rx.PdfDocument doc, {
    required bool removeSecurity,
  }) async {
    try {
      return await doc
          .encodePdf(removeSecurity: removeSecurity)
          .timeout(opTimeout);
    } on Object catch (e) {
      _log.warn('protect_resave_failed', {'type': e.runtimeType.toString()});
      return null;
    }
  }

  Future<Uint8List?> _tryImportPages(rx.PdfDocument doc) async {
    rx.PdfDocument? out;
    try {
      final created = await rx.PdfDocument.createNew(
        sourceName: 'protect-import',
      );
      out = created..pages = doc.pages;
      return await created.encodePdf().timeout(opTimeout);
    } on Object catch (e) {
      _log.warn('protect_import_failed', {'type': e.runtimeType.toString()});
      return null;
    } finally {
      await out?.dispose();
    }
  }

  /// The output needs the password (and PDFium says so), opens with it and
  /// has every page.
  Future<bool> _verifyProtected(
    Uint8List bytes,
    String password,
    int pages,
  ) async {
    rx.PdfDocument? doc;
    try {
      try {
        doc = await rx.PdfDocument.openData(
          bytes,
          sourceName: 'protect-verify-locked-${newId()}',
        ).timeout(opTimeout);
        return false; // Opened without a password: not protected.
      } on rx.PdfPasswordException {
        // Expected.
      }
      doc = await rx.PdfDocument.openData(
        bytes,
        sourceName: 'protect-verify-${newId()}',
        passwordProvider: _once(password),
        firstAttemptByEmptyPassword: false,
      ).timeout(opTimeout);
      return doc.isEncrypted && doc.pages.length == pages;
    } on Object {
      return false;
    } finally {
      await doc?.dispose();
    }
  }

  Future<bool> _verifyOpen(Uint8List bytes, int pages) async {
    rx.PdfDocument? doc;
    try {
      doc = await rx.PdfDocument.openData(
        bytes,
        sourceName: 'unlock-verify-${newId()}',
      ).timeout(opTimeout);
      return !doc.isEncrypted && doc.pages.length == pages;
    } on Object {
      return false;
    } finally {
      await doc?.dispose();
    }
  }

  static Future<void> _write(String path, Uint8List bytes) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  static String _randomOwnerPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final bytes = secureRandomBytes(32);
    return String.fromCharCodes([
      for (final b in bytes) alphabet.codeUnitAt(b % alphabet.length),
    ]);
  }

  AppFailure _mapError(Object e, StackTrace st) {
    _log.error('protect_failed', {'type': e.runtimeType.toString()});
    return switch (e) {
      ZipLimitException(:final message) => AppFailure(
        FailureCode.memoryLimitExceeded,
        cause: e,
        stackTrace: st,
        message: message,
        action: FailureAction.pickDifferentFile,
      ),
      ZipPasswordException(:final message) => _badPassword(message),
      FileSystemException(:final osError)
          when osError?.errorCode == 28 || osError?.errorCode == 112 =>
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      PathNotFoundException() => AppFailure(
        FailureCode.notFound,
        cause: e,
        stackTrace: st,
      ),
      FileSystemException() => AppFailure(
        FailureCode.insufficientStorage,
        cause: e,
        stackTrace: st,
      ),
      TimeoutException() => AppFailure(
        FailureCode.timeout,
        cause: e,
        stackTrace: st,
      ),
      _ => AppFailure(FailureCode.conversionFailed, cause: e, stackTrace: st),
    };
  }
}

/// Null when [password] can protect a PDF, else why not.
String? validatePdfPassword(String password) {
  if (password.isEmpty) return 'Enter a password.';
  // R6 uses the first 127 UTF-8 bytes; longer passwords would be silently
  // truncated, so reject them instead.
  if (utf8.encode(password).length > 127) {
    return 'Use a shorter password (at most 127 characters).';
  }
  return null;
}

// ISOLATE BOUNDARY: see isolate_jobs.dart. Closures are created inside these
// top-level functions so they capture only plain data.

Future<Uint8List> _runEncrypt(
  Uint8List base,
  String user,
  String owner,
  int permissions,
) => Isolate.run(
  () => encryptPdfR6(
    base,
    PdfR6Security.create(
      userPassword: user,
      ownerPassword: owner,
      permissions: permissions,
    ),
  ),
);

/// Writes an AE-2 ZIP on a background isolate, forwarding progress.
Future<int> runWriteAe2Zip(
  List<String> paths,
  List<String> names,
  String password,
  String outputPath,
  void Function(double progress)? onProgress,
) async {
  final port = ReceivePort();
  final send = port.sendPort;
  final sub = port.listen((m) {
    if (m is double) onProgress?.call(m);
  });
  try {
    return await Isolate.run(
      () => writeAe2ZipSync(
        paths,
        names,
        password,
        outputPath,
        onProgress: send.send,
      ),
    );
  } finally {
    await sub.cancel();
    port.close();
  }
}
