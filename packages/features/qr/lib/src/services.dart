import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// Feature-local seams. The app overrides the scanner in its bootstrap;
// tests override everything with fakes.

/// Live camera state shared between the scan screen and the preview.
class CodeScannerController {
  /// Torch requested on/off.
  final torch = ValueNotifier<bool>(false);

  /// Camera paused (a result screen is on top).
  final paused = ValueNotifier<bool>(false);

  /// Set by the preview when the device has no torch.
  final torchAvailable = ValueNotifier<bool>(true);

  void dispose() {
    torch.dispose();
    paused.dispose();
    torchAvailable.dispose();
  }
}

/// Camera + image barcode decoding, implemented in the app with the bundled
/// on-device model (no network). The default reports "unavailable" so the
/// picture path is always offered.
abstract interface class CodeScanner {
  Future<EngineCapability> capability();

  /// A live preview that reports every code in view (all supported
  /// symbologies) via [onDetect], follows [controller] (torch, pause) and
  /// calls [onError] when the camera can't start.
  Widget buildPreview(
    BuildContext context, {
    required CodeScannerController controller,
    required ValueChanged<List<ScannedCode>> onDetect,
    required ValueChanged<AppFailure> onError,
  });

  /// Every code found in the image at [path] (empty when there is none).
  Future<Result<List<ScannedCode>>> decodeImage(String path);
}

class UnavailableCodeScanner implements CodeScanner {
  const UnavailableCodeScanner();

  @override
  Future<EngineCapability> capability() async => const EngineCapability(
    available: false,
    worksOffline: true,
    note: 'The camera scanner is not available on this device.',
  );

  @override
  Widget buildPreview(
    BuildContext context, {
    required CodeScannerController controller,
    required ValueChanged<List<ScannedCode>> onDetect,
    required ValueChanged<AppFailure> onError,
  }) => const SizedBox.expand();

  @override
  Future<Result<List<ScannedCode>>> decodeImage(String path) async =>
      const Err(AppFailure(FailureCode.cameraUnavailable));
}

final codeScannerProvider = Provider<CodeScanner>(
  (ref) => const UnavailableCodeScanner(),
);

/// Everything the result and generator screens do outside the app. Every
/// call is user-initiated. Links are handed to other apps; this app never
/// opens a network connection itself.
abstract interface class QrActions {
  Future<Result<void>> copy(String text);
  Future<Result<void>> shareText(String text);

  /// Writes [bytes] to a temporary `.<extension>` file and opens the share
  /// sheet (contacts and calendar apps accept `.vcf` / `.ics`).
  Future<Result<void>> shareFile(
    Uint8List bytes, {
    required String extension,
    String? subject,
  });

  /// "Save to device" picker. False when cancelled.
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName);

  /// Adds a file to the ID Vault, into [folderId] (`null` = top level).
  Future<Result<Document>> saveToVault(
    Uint8List bytes, {
    required DocumentFormat format,
    required String name,
    String? folderId,
  });

  /// Hands [uri] to the app that handles it (browser, mail, phone, maps).
  /// False when no app accepted it.
  Future<bool> open(Uri uri);
}

class PlatformQrActions implements QrActions {
  PlatformQrActions(this._ref);

  final Ref _ref;

  ShareService get _share => _ref.read(shareServiceProvider);

  @override
  Future<Result<void>> copy(String text) => _share.copyText(text);

  @override
  Future<Result<void>> shareText(String text) => _share.shareText(text);

  @override
  Future<Result<void>> shareFile(
    Uint8List bytes, {
    required String extension,
    String? subject,
  }) async {
    final String path;
    try {
      path = await _ref.read(fileStoreProvider).writeTemp(bytes, extension);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }
    return await _share.share([path], subject: subject);
  }

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) =>
      _share.saveToDevice(bytes, fileName);

  @override
  Future<Result<Document>> saveToVault(
    Uint8List bytes, {
    required DocumentFormat format,
    required String name,
    String? folderId,
  }) async => await _ref
      .read(commitOutputProvider)
      .call(
        OutputFile(bytes: bytes, format: format, suggestedName: name),
        folderId: await existingSaveFolder(
          () => _ref.read(folderRepositoryProvider),
          folderId,
        ),
      );

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

final qrActionsProvider = Provider<QrActions>(PlatformQrActions.new);

/// [saveFolderProvider] key of the QR tool's "Save to ID Vault" actions.
const qrSaveFlow = 'qr';

/// Asks where to save in the ID Vault (default: the last choice). Returns
/// false when dismissed; the choice is in [saveFolderProvider] of
/// [qrSaveFlow].
Future<bool> pickQrSaveFolder(BuildContext context, WidgetRef ref) async {
  final pick = await pickSaveFolder(
    context,
    initial: ref.read(saveFolderProvider(qrSaveFlow)),
  );
  if (pick == null || !context.mounted) return false;
  ref.read(saveFolderProvider(qrSaveFlow).notifier).choose(pick.folderId);
  return true;
}

/// Apple platforms open maps links through Apple Maps; others use `geo:`.
final useAppleMapsProvider = Provider<bool>(
  (ref) =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS,
);
