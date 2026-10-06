import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/signature/signature_pad.dart';
import 'package:feature_tools/src/signature/signature_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen canvas; pops with a trimmed transparent [SignatureImage].
class DrawSignatureScreen extends StatefulWidget {
  const DrawSignatureScreen({super.key});

  @override
  State<DrawSignatureScreen> createState() => _DrawSignatureScreenState();
}

class _DrawSignatureScreenState extends State<DrawSignatureScreen> {
  final _pad = SignaturePadController();
  var _exporting = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => _exporting = true);
    final image = await _pad.export();
    if (!mounted) return;
    setState(() => _exporting = false);
    if (image == null) {
      showAppSnack(context, 'Draw your signature first.');
      return;
    }
    Navigator.pop(context, image);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Draw signature'),
      actions: [
        ListenableBuilder(
          listenable: _pad,
          builder: (context, _) => IconButton(
            tooltip: 'Undo last stroke',
            onPressed: _pad.canUndo ? _pad.undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
        ),
        ListenableBuilder(
          listenable: _pad,
          builder: (context, _) => IconButton(
            tooltip: 'Clear',
            onPressed: _pad.canUndo ? _pad.clear : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign inside the box. Turn your phone sideways for more room.',
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
            const SizedBox(height: Space.x3),
            Expanded(child: SignaturePad(controller: _pad)),
            const SizedBox(height: Space.x3),
            ListenableBuilder(
              listenable: _pad,
              builder: (context, _) => Row(
                children: [
                  Text('Ink', style: context.text.titleSmall),
                  const SizedBox(width: Space.x3),
                  for (final ink in SignatureInk.values) ...[
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: ink.color,
                        radius: 8,
                      ),
                      label: Text(ink.label),
                      selected: _pad.ink == ink,
                      onSelected: (_) => _pad.ink = ink,
                    ),
                    const SizedBox(width: Space.x2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        Space.x3,
      ),
      child: ListenableBuilder(
        listenable: _pad,
        builder: (context, _) => FilledButton.icon(
          onPressed: _pad.isEmpty || _exporting ? null : _done,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Use this signature'),
        ),
      ),
    ),
  );
}

/// Opens the canvas; null when the user backs out.
Future<SignatureImage?> drawSignature(BuildContext context) =>
    Navigator.of(context).push<SignatureImage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const DrawSignatureScreen(),
      ),
    );

/// Photographs ([camera]) or picks a paper signature and removes its
/// background. Shows actionable errors; null when cancelled or failed.
Future<SignatureImage?> signatureFromPhoto(
  BuildContext context,
  WidgetRef ref, {
  required bool camera,
}) async {
  final Result<List<String>> picked;
  try {
    picked = camera
        ? await ref.read(documentScannerProvider).scan(maxPages: 1)
        : (await ref.read(mediaPickerProvider).pickImages(multiple: false)).map(
            (files) => [for (final f in files) f.path],
          );
  } on Object catch (e, st) {
    if (context.mounted) {
      showFailureSnack(
        context,
        AppFailure(
          FailureCode.cameraUnavailable,
          cause: e,
          stackTrace: st,
          message: camera
              ? 'The camera is not available. Choose a photo instead.'
              : null,
        ),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  if (picked case Err(:final failure)) {
    if (failure.code != FailureCode.captureCancelled) {
      showFailureSnack(context, failure);
    }
    return null;
  }
  final paths = picked.valueOrNull!;
  if (paths.isEmpty) return null;

  final Uint8List bytes;
  try {
    bytes = await ref.read(fileStoreProvider).read(paths.first);
  } on Object catch (e, st) {
    if (context.mounted) {
      showFailureSnack(
        context,
        AppFailure(FailureCode.notFound, cause: e, stackTrace: st),
      );
    }
    return null;
  }
  final SignatureProcessor processor;
  try {
    processor = ref.read(signatureProcessorProvider);
  } on Object {
    if (context.mounted) {
      showFailureSnack(
        context,
        const AppFailure(
          FailureCode.offlineDependencyUnavailable,
          message:
              'Background removal is not available in this build. Draw '
              'your signature instead.',
        ),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  final result = await _withProgress(
    context,
    'Removing the paper background…',
    processor.extractTransparent(bytes),
  );
  if (!context.mounted) return null;
  switch (result) {
    case Err(:final failure):
      showFailureSnack(context, failure);
      return null;
    case Ok(:final value):
      return SignatureImage(
        png: Uint8List.fromList(value.bytes),
        width: value.width,
        height: value.height,
      );
  }
}

Future<T> _withProgress<T>(
  BuildContext context,
  String label,
  Future<T> work,
) async {
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(Space.x6),
            child: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: Space.x5),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    navigator.pop();
  }
}

/// Saves [image] to the library. Returns null (after explaining why) when
/// it could not be saved, e.g. because the library is full.
Future<SavedSignature?> saveSignature(
  BuildContext context,
  WidgetRef ref,
  SignatureImage image,
) async {
  final r = await ref
      .read(signatureLibraryProvider)
      .add(image.png, width: image.width, height: image.height);
  ref.invalidate(savedSignaturesProvider);
  if (!context.mounted) return r.valueOrNull;
  if (r case Err(:final failure)) {
    showAppSnack(context, failure.recovery);
    return null;
  }
  return r.valueOrNull;
}

/// How a new signature should be created.
enum SignatureSource { draw, camera, gallery }

/// Creates a signature from [source] and saves it to the library when there
/// is room. The image is returned even if saving failed.
Future<SignatureImage?> createSignature(
  BuildContext context,
  WidgetRef ref,
  SignatureSource source,
) async {
  final SignatureImage? image;
  if (source == SignatureSource.draw) {
    image = await drawSignature(context);
  } else {
    image = await signatureFromPhoto(
      context,
      ref,
      camera: source == SignatureSource.camera,
    );
  }

  if (image == null || !context.mounted) return image;
  await saveSignature(context, ref, image);
  return image;
}

/// Bottom sheet: pick a saved signature or create a new one.
Future<SignatureImage?> showSignaturePicker(BuildContext context) =>
    showModalBottomSheet<SignatureImage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SignaturePickerSheet(),
    );

class _SignaturePickerSheet extends ConsumerWidget {
  const _SignaturePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedSignaturesProvider);
    Future<void> create(SignatureSource source) async {
      final image = await createSignature(context, ref, source);
      if (image != null && context.mounted) Navigator.pop(context, image);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose a signature', style: context.text.titleLarge),
          const SizedBox(height: Space.x3),
          switch (saved) {
            AsyncData(:final value) when value.isNotEmpty => Wrap(
              spacing: Space.x3,
              runSpacing: Space.x3,
              children: [
                for (final s in value)
                  SavedSignatureTile(
                    signature: s,
                    onTap: () async {
                      final png = await ref.read(
                        signaturePngProvider(s.id).future,
                      );
                      if (context.mounted) {
                        Navigator.pop(
                          context,
                          SignatureImage(
                            png: png,
                            width: s.width,
                            height: s.height,
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
            AsyncData() => Text(
              'No saved signatures yet. Create one below — it is saved on '
              'this phone for next time.',
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
            AsyncError(:final error) => Text(
              error is AppFailure
                  ? error.recovery
                  : "Saved signatures couldn't be loaded. Create a new one.",
            ),
            _ => const LinearProgressIndicator(),
          },
          const SizedBox(height: Space.x5),
          FilledButton.icon(
            onPressed: () => create(SignatureSource.draw),
            icon: const Icon(Icons.draw_rounded),
            label: const Text('Draw a new signature'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            onPressed: () => create(SignatureSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Photograph a paper signature'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            onPressed: () => create(SignatureSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Use a photo from the gallery'),
          ),
        ],
      ),
    );
  }
}

/// A saved signature on a checkerboard (so transparency is visible).
class SavedSignatureTile extends ConsumerWidget {
  const SavedSignatureTile({
    required this.signature,
    super.key,
    this.onTap,
    this.width = 150,
  });

  final SavedSignature signature;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final png = ref.watch(signaturePngProvider(signature.id));
    return Semantics(
      button: onTap != null,
      label: signature.isDefault ? 'Default signature' : 'Saved signature',
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Container(
          width: width,
          height: width * 0.5,
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(
              color: signature.isDefault
                  ? context.colors.primary
                  : context.ds.border,
              width: signature.isDefault ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: TransparencyBackdrop(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.x2),
                  child: switch (png) {
                    AsyncData(:final value) => Image.memory(
                      value,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    AsyncError() => const Icon(Icons.broken_image_outlined),
                    _ => const SizedBox.shrink(),
                  },
                ),
                if (signature.isDefault)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Pill('Default', icon: Icons.star_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
