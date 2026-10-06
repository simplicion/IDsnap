import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/src/passport_photo/capture_machine.dart';
import 'package:feature_scan/src/passport_photo/guide_overlay.dart';
import 'package:feature_scan/src/passport_photo/passport_dialogs.dart';
import 'package:feature_scan/src/passport_photo/passport_photo_controller.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Take passport-size photo": live camera with face checks and
/// auto-capture, then review, crop, save as JPEG or print sheet.
class PassportPhotoScreen extends ConsumerStatefulWidget {
  const PassportPhotoScreen({super.key, this.folderId});

  /// ID Vault folder the flow was started from (the folder "+" menu); the
  /// default "Save to" destination.
  final String? folderId;

  @override
  ConsumerState<PassportPhotoScreen> createState() =>
      _PassportPhotoScreenState();
}

class _PassportPhotoScreenState extends ConsumerState<PassportPhotoScreen>
    with WidgetsBindingObserver {
  PassportPhotoController get _ctrl => ref.read(passportPhotoProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(saveFolderProvider(passportPhotoSaveFlow).notifier)
          .start(widget.folderId);
      unawaited(_ctrl.start());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // `inactive` also fires for the permission prompt, so only a real
    // background/hide releases the camera.
    switch (s) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        unawaited(_ctrl.pause());
      case AppLifecycleState.resumed:
        unawaited(_ctrl.resume());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(passportPhotoProvider.select((s) => s.save), (prev, next) {
      switch (next) {
        case PassportSaved(:final document, :final sheet):
          final where = saveFolderLabel(
            ref.read(saveFolderTreeProvider).value,
            document.folderId,
          );
          showAppSnack(
            context,
            sheet ? 'Print sheet saved to $where' : 'Photo saved to $where',
            actionLabel: 'Open',
            onAction: () => context.push(Routes.document(document.id)),
          );
        case PassportSaveFailed(:final failure):
          showFailureSnack(context, failure);
        case PassportSaveIdle() || PassportSaving():
          break;
      }
    });
    final hasReview = ref.watch(
      passportPhotoProvider.select((s) => s.review != null),
    );
    return hasReview ? const _ReviewView() : const _CameraView();
  }
}

class _CameraView extends ConsumerWidget {
  const _CameraView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(passportPhotoProvider);
    final ctrl = ref.read(passportPhotoProvider.notifier);
    final failure = s.cameraFailure;
    if (s.status == CameraStatus.failed && failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Passport-size photo')),
        body: FailureView(
          failure,
          onRetry: ctrl.start,
          actions: {
            FailureAction.pickDifferentFile: () => pushIfPro(
              context,
              ref,
              ProFeature.imageTools,
              Routes.tool(ToolId.photoCrop),
            ),
          },
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Passport-size photo'),
      ),
      body: Column(
        children: [
          _PresetBar(selected: s.preset),
          Expanded(child: _PreviewArea(state: s)),
          _ControlsBar(state: s),
        ],
      ),
    );
  }
}

