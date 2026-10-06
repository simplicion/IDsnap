import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> shareDocument(
  BuildContext context,
  WidgetRef ref,
  Document doc,
) async {
  final files = ref.read(fileStoreProvider);
  final share = ref.read(shareServiceProvider);
  try {
    final path = await files.exportCopy(doc.relativePath, doc.fileName);
    final result = await share.share([path], subject: doc.name);
    // Shred the decrypted copy once the target app had time to read it
    // (and at the next launch otherwise; ADR-0010).
    await ref
        .read(plainFileAccessProvider)
        .releaseTemp(path, grace: const Duration(minutes: 2));
    if (!context.mounted) return;
    if (result case Err(:final failure)) showFailureSnack(context, failure);
  } on Object catch (e) {
    if (context.mounted) {
      showFailureSnack(
        context,
        AppFailure(
          FailureCode.unknown,
          cause: e,
          message:
              "Couldn't open the share sheet. The file is saved in ID "
              'Vault; try sharing it from there.',
        ),
      );
    }
  }
}

Future<void> saveDocumentToDevice(
  BuildContext context,
  WidgetRef ref,
  Document doc,
) async {
  final files = ref.read(fileStoreProvider);
  try {
    final bytes = await files.read(files.absolute(doc.relativePath));
    final result = await ref
        .read(shareServiceProvider)
        .saveToDevice(bytes, doc.fileName);
    if (!context.mounted) return;
    result.fold((saved) {
      if (saved) showAppSnack(context, 'Saved ${doc.fileName}');
    }, (f) => showFailureSnack(context, f));
  } on Object catch (e) {
    if (context.mounted) {
      showFailureSnack(
        context,
        AppFailure(
          FailureCode.unknown,
          cause: e,
          message:
              "The file couldn't be saved to this phone's storage. It is "
              'still in ID Vault; try again or use Share.',
        ),
      );
    }
  }
}

/// Success panel shown only after outputs were validated and saved.
class ResultSheet extends ConsumerWidget {
  const ResultSheet({
    required this.documents,
    super.key,
    this.summary,
    this.onStartOver,
    this.showAds = true,
  });

  final List<Document> documents;
  final Widget? summary;
  final VoidCallback? onStartOver;

  /// False inside a bottom sheet: sheets and dialogs never show ads.
  /// Elsewhere the placement policy decides per screen (ADR-0013).
  final bool showAds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final many = documents.length > 1;
    final location = showAds ? routeLocationOf(context) : null;
    return PopScope(
      // The one interstitial moment in the app: the job is finished, its
      // files are saved and listed here, and the user is leaving this
      // panel (Done or back). The placement policy and the frequency caps
      // decide; nothing waits for an ad.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) maybeShowResultInterstitial(ref, location);
      },
      child: _content(context, many),
    );
  }

  Widget _content(BuildContext context, bool many) {
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.x4),
        Center(
          child: IconBadge(
            Icons.check_circle_rounded,
            color: context.ds.success,
            size: 72,
          ),
        ),
        const SizedBox(height: Space.x4),
        Text(
          many ? '${documents.length} files saved' : 'File saved',
          style: context.text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.x1),
        // The real destination folder (all outputs of one run share it).
        if (documents.isNotEmpty)
          SavedToFolderText(
            documents.first.folderId,
            style: context.text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        Text(
          'Stored on this device only.',
          style: context.text.bodyMedium?.copyWith(
            color: context.ds.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        if (summary != null) ...[const SizedBox(height: Space.x5), summary!],
        const SizedBox(height: Space.x5),
        for (final doc in documents) _ResultRow(doc: doc),
        const SizedBox(height: Space.x4),
        if (onStartOver != null)
          OutlinedButton.icon(
            onPressed: onStartOver,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Start over'),
          ),
        const SizedBox(height: Space.x2),
        TextButton(
          onPressed: () => context.canPop() ? context.pop() : null,
          child: const Text('Done'),
        ),
        // One labelled ad card below the result and its buttons, with
        // space around it. Zero height unless an ad is already loaded.
        if (showAds)
          const AdNativeSlot(placement: AdNativePlacement.toolResult),
      ],
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = formatVisual(context, doc.format);
    final details = [
      doc.format.label,
      formatBytes(doc.sizeBytes),
      if (doc.pageCount != null)
        '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(v.icon, color: v.color),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          style: context.text.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          details,
                          style: context.text.bodySmall?.copyWith(
                            color: context.ds.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push(Routes.document(doc.id)),
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('Open'),
                  ),
                  TextButton.icon(
                    onPressed: () => shareDocument(context, ref, doc),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share'),
                  ),
                  TextButton.icon(
                    onPressed: () => saveDocumentToDevice(context, ref, doc),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Save to device'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet variant of [ResultSheet].
Future<void> showResultSheet(BuildContext context, List<Document> documents) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: ResultSheet(documents: documents, showAds: false),
      ),
    );
