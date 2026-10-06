import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// OS share sheet, "Save to device" (system save dialog) and clipboard.
/// Every action is user-initiated; nothing is uploaded by DocScan itself.
///
/// [saveFileToDevice] hands the system save dialog the file's bytes (the
/// only API `file_picker` offers), so it is limited to
/// [maxDirectSaveBytes]; larger files (big backups) go through [share],
/// which streams the file to the receiving app (Files, Drive, Quick Share).
class PlatformShareService implements ShareService, FileSaver {
  /// Largest file "Save to device" loads into memory.
  static const maxDirectSaveBytes = 64 * 1024 * 1024;

  @override
  Future<Result<bool>> saveFileToDevice(String path, String fileName) async {
    final file = File(path);
    final int length;
    try {
      length = await file.length();
    } on FileSystemException catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    if (length > maxDirectSaveBytes) {
      return const Err(
        AppFailure(
          FailureCode.memoryLimitExceeded,
          message:
              'This file is too large to save directly. Use Send to copy it '
              'to Files, Google Drive, a computer or your new phone.',
          action: FailureAction.none,
        ),
      );
    }
    return await saveToDevice(await file.readAsBytes(), fileName);
  }

  @override
  Future<Result<void>> share(List<String> absolutePaths, {String? subject}) =>
      guard(() async {
        await SharePlus.instance.share(
          ShareParams(
            files: [for (final path in absolutePaths) XFile(path)],
            subject: subject,
          ),
        );
      });

  @override
  Future<Result<void>> shareText(String text) => guard(() async {
    await SharePlus.instance.share(ShareParams(text: text));
  });

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) =>
      guard(() async {
        final uri = await fp.FilePicker.saveFile(
          fileName: fileName,
          bytes: bytes,
          mimeType: DocumentFormat.fromExtension(fileName).mimeType,
        );
        return uri != null;
      }, code: FailureCode.insufficientStorage);

  @override
  Future<Result<void>> copyText(String text) =>
      guard(() => Clipboard.setData(ClipboardData(text: text)));
}
