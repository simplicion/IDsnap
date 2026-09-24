import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// System pickers. Images go through `image_picker` (Android Photo Picker /
/// iOS PHPicker — no storage permission needed); `imageQuality` makes iOS
/// transcode HEIC to JPEG. Other files go through `file_picker`.
class PlatformMediaPicker implements MediaPicker {
  PlatformMediaPicker({ImagePicker? imagePicker})
    : _images = imagePicker ?? ImagePicker();

  final ImagePicker _images;

  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async {
    try {
      final List<XFile> files;
      if (multiple) {
        files = await _images.pickMultiImage(imageQuality: 95);
      } else {
        final one = await _images.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
        files = one == null ? const [] : [one];
      }
      return Ok([
        for (final f in files) PickedFile(path: f.path, name: f.name),
      ]);
    } on PlatformException catch (e, st) {
      return Err(AppFailure(_mapPickerError(e.code), cause: e, stackTrace: st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.unknown, cause: e, stackTrace: st));
    }
  }

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async {
    try {
      final extensions = pickerExtensions(formats);
      final files = <fp.PlatformFile>[];
      if (multiple) {
        files.addAll(
          await fp.FilePicker.pickFiles(
            type: extensions.isEmpty ? fp.FileType.any : fp.FileType.custom,
            allowedExtensions: extensions.isEmpty ? null : extensions,
          ),
        );
      } else {
        final one = await fp.FilePicker.pickFile(
          type: extensions.isEmpty ? fp.FileType.any : fp.FileType.custom,
          allowedExtensions: extensions.isEmpty ? null : extensions,
        );
        if (one != null) files.add(one);
      }
      final out = <PickedFile>[];
      for (final f in files) {
        out.add(PickedFile(path: await _readablePath(f), name: f.name));
      }
      return Ok(out);
    } on PlatformException catch (e, st) {
      return Err(AppFailure(_mapPickerError(e.code), cause: e, stackTrace: st));
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.unknown, cause: e, stackTrace: st));
    }
  }

  /// Picker results may be `content://` URIs on Android; copy those into
  /// the cache so engines can read them by path.
  static Future<String> _readablePath(fp.PlatformFile f) async {
    final direct = f.path;
    if (direct != null && File(direct).existsSync()) return direct;
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'picked', newId()),
    );
    await dir.create(recursive: true);
    final target = p.join(dir.path, p.basename(f.name));
    await f.xFile.saveTo(target);
    return target;
  }

  static FailureCode _mapPickerError(String code) {
    final c = code.toLowerCase();
    if (c.contains('permission') || c.contains('denied')) {
      return FailureCode.permissionDenied;
    }
    return FailureCode.unknown;
  }
}

/// File extensions to offer for a set of formats (e.g. jpeg → jpg, jpeg).
List<String> pickerExtensions(Set<DocumentFormat> formats) {
  final out = <String>{};
  for (final f in formats) {
    switch (f) {
      case DocumentFormat.unknown || DocumentFormat.zip:
        continue;
      case DocumentFormat.jpeg:
        out.addAll(['jpg', 'jpeg']);
      case DocumentFormat.heic:
        out.addAll(['heic', 'heif']);
      case DocumentFormat.tiff:
        out.addAll(['tif', 'tiff']);
      case DocumentFormat.html:
        out.addAll(['html', 'htm']);
      case DocumentFormat.markdown:
        out.addAll(['md', 'markdown']);
      case _:
        out.add(f.extension);
    }
  }
  return out.toList()..sort();
}
