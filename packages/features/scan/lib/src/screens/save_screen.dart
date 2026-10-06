import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/save_controller.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// [saveFolderProvider] key of the scan flow.
const scanSaveFlow = 'scan';

/// Name, quality, page size, searchable text and folder → Save as PDF.
class SaveScreen extends ConsumerStatefulWidget {
  const SaveScreen({super.key, this.now});

  /// Injected clock for tests.
  final DateTime? now;

  @override
  ConsumerState<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends ConsumerState<SaveScreen> {
  late final TextEditingController _name;
  QualityPreset? _quality;
  PdfPageSize? _pageSize;
  bool? _searchable;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: defaultScanName(widget.now ?? DateTime.now()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(saveFolderProvider(scanSaveFlow).notifier)
          .start(ref.read(scanTargetFolderProvider));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings settings) async {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final folderId = await existingSaveFolder(
      () => ref.read(folderRepositoryProvider),
      ref.read(saveFolderProvider(scanSaveFlow)),
    );
    if (!mounted) return;
    unawaited(
      ref
          .read(saveScanControllerProvider.notifier)
          .save(
            SaveRequest(
              name: name.isEmpty ? defaultScanName(DateTime.now()) : name,
              quality: _quality ?? settings.quality,
              pageSize: _pageSize ?? settings.pageSize,
              searchable: _searchable ?? settings.searchablePdf,
              folderId: folderId,
            ),
          ),
    );
  }

  Future<void> _share(Document doc) async {
    try {
      final path = await ref
          .read(fileStoreProvider)
          .exportCopy(doc.relativePath, doc.fileName);
      final plain = ref.read(plainFileAccessProvider);
      final result = await ref.read(shareServiceProvider).share([
        path,
      ], subject: doc.name);
      // Shred the decrypted copy after the target app had time to read it
      // (and at the next launch otherwise; ADR-0010).
      await plain.releaseTemp(path, grace: const Duration(minutes: 2));
      if (!mounted) return;
      if (result case Err(:final failure)) showFailureSnack(context, failure);
    } on Object catch (e) {
      if (mounted) {
        showFailureSnack(
          context,
          AppFailure(
            FailureCode.unknown,
            cause: e,
            message:
                "The file couldn't be shared. It is saved in ID Vault — "
                'try sharing it again from there.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(saveScanControllerProvider);
    final settings = ref.watch(currentSettingsProvider);
    final pageCount = ref.watch(scanSessionProvider).value?.pages.length ?? 0;
    final saving = state is SaveInProgress;
    final done = state is SaveSucceeded;

    return PopScope(
      canPop: !saving && !done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && done) context.go(Routes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !saving,
          leading: done
              ? IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => context.go(Routes.home),
                )
              : null,
          title: Text(done ? 'Saved' : 'Save as PDF'),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: Motion.medium,
            child: switch (state) {
              SaveInProgress(:final progress) => ProgressPanel(
                key: const ValueKey('progress'),
                label: 'Creating your PDF…',
                progress: progress,
              ),
              SaveSucceeded(:final document) => _Success(
                key: const ValueKey('success'),
                document: document,
                onOpen: () => context.go(Routes.document(document.id)),
                onShare: () => _share(document),
                onDone: () => context.go(Routes.home),
              ),
              SaveFailed(:final failure) => FailureView(
                failure,
                key: const ValueKey('failure'),
                onRetry: () => _save(settings),
              ),
              SaveIdle() => _form(settings, pageCount),
            },
          ),
        ),
      ),
    );
  }

  Widget _form(AppSettings settings, int pageCount) {
    final quality = _quality ?? settings.quality;
    final pageSize = _pageSize ?? settings.pageSize;
    final searchable = _searchable ?? settings.searchablePdf;
    return Column(
      key: const ValueKey('form'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'File name',
                  prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                '$pageCount ${pageCount == 1 ? 'page' : 'pages'} · saved on this phone',
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
              const _Label('Quality'),
              SegmentedButton<QualityPreset>(
                showSelectedIcon: false,
                segments: [
                  for (final q in QualityPreset.values)
                    ButtonSegment(value: q, label: Text(q.label)),
                ],
                selected: {quality},
                onSelectionChanged: (s) => setState(() => _quality = s.first),
              ),
              const SizedBox(height: Space.x1),
              Text(
                quality.hint,
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
              const _Label('Page size'),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  for (final s in PdfPageSize.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: s == pageSize,
                      onSelected: (_) => setState(() => _pageSize = s),
                    ),
                ],
              ),
              const _Label('Save to'),
              const SaveFolderField(flow: scanSaveFlow),
              const _Label('Options'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: searchable,
                      onChanged: (v) => setState(() => _searchable = v),
                      secondary: const Icon(Icons.manage_search_rounded),
                      title: const Text('Make text searchable'),
                      subtitle: const Text(
                        'Recognizes text on this phone so you can search and copy it. '
                        'Works for Latin-script languages such as English.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.x2,
            Space.gutter,
            Space.x4,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: pageCount == 0 ? null : () => _save(settings),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Save PDF'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x6, bottom: Space.x2),
    child: Semantics(
      header: true,
      child: Text(text, style: context.text.titleSmall),
    ),
  );
}

class _Success extends StatelessWidget {
  const _Success({
    required this.document,
    required this.onOpen,
    required this.onShare,
    required this.onDone,
    super.key,
  });

  final Document document;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final pages = document.pageCount;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: ds.successContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 48, color: ds.success),
            ),
            const SizedBox(height: Space.x5),
            Text(
              'PDF saved',
              style: context.text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.x2),
            Text(
              document.fileName,
              style: context.text.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.x1),
            Text(
              [
                if (pages != null) '$pages ${pages == 1 ? 'page' : 'pages'}',
                formatBytes(document.sizeBytes),
                'Checked and stored on this phone',
              ].join(' · '),
              style: context.text.bodySmall?.copyWith(color: ds.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.x8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Open'),
              ),
            ),
            const SizedBox(height: Space.x3),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(height: Space.x2),
            TextButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