class _PreviewArea extends ConsumerWidget {
  const _PreviewArea({required this.state});
  final PassportPhotoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final camera = ref.watch(liveFaceCameraProvider);
    if (s.status == CameraStatus.capturing) {
      return const _Busy('Preparing your photo…');
    }
    if (s.status != CameraStatus.live) {
      return const _Busy('Starting the camera…');
    }
    final ok = s.checks.allPass && s.detectorAvailable;
    final color = ok ? Colors.greenAccent.shade400 : Colors.white;
    final phase = s.phase;
    return Center(
      child: AspectRatio(
        aspectRatio: s.previewAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            camera.buildPreview(),
            CustomPaint(
              painter: GuidePainter(guide: s.guide, color: color),
            ),
            Positioned(
              top: Space.x3,
              left: Space.x3,
              right: Space.x3,
              child: _HintPill(state: s),
            ),
            if (phase is Countdown)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: 'Taking photo in ${phase.secondsLeft}',
                      child: Container(
                        width: 96,
                        height: 96,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                        child: Text(
                          '${phase.secondsLeft}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.x3),
                    FilledButton.tonalIcon(
                      onPressed: ref
                          .read(passportPhotoProvider.notifier)
                          .cancelCountdown,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
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

class _HintPill extends StatelessWidget {
  const _HintPill({required this.state});
  final PassportPhotoState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final String text;
    if (!s.detectorAvailable) {
      text =
          "Face detection isn't available on this device — line up with the "
          'oval and use the shutter button.';
    } else if (s.phase is Manual) {
      text = s.checks.allPass
          ? 'Looks good — tap the shutter'
          : '${s.checks.hint} · Auto-capture is off';
    } else {
      text = s.checks.hint;
    }
    final phase = s.phase;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x2,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: Radii.buttonAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              key: const Key('passport-hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            if (phase is Holding) ...[
              const SizedBox(height: Space.x1),
              LinearProgressIndicator(
                value: phase.progress,
                color: Colors.greenAccent.shade400,
                backgroundColor: Colors.white24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlsBar extends ConsumerWidget {
  const _ControlsBar({required this.state});
  final PassportPhotoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final ctrl = ref.read(passportPhotoProvider.notifier);
    final live = s.status == CameraStatus.live;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  toggled: s.autoCapture,
                  label: 'Auto-capture',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        key: const Key('auto-capture'),
                        value: s.autoCapture,
                        onChanged: s.detectorAvailable
                            ? (v) => ctrl.setAutoCapture(enabled: v)
                            : null,
                      ),
                      const Flexible(
                        child: Text(
                          'Auto',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Take photo',
              child: InkResponse(
                key: const Key('shutter'),
                onTap: live ? ctrl.capture : null,
                radius: 40,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? Colors.white : Colors.white38,
                    border: Border.all(color: Colors.white54, width: 4),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: s.canSwitchFacing
                    ? IconButton(
                        tooltip: s.facing == CameraFacing.front
                            ? 'Use back camera'
                            : 'Use front camera',
                        color: Colors.white,
                        onPressed: live ? ctrl.switchFacing : null,
                        icon: const Icon(Icons.flip_camera_ios_rounded),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: Space.x3),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}

/// Horizontal size picker: built-in presets plus Custom.
class _PresetBar extends ConsumerWidget {
  const _PresetBar({required this.selected});
  final PhotoPreset selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(passportPhotoProvider.notifier);
    final isCustom = selected.id == 'custom';
    Widget chip(
      String label, {
      required bool sel,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(right: Space.x2),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
      ),
    );
    // Few chips: a Row keeps them all built (and reachable) at any width.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.x2,
      ),
      child: Row(
        children: [
          for (final p in PhotoPreset.builtIn)
            chip(p.label, sel: p == selected, onTap: () => ctrl.setPreset(p)),
          chip(
            isCustom ? selected.label : 'Custom…',
            sel: isCustom,
            onTap: () async {
              final p = await showCustomSizeDialog(context);
              if (p != null) ctrl.setPreset(p);
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewView extends ConsumerWidget {
  const _ReviewView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(passportPhotoProvider);
    final ctrl = ref.read(passportPhotoProvider.notifier);
    final review = s.review!;
    final photo = review.photo;
    final preset = s.preset;
    final saving = s.save is PassportSaving;
    final ready = photo != null && !review.processing && !saving;
    final limit = preset.maxBytes;
    return Scaffold(
      appBar: AppBar(title: const Text('Your photo')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x8),
        children: [
          _PresetBar(selected: preset),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: AspectRatio(
                      aspectRatio: preset.aspect,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: context.ds.border),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (photo != null)
                              Image.memory(
                                photo.bytes,
                                key: const Key('passport-result'),
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                semanticLabel: 'Cropped ${preset.name} photo',
                              ),
                            if (review.processing)
                              const Center(child: CircularProgressIndicator()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x3),
                if (!review.faceFound)
                  _Note(
                    icon: Icons.face_rounded,
                    color: context.ds.warning,
                    text:
                        "We couldn't find a face in the photo, so it's "
                        'centred. Use Adjust crop to position it.',
                  ),
                if (review.failure case final f?)
                  _Note(
                    icon: Icons.error_outline_rounded,
                    color: context.colors.error,
                    text: '${f.title}. ${f.recovery}',
                  ),
                if (photo != null) ...[
                  Text(
                    '${photo.width} × ${photo.height} px · ${preset.sizeLabel} '
                    'at ${preset.dpi} dpi',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: Space.x1),
                  Text(
                    limit == null
                        ? 'File size: ${formatBytes(photo.sizeBytes)}'
                        : 'File size: ${formatBytes(photo.sizeBytes)} '
                              '(limit ${preset.maxKb} KB)'
                              '${photo.withinLimit ? '' : ' — over the limit'}',
                    key: const Key('passport-size'),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: photo.withinLimit
                          ? context.ds.textSecondary
                          : context.colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: Space.x2),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: review.brighten,
                  onChanged: review.processing
                      ? null
                      : (v) => ctrl.setBrighten(enabled: v),
                  title: const Text('Brighten background'),
                  subtitle: const Text(
                    "A light touch for off-white walls. It doesn't replace "
                    'the background — a plain, light wall works best.',
                  ),
                ),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : ctrl.retake,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: review.processing || saving
                            ? null
                            : () async {
                                final auto = ctrl.autoRectForReview();
                                final rect = await Navigator.of(context)
                                    .push<NRect>(
                                      MaterialPageRoute(
                                        fullscreenDialog: true,
                                        builder: (_) => CropAdjustPage(
                                          source: review.source,
                                          preset: preset,
                                          initial: review.rect,
                                          auto: auto ?? review.rect,
                                        ),
                                      ),
                                    );
                                if (rect != null) await ctrl.setCrop(rect);
                              },
                        icon: const Icon(Icons.crop_rounded),
                        label: const Text('Adjust crop'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                SaveFolderField(flow: passportPhotoSaveFlow, enabled: !saving),
                const SizedBox(height: Space.x3),
                FilledButton.icon(
                  onPressed: ready ? ctrl.saveJpeg : null,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_rounded),
                  label: const Text('Save as JPEG'),
                ),
                const SizedBox(height: Space.x2),
                OutlinedButton.icon(
                  onPressed: ready
                      ? () async {
                          final opts = await showPrintSheetOptions(
                            context,
                            preset,
                          );
                          if (opts != null) {
                            await ctrl.savePrintSheet(
                              opts.paper,
                              count: opts.count,
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('Print sheet (4 × 6 in or A4)'),
                ),
                const SizedBox(height: Space.x4),
                const FidelityNote(
                  label: 'Check the official rules',
                  explanation:
                      'Requirements differ between offices and forms. We '
                      "help with size and framing but don't verify official "
                      'compliance (background, expression, glasses).',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}
