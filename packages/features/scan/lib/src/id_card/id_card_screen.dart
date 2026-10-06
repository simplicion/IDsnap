import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/id_card/id_card_controller.dart';
import 'package:feature_scan/src/id_card/layout.dart';
import 'package:feature_scan/src/preview_cache.dart';
import 'package:feature_scan/src/widgets/quad_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ID card front & back on one page: front → back → preview → save.
class IdCardScreen extends ConsumerStatefulWidget {
  const IdCardScreen({super.key, this.slot, this.folderId});

  /// [VaultSlot.key] when started from a vault slot (legacy, unused).
  final String? slot;

  /// ID Vault folder the flow was started from (the folder "+" menu); the
  /// default "Save to" destination.
  final String? folderId;

  @override
  ConsumerState<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends ConsumerState<IdCardScreen> {
  IdCardFlowController get _flow => ref.read(idCardFlowProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flow.start(slot: widget.slot);
      ref
          .read(saveFolderProvider(idCardSaveFlow).notifier)
          .start(widget.folderId);
    });
  }

  Future<void> _capture(IdSide side, {required bool camera}) async {
    final failure = camera
        ? await _flow.captureWithCamera(side)
        : await _flow.captureFromPhotos(side);
    if (failure != null && mounted) showFailureSnack(context, failure);
  }

  Future<void> _adjust(IdSide side) async {
    final capture = ref.read(idCardFlowProvider).side(side);
    if (capture == null) return;
    final quad = await Navigator.of(context).push<Quad>(
      MaterialPageRoute(
        builder: (_) => IdCornerEditor(
          originalPath: capture.originalPath,
          initial: capture.quad ?? Quad.full,
          sideLabel: side.label,
        ),
      ),
    );
    if (quad == null || !mounted) return;
    final failure = await _flow.setQuad(side, quad);
    if (failure != null && mounted) showFailureSnack(context, failure);
  }

  Future<void> _share(Document doc) async {
    try {
      final path = await ref
          .read(fileStoreProvider)
          .exportCopy(doc.relativePath, doc.fileName);
      final plain = ref.read(plainFileAccessProvider);
      final r = await ref.read(shareServiceProvider).share([
        path,
      ], subject: doc.name);
      // Shred the decrypted copy after the target app had time to read it
      // (and at the next launch otherwise; ADR-0010).
      await plain.releaseTemp(path, grace: const Duration(minutes: 2));
      if (!mounted) return;
      if (r case Err(:final failure)) showFailureSnack(context, failure);
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

  void _back(IdCardFlowState s) {
    switch (s.step) {
      case IdCardStep.back:
        _flow.retake(IdSide.front);
      case IdCardStep.preview:
        _flow.retake(IdSide.back);
      case IdCardStep.front:
        unawaited(_leave(s));
    }
  }

  Future<void> _leave(IdCardFlowState s) async {
    if (s.hasAnyCapture && s.save is! IdCardSaved) {
      final ok = await confirmAction(
        context,
        title: 'Discard this ID card copy?',
        message: 'The photos you took for this copy will be deleted.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!ok) return;
      await _flow.discard();
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(idCardFlowProvider);
    final saving = s.save is IdCardSaving;
    final saved = s.save is IdCardSaved;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || saving) return;
        if (saved) {
          context.go(Routes.home);
        } else {
          _back(s);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: saving
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: saved ? 'Close' : 'Back',
                  icon: Icon(
                    saved || s.step == IdCardStep.front
                        ? Icons.close_rounded
                        : Icons.arrow_back_rounded,
                  ),
                  onPressed: () => saved ? context.go(Routes.home) : _back(s),
                ),
          title: Text(saved ? 'Saved' : 'ID card copy'),
          bottom: saved || saving
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: _StepIndicator(step: s.step),
                ),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: Motion.medium,
            child: switch (s.save) {
              IdCardSaving() => const ProgressPanel(
                key: ValueKey('saving'),
                label: 'Creating your ID card PDF…',
              ),
              IdCardSaved(:final document) => _Success(
                key: const ValueKey('saved'),
                document: document,
                onOpen: () => context.go(Routes.document(document.id)),
                onShare: () => _share(document),
                onDone: () => context.go(Routes.home),
              ),
              IdCardSaveFailed(:final failure) => FailureView(
                failure,
                key: const ValueKey('failed'),
                onRetry: _flow.resetSave,
              ),
              IdCardSaveIdle() => switch (s.step) {
                IdCardStep.front => _CaptureStep(
                  key: const ValueKey('front'),
                  side: IdSide.front,
                  state: s,
                  onCapture: _capture,
                ),
                IdCardStep.back => _CaptureStep(
                  key: const ValueKey('back'),
                  side: IdSide.back,
                  state: s,
                  onCapture: _capture,
                ),
                IdCardStep.preview => _PreviewStep(
                  key: const ValueKey('preview'),
                  state: s,
                  layout: _flow.currentLayout(),
                  onAdjust: _adjust,
                  onRetake: _flow.retake,
                  onSave: () => unawaited(_flow.save()),
                ),
              },
            },
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final IdCardStep step;

  @override
  Widget build(BuildContext context) {
    final label = switch (step) {
      IdCardStep.front => 'Step 1 of 2 · Front',
      IdCardStep.back => 'Step 2 of 2 · Back',
      IdCardStep.preview => 'Review and save',
    };
    final value = switch (step) {
      IdCardStep.front => 1 / 3,
      IdCardStep.back => 2 / 3,
      IdCardStep.preview => 1.0,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.x2,
      ),
      child: Row(
        children: [
          Flexible(
            flex: 3,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: value, minHeight: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureStep extends StatelessWidget {
  const _CaptureStep({
    required this.side,
    required this.state,
    required this.onCapture,
    super.key,
  });

  final IdSide side;
  final IdCardFlowState state;
  final Future<void> Function(IdSide side, {required bool camera}) onCapture;

  @override
  Widget build(BuildContext context) {
    final front = side == IdSide.front;
    final busy = state.busy == side;
    final announcement = front
        ? 'Step 1 of 2, front of card'
        : 'Step 2 of 2, back of card';
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Semantics(
          liveRegion: true,
          label: announcement,
          child: ExcludeSemantics(
            child: Text(
              front ? 'Scan the front of your card' : 'Now flip the card over',
              style: context.text.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: Space.x2),
        Text(
          front
              ? 'Place the card on a plain, contrasting surface. We find the '
                    'edges and straighten it for you.'
              : 'Scan the back the same way. Both sides go on one page.',
          style: context.text.bodyMedium?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
        const SizedBox(height: Space.x6),
        _CardFrame(
          label: side.label,
          busy: busy,
          image: state.side(side)?.rendered,
        ),
        if (!front && state.front != null) ...[
          const SizedBox(height: Space.x4),
          Row(
            children: [
              ClipRRect(
                borderRadius: Radii.smAll,
                child: Image.memory(
                  state.front!.rendered,
                  width: 64,
                  height: 40,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  semanticLabel: 'Front of card',
                ),
              ),
              const SizedBox(width: Space.x3),
              Icon(Icons.check_circle_rounded, color: context.ds.success),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text('Front captured', style: context.text.bodyMedium),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.x6),
        FilledButton.icon(
          onPressed: busy ? null : () => onCapture(side, camera: true),
          icon: const Icon(Icons.document_scanner_rounded),
          label: Text('Scan ${side.label.toLowerCase()}'),
        ),
        const SizedBox(height: Space.x3),
        OutlinedButton.icon(
          onPressed: busy ? null : () => onCapture(side, camera: false),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from photos'),
        ),
        const SizedBox(height: Space.x6),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: context.ds.success,
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                'Processed on this phone. Nothing is uploaded.',
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Card-shaped (ID-1) frame: a dashed outline, the captured image, or a
/// spinner while the side is being prepared.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.label, required this.busy, this.image});

  final String label;
  final bool busy;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: idCardAspect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: Radii.cardAll,
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: ClipRRect(
              borderRadius: Radii.cardAll,
              child: busy
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: Space.x3),
                          Text(
                            'Preparing ${label.toLowerCase()}…',
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  : image != null
                  ? Image.memory(
                      image!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: '$label of card',
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 48,
                            color: scheme.primary,
                          ),
                          const SizedBox(height: Space.x2),
                          Text(
                            label.toUpperCase(),
                            style: context.text.labelLarge?.copyWith(
                              color: scheme.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewStep extends StatefulWidget {
  const _PreviewStep({
    required this.state,
    required this.layout,
    required this.onAdjust,
    required this.onRetake,
    required this.onSave,
    super.key,
  });

  final IdCardFlowState state;
  final IdCardSheetLayout? layout;
  final Future<void> Function(IdSide side) onAdjust;
  final void Function(IdSide side) onRetake;
  final VoidCallback onSave;

  @override
  State<_PreviewStep> createState() => _PreviewStepState();
}

class _PreviewStepState extends State<_PreviewStep> {
  late final TextEditingController _purpose = TextEditingController(
    text: widget.state.purpose,
  );

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final layout = widget.layout;
    return Consumer(
      builder: (context, ref, _) {
        final flow = ref.read(idCardFlowProvider.notifier);
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Space.gutter),
                children: [
                  if (layout != null)
                    _SheetPreview(
                      layout: layout,
                      watermark: s.watermarkText,
                      busy: s.busy != null,
                    ),
                  const SizedBox(height: Space.x2),
                  Text(
                    'Copy of your card on one A4 page. '
                    'Not a certified or official copy.',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  for (final side in IdSide.values)
                    if (s.side(side)?.needsCheck ?? false)
                      _CheckCorners(
                        side: side,
                        onAdjust: () => widget.onAdjust(side),
                      ),
                  const _Label('Layout'),
                  SegmentedButton<IdCardLayout>(
                    showSelectedIcon: false,
                    segments: [
                      for (final l in IdCardLayout.values)
                        ButtonSegment(value: l, label: Text(l.label)),
                    ],
                    selected: {s.layout},
                    onSelectionChanged: (v) => flow.setLayout(v.first),
                  ),
                  const _Label('Size'),
                  SegmentedButton<IdCardSizing>(
                    showSelectedIcon: false,
                    segments: [
                      for (final z in IdCardSizing.values)
                        ButtonSegment(value: z, label: Text(z.label)),
                    ],
                    selected: {s.sizing},
                    onSelectionChanged: (v) => flow.setSizing(v.first),
                  ),
                  const SizedBox(height: Space.x1),
                  Text(
                    s.sizing.hint,
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  const _Label('Protect this copy'),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: s.watermark,
                          onChanged: (v) => flow.setWatermark(enabled: v),
                          secondary: const Icon(Icons.water_drop_outlined),
                          title: const Text('Add "COPY" watermark'),
                          subtitle: const Text(
                            'A faint label across the page helps prevent misuse.',
                          ),
                        ),
                        if (s.watermark)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.x4,
                              0,
                              Space.x4,
                              Space.x4,
                            ),
                            child: TextField(
                              controller: _purpose,
                              onChanged: flow.setPurpose,
                              maxLength: 40,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Purpose (optional)',
                                hintText: 'e.g. bank KYC',
                                helperText:
                                    'Shows as "COPY — for bank KYC only"',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.x4),
                  SaveFolderField(
                    flow: idCardSaveFlow,
                    enabled: s.busy == null,
                  ),
                  const SizedBox(height: Space.x4),
                  Wrap(
                    spacing: Space.x3,
                    runSpacing: Space.x3,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final side in IdSide.values)
                        OutlinedButton.icon(
                          onPressed: () => widget.onRetake(side),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('Retake ${side.label.toLowerCase()}'),
                        ),
                    ],
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
                  onPressed: s.canSave && s.busy == null ? widget.onSave : null,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Save PDF'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CheckCorners extends StatelessWidget {
  const _CheckCorners({required this.side, required this.onAdjust});

  final IdSide side;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x3),
    child: Container(
      padding: const EdgeInsets.fromLTRB(
        Space.x3,
        Space.x2,
        Space.x1,
        Space.x2,
      ),
      decoration: BoxDecoration(
        color: context.ds.warningContainer,
        borderRadius: Radii.buttonAll,
      ),
      child: Row(
        children: [
          Icon(Icons.crop_free_rounded, color: context.ds.warning, size: 20),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Check corners: the ${side.label.toLowerCase()} may not be '
              'cropped to the card edges.',
              style: context.text.bodySmall,
            ),
          ),
          TextButton(onPressed: onAdjust, child: const Text('Adjust')),
        ],
      ),
    ),
  );
}

/// Scaled on-screen preview of the exact page layout that will be saved.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({
    required this.layout,
    required this.busy,
    this.watermark,
  });

  final IdCardSheetLayout layout;
  final String? watermark;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
      child: AspectRatio(
        aspectRatio: layout.pageWidthPt / layout.pageHeightPt,
        child: Semantics(
          label: 'Preview of the page with front and back of the card',
          child: LayoutBuilder(
            builder: (context, c) {
              final k = c.maxWidth / layout.pageWidthPt;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: Radii.smAll,
                  border: Border.all(color: context.ds.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    for (final img in layout.images)
                      Positioned(
                        left: img.left * k,
                        top: img.top * k,
                        width: img.width * k,
                        height: img.height * k,
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF9EA3AD),
                              width: 0.5,
                            ),
                          ),
                          child: Image.memory(
                            img.jpeg,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    if (watermark != null)
                      Positioned.fill(
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.6,
                            child: Text(
                              watermark!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.14),
                                fontWeight: FontWeight.w800,
                                fontSize: c.maxWidth / 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66FFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
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
              'ID card copy saved',
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
              '1 page · ${formatBytes(document.sizeBytes)}',
              style: context.text.bodySmall?.copyWith(color: ds.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.x1),
            SavedToFolderText(
              document.folderId,
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

/// Full-screen corner editor for one card side; pops with the new [Quad].
class IdCornerEditor extends ConsumerStatefulWidget {
  const IdCornerEditor({
    required this.originalPath,
    required this.initial,
    required this.sideLabel,
    super.key,
  });

  final String originalPath;
  final Quad initial;
  final String sideLabel;

  @override
  ConsumerState<IdCornerEditor> createState() => _IdCornerEditorState();
}

class _IdCornerEditorState extends ConsumerState<IdCornerEditor> {
  late Quad _quad = widget.initial;
  late final Future<(Uint8List, Size)?> _source = _load();

  Future<(Uint8List, Size)?> _load() async {
    final bytes = await ref
        .read(previewCacheProvider)
        .cropSource(widget.originalPath);
    if (bytes == null) return null;
    return (bytes, await decodeImageSize(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final problem = validateQuad(_quad);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1013),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1013),
        foregroundColor: Colors.white,
        title: Text('Adjust ${widget.sideLabel.toLowerCase()} corners'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.x3),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: problem == null
                  ? () => Navigator.of(context).pop(_quad)
                  : null,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<(Uint8List, Size)?>(
                future: _source,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snap.data;
                  if (data == null) {
                    return const FailureView(
                      AppFailure(FailureCode.corruptFile),
                    );
                  }
                  return QuadEditor(
                    image: data.$1,
                    imageSize: data.$2,
                    quad: _quad,
                    onChanged: (q) => setState(() => _quad = q),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.x3),
              child: Row(
                children: [
                  if (problem != null)
                    Expanded(
                      child: Text(
                        problem,
                        style: context.text.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => setState(() => _quad = Quad.full),
                    child: const Text('Full photo'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => setState(() => _quad = widget.initial),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
