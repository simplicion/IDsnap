import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class SaveState {
  const SaveState();
}

final class SaveIdle extends SaveState {
  const SaveIdle();
}

final class SaveInProgress extends SaveState {
  const SaveInProgress(this.progress);
  final double? progress;
}

final class SaveSucceeded extends SaveState {
  const SaveSucceeded(this.document);
  final Document document;
}

final class SaveFailed extends SaveState {
  const SaveFailed(this.failure);
  final AppFailure failure;
}

class SaveRequest {
  const SaveRequest({
    required this.name,
    required this.quality,
    required this.pageSize,
    required this.searchable,
    this.folderId,
  });

  final String name;
  final QualityPreset quality;
  final PdfPageSize pageSize;
  final bool searchable;
  final String? folderId;
}

/// Drives Scan → PDF. Success is only reported after [SaveScanAsPdf]
/// returns `Ok`, i.e. the PDF was written, reopened and committed.
class SaveScanController extends Notifier<SaveState> {
  @override
  SaveState build() => const SaveIdle();

  Future<void> save(SaveRequest request) async {
    if (state is SaveInProgress) return;
    final draft = ref.read(scanSessionProvider).value;
    if (draft == null || draft.isEmpty) {
      state = const SaveFailed(
        AppFailure(FailureCode.notFound, detail: 'There are no pages to save.'),
      );
      return;
    }
    state = const SaveInProgress(0);
    final result = await ref
        .read(saveScanAsPdfProvider)
        .call(
          draft,
          name: request.name,
          preset: request.quality,
          options: PdfBuildOptions(pageSize: request.pageSize),
          // The invisible text layer uses a Latin font; other scripts are
          // recognized in the OCR tool instead.
          searchableScript: request.searchable ? OcrScript.latin : null,
          folderId: request.folderId,
          onProgress: (p) {
            if (ref.mounted) state = SaveInProgress(p);
          },
        );
    if (!ref.mounted) return;
    switch (result) {
      case Ok(:final value):
        await ref.read(scanSessionProvider.notifier).finishSaved();
        if (ref.mounted) state = SaveSucceeded(value);
      case Err(:final failure):
        state = SaveFailed(failure);
    }
  }

  void reset() => state = const SaveIdle();
}

final NotifierProvider<SaveScanController, SaveState>
saveScanControllerProvider =
    NotifierProvider.autoDispose<SaveScanController, SaveState>(
      SaveScanController.new,
    );

/// ID Vault folder a scan started from (`/scan?folder=`), preselected on the
/// save screen. In memory only: a scan resumed after a restart saves to the
/// top level unless the user picks a folder.
class ScanTargetFolder extends Notifier<String?> {
  @override
  String? build() => null;

  String? get folderId => state;
  set folderId(String? value) => state = value;
}

final scanTargetFolderProvider = NotifierProvider<ScanTargetFolder, String?>(
  ScanTargetFolder.new,
);

/// "Scan 2026-09-24 14.05"
String defaultScanName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}';
}
