import 'package:docscan_core/docscan_core.dart';

// "Password-protect any file": standard formats a recipient can open with
// ordinary tools. PDFs become AES-256 encrypted PDFs (ISO 32000-2 security
// handler, revision 6); any other file goes into an AES-256 ZIP (WinZip
// AE-2). Passwords are never stored or logged: they live only in the
// request objects below for the duration of one call.

/// What the recipient may do after opening a protected PDF with the open
/// password. Restrictions only apply when an owner password is set (anyone
/// holding the owner password can lift them); standard viewers honour them,
/// but they are not a substitute for the open password.
final class PdfProtection {
  const PdfProtection({
    required this.openPassword,
    this.ownerPassword,
    this.allowPrinting = true,
    this.allowCopying = true,
    this.allowEditing = true,
  });

  /// Required to open (decrypt) the file.
  final String openPassword;

  /// Optional "permissions" password. When null, a random one is used so
  /// nobody can change the permissions, and every permission is granted.
  final String? ownerPassword;
  final bool allowPrinting;
  final bool allowCopying;
  final bool allowEditing;

  bool get restricts => !allowPrinting || !allowCopying || !allowEditing;

  @override
  String toString() => 'PdfProtection(restricts: $restricts)';
}

/// A file written by a protector, ready to share or commit.
final class ProtectedFile {
  const ProtectedFile({
    required this.path,
    required this.format,
    required this.sizeBytes,
    this.pageCount,
  });

  /// Absolute path of the output (a temp file).
  final String path;
  final DocumentFormat format;
  final int sizeBytes;

  /// Pages, for PDFs (verified by reopening with the password).
  final int? pageCount;
}

/// Password encryption and removal for PDFs. Implemented by `engine_pdf`.
///
/// Failures: `passwordProtected` when a password is needed but none was
/// given, `wrongPassword` when the given one is not correct,
/// `corruptFile`/`notFound`/`emptyFile` for unreadable inputs and
/// `outputValidationFailed` when the result could not be reopened.
abstract interface class PdfProtector {
  /// Whether [path] needs a password to open. PDFs with only an owner
  /// (permissions) password open without one and return false.
  Future<Result<bool>> needsPassword(String path);

  /// Writes an AES-256 encrypted copy of [inputPath] to [outputPath].
  /// [currentPassword] opens an input that is already protected.
  Future<Result<ProtectedFile>> protectPdf(
    String inputPath,
    PdfProtection protection, {
    required String outputPath,
    String? currentPassword,
  });

  /// Writes a copy of [inputPath] without encryption to [outputPath], using
  /// the open (or owner) [password]. Also used to unlock inputs for tools.
  Future<Result<ProtectedFile>> removePdfPassword(
    String inputPath,
    String password, {
    required String outputPath,
  });
}

/// One file to put into a protected ZIP.
final class ZipSource {
  const ZipSource({required this.path, required this.fileName});

  /// Absolute, app-readable path.
  final String path;

  /// Name inside the archive, with extension (no folders).
  final String fileName;
}

/// AES-256 encrypted ZIP (WinZip AE-2). Implemented by `engine_pdf`.
abstract interface class ProtectedZipWriter {
  /// Streams [sources] into one encrypted archive at [outputPath]; input
  /// files are read in chunks, never whole. Names are de-duplicated.
  Future<Result<ProtectedFile>> writeProtectedZip(
    List<ZipSource> sources,
    String password, {
    required String outputPath,
    void Function(double progress)? onProgress,
  });
}
