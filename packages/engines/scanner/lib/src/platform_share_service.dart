import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// OS share sheet, "Save to device" (system save dialog) and clipboard.
/// Every action is user-initiated; nothing is uploaded by DocScan itself.
class PlatformShareService implements ShareService {
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
