import 'dart:typed_data';

/// App-private file storage. Layout: `documents/` (library files),
/// `originals/` (captured images), `thumbs/`, `tmp/` (work in progress).
abstract interface class FileStore {
  /// Resolves a library-relative path to an absolute one.
  String absolute(String relativePath);

  Future<Uint8List> read(String absolutePath);
  Future<String> readText(String absolutePath);
  Future<bool> exists(String absolutePath);
  Future<int> size(String absolutePath);

  /// Writes [bytes] to a fresh file in `tmp/` and returns its absolute path.
  Future<String> writeTemp(Uint8List bytes, String extension);

  /// Copies an external file (picker/scanner cache) into `originals/`.
  Future<String> importOriginal(String externalPath);

  /// Atomically moves a temp file into `documents/` and returns the new
  /// library-relative path.
  Future<String> commit(String tempPath, String extension);

  /// Writes a thumbnail and returns its library-relative path.
  Future<String> writeThumbnail(String documentId, Uint8List jpegBytes);

  /// A temp copy named `<name>.<ext>` so share targets see a friendly name.
  Future<String> exportCopy(String relativePath, String fileName);

  Future<void> delete(String absoluteOrRelativePath);

  /// Removes everything in `tmp/`.
  Future<void> clearTemp();

  /// Bytes used by library, originals and temp files.
  Future<StorageUsage> usage();
}

class StorageUsage {
  const StorageUsage({
    required this.documents,
    required this.originals,
    required this.temp,
  });

  final int documents;
  final int originals;
  final int temp;

  int get total => documents + originals + temp;
}
