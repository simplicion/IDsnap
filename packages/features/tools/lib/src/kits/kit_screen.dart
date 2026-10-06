import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/result_sheet.dart';
import 'package:feature_tools/src/kits/kit_catalog.dart';
import 'package:feature_tools/src/kits/kit_controller.dart';
import 'package:feature_tools/src/kits/kits_hub_screen.dart';
import 'package:feature_tools/src/kits/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Guided kit: each item is picked, processed and verified, then everything
/// is saved to the library in one step.
class KitScreen extends ConsumerStatefulWidget {
  const KitScreen({required this.kitId, super.key});

  final String kitId;

  @override
  ConsumerState<KitScreen> createState() => _KitScreenState();
}

class _KitScreenState extends ConsumerState<KitScreen> {
  String get kitId => widget.kitId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(saveFolderProvider(kitSaveFlow(kitId)).notifier).start(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final kit = ref.watch(kitByIdProvider(kitId));
    if (kit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Kit not found',
          message: 'It may have been renamed in an update.',
        ),
      );
    }
    final state = ref.watch(kitControllerProvider(kitId));
    final controller = ref.read(kitControllerProvider(kitId).notifier);

    final body = switch (state.save) {
      KitSaving(:final progress) => ProgressPanel(
        label: 'Saving to ID Vault…',
        progress: progress,
      ),
      KitSaved(:final documents) => ResultSheet(
        documents: documents,
        onStartOver: controller.reset,
      ),
      KitSaveFailed(:final failure) => FailureView(
        failure,
        onRetry: controller.dismissSaveError,
      ),
      KitSaveIdle() => _KitBody(kit: kit, state: state),
    };

    final ready = state.readyIds.length;
    final showSave = state.save is KitSaveIdle;
    return PopScope(
      canPop: !state.busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(kit.label),
          actions: [
            if (kit.id == customKitId && showSave)
              IconButton(
                tooltip: 'Edit limits',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => _editCustomKit(context, ref),
              ),
          ],
        ),
        body: AnimatedSwitcher(duration: Motion.medium, child: body),
        bottomNavigationBar: showSave
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.x2,
                  Space.gutter,
                  Space.x3,
                ),
                child: FilledButton.icon(
                  onPressed: ready == 0 || state.busy
                      ? null
                      : () => unawaited(controller.saveAll()),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(
                    ready == 0
                        ? 'Prepare an item to save'
                        : ready == kit.items.length
                        ? 'Save all to ID Vault'
                        : 'Save $ready of ${kit.items.length} to ID Vault',
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _KitBody extends StatelessWidget {
  const _KitBody({required this.kit, required this.state});

  final ApplicationKit kit;
  final KitState state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x2,
      Space.gutter,
      Space.x10,
    ),
    children: [
      Row(
        children: [
          IconBadge(kitIcon(kit.id), color: context.colors.secondary),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Text(kit.description, style: context.text.bodyMedium),
          ),
        ],
      ),
      const SizedBox(height: Space.x3),
      FidelityNote(
        label: 'Check the latest official requirements',
        explanation:
            "IDSnap prepares files to these limits but can't guarantee a "
            'portal will accept them.',
        limitations: [
          'Source: ${kit.source}',
          'Last reviewed: ${kit.reviewedOn}',
        ],
      ),
      const SizedBox(height: Space.x4),
      for (final (i, item) in kit.items.indexed) ...[
        _ItemCard(
          kitId: kit.id,
          step: i + 1,
          item: item,
          state: state.of(item.id),
        ),
        const SizedBox(height: Space.x3),
      ],
      SaveFolderField(flow: kitSaveFlow(kit.id), enabled: !state.busy),
    ],
  );
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.kitId,
    required this.step,
    required this.item,
    required this.state,
  });

  final String kitId;
  final int step;
  final KitItem item;
  final KitItemState state;

  IconData get _icon => switch (item) {
    PhotoItem() => Icons.face_rounded,
    SignatureItem() => Icons.draw_rounded,
    DocumentItem() => Icons.picture_as_pdf_rounded,
  };

  String get _pickLabel => switch (item) {
    PhotoItem() => 'Choose photo',
    SignatureItem() => 'Choose signature photo',
    DocumentItem() => 'Choose files',
  };

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(mediaPickerProvider);
    final controller = ref.read(kitControllerProvider(kitId).notifier);
    final item = this.item;
    final picked = switch (item) {
      PhotoItem() ||
      SignatureItem() => await picker.pickImages(multiple: false),
      DocumentItem() => await picker.pickFiles(const {
        DocumentFormat.pdf,
        DocumentFormat.jpeg,
        DocumentFormat.png,
        DocumentFormat.webp,
      }, multiple: true),
    };
    if (picked case Err(:final failure)) {
      if (context.mounted) showFailureSnack(context, failure);
      return;
    }
    final files = picked.valueOrNull!;
    if (files.isEmpty) return;
    switch (item) {
      case PhotoItem():
        await controller.processPhoto(item, files.first);
      case SignatureItem():
        await controller.processSignature(item, files.first);
      case DocumentItem():
        await controller.processDocuments(item, files);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = state is KitItemReady;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  done ? Icons.check_rounded : _icon,
                  color: done ? context.ds.success : null,
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Step $step · ${item.label}',
                      style: context.text.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x3),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [for (final c in constraintLabels(item)) Pill(c)],
            ),
            if (item.hint != null) ...[
              const SizedBox(height: Space.x2),
              Text(
                item.hint!,
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: Space.x3),
            switch (state) {
              KitItemEmpty() => OutlinedButton.icon(
                onPressed: () => unawaited(_pick(context, ref)),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_pickLabel),
              ),
              KitItemWorking(:final progress) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: Space.x2),
                  Text('Preparing…', style: context.text.bodySmall),
                ],
              ),
              KitItemReady(:final output, :final sourceName) => _Ready(
                output: output,
                sourceName: sourceName,
                onReplace: () => unawaited(_pick(context, ref)),
              ),
              KitItemNotice(:final message) => _Problem(
                title: "Couldn't meet the limit",
                message: message,
                onRetry: () => unawaited(_pick(context, ref)),
              ),
              KitItemFailed(:final failure) => _Problem(
                title: failure.title,
                message: [
                  if (failure.detail != null) failure.detail!,
                  failure.recovery,
                ].join(' '),
                onRetry: () => unawaited(_pick(context, ref)),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.output,
    required this.sourceName,
    required this.onReplace,
  });

  final KitOutput output;
  final String sourceName;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: Radii.smAll,
            child: SizedBox(
              width: 72,
              height: 72,
              child: output.format == DocumentFormat.pdf
                  ? ColoredBox(
                      color: context.ds.pdf.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: context.ds.pdf,
                      ),
                    )
                  : Image.memory(
                      output.bytes,
                      fit: BoxFit.contain,
                      semanticLabel: 'Prepared image preview',
                    ),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From $sourceName',
                  style: context.text.bodySmall?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.x1),
                for (final check in output.checks) _CheckRow(check),
              ],
            ),
          ),
        ],
      ),
      if (output.backgroundWarning)
        const _Hint(
          icon: Icons.wallpaper_rounded,
          text:
              'Background may not be plain. Many portals require a white or '
              'light, even background.',
        ),
      if (output.compressedPdf)
        const _Hint(
          icon: Icons.info_outline_rounded,
          text:
              'Pages were compressed to fit the limit, so text in this PDF '
              "can't be selected.",
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onReplace,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Replace'),
        ),
      ),
    ],
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.check);

  final KitCheck check;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Semantics(
      label: '${check.passed ? 'Passed' : 'Not met'}: ${check.label}',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(
            check.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: check.passed ? context.ds.success : context.colors.error,
          ),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(check.label, style: context.text.bodyMedium)),
        ],
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.ds.warning),
        const SizedBox(width: Space.x2),
        Expanded(child: Text(text, style: context.text.bodySmall)),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.x3),
    decoration: BoxDecoration(
      color: context.colors.errorContainer.withValues(alpha: 0.5),
      borderRadius: Radii.buttonAll,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleSmall),
        const SizedBox(height: Space.x1),
        Text(message, style: context.text.bodySmall),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onRetry,
            child: const Text('Choose another file'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _editCustomKit(BuildContext context, WidgetRef ref) async {
  final current = ref.read(customKitProvider);
  var preset = CropPreset.passportIntl;
  var photoKb = 100;
  int? signatureKb;
  var documentKb = 500;
  for (final item in current.items) {
    switch (item) {
      case PhotoItem(preset: final p, :final maxBytes):
        photoKb = maxBytes ~/ 1024;
        preset = p;
      case SignatureItem(:final maxBytes):
        signatureKb = maxBytes ~/ 1024;
      case DocumentItem(:final maxBytes):
        documentKb = maxBytes ~/ 1024;
    }
  }
  final photo = TextEditingController(text: '$photoKb');
  final signature = TextEditingController(text: '${signatureKb ?? 20}');
  final documents = TextEditingController(text: '$documentKb');
  var includeSignature = signatureKb != null;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          MediaQuery.viewInsetsOf(context).bottom + Space.x4,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Custom limits', style: context.text.titleLarge),
              const SizedBox(height: Space.x4),
              DropdownButtonFormField<CropPreset>(
                initialValue: preset,
                decoration: const InputDecoration(labelText: 'Photo size'),
                items: [
                  for (final p in CropPreset.all)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${p.label} (${p.sizeLabel})'),
                    ),
                ],
                onChanged: (p) => setState(() => preset = p ?? preset),
              ),
              const SizedBox(height: Space.x3),
              _KbField(controller: photo, label: 'Photo limit (KB)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include a signature'),
                value: includeSignature,
                onChanged: (v) => setState(() => includeSignature = v),
              ),
              if (includeSignature)
                _KbField(controller: signature, label: 'Signature limit (KB)'),
              const SizedBox(height: Space.x3),
              _KbField(controller: documents, label: 'Document PDF limit (KB)'),
              const SizedBox(height: Space.x5),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use these limits'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (saved ?? false) {
    int kb(TextEditingController c, int fallback) =>
        (int.tryParse(c.text.trim()) ?? fallback).clamp(5, 100 * 1024);
    ref
        .read(customKitProvider.notifier)
        .update(
          preset: preset,
          photoKb: kb(photo, 100),
          signatureKb: includeSignature ? kb(signature, 20) : null,
          documentKb: kb(documents, 500),
        );
    ref.read(kitControllerProvider(customKitId).notifier).reset();
  }
  photo.dispose();
  signature.dispose();
  documents.dispose();
}

class _KbField extends StatelessWidget {
  const _KbField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: 'KB'),
  );
}
