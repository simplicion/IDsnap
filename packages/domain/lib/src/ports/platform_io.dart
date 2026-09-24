import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/conversion.dart';

class PickedFile {
  const PickedFile({required this.path, required this.name});

  /// Absolute, app-readable path (picker cache).
  final String path;

  /// Original file name including extension.
  final String name;

  String get baseName =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
}

/// System pickers. Uses scoped pickers (Android Photo Picker, iOS PHPicker)
/// so no broad storage permission is needed.
abstract interface class MediaPicker {
  /// Empty list when the user cancels.
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true});

  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  });
}

/// Share sheet and "save to device". Sharing is always user-initiated.
abstract interface class ShareService {
  Future<Result<void>> share(List<String> absolutePaths, {String? subject});

  Future<Result<void>> shareText(String text);

  /// Lets the user pick a destination (Files / Downloads). Returns false when
  /// the user cancels.
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName);

  Future<Result<void>> copyText(String text);
}

/// Runs a registered conversion. Implemented by `engine_conversion`.
abstract interface class ConversionEngine {
  List<ConversionSpec> get specs;

  ConversionSpec? spec(String id);

  Future<Result<List<OutputFile>>> convert(
    ConversionRequest request, {
    void Function(double progress)? onProgress,
  });
}
