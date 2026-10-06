import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/signature/create_signature.dart';
import 'package:feature_tools/src/signature/signature_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create, manage and export saved signatures (PRD 3.3).
class MySignatureScreen extends ConsumerWidget {
  const MySignatureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedSignaturesProvider);
    final count = saved.value?.length ?? 0;
    final full = count >= SignatureLibrary.capacity;
    return Scaffold(
      appBar: AppBar(title: const Text('My signature')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.x2,
          Space.gutter,
          Space.x10,
        ),
        children: [
          Text(
            'Draw your signature or photograph it on paper. It is stored '
            'only on this phone as a transparent PNG, ready to sign PDFs.',
            style: context.text.bodyLarge?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          const SizedBox(height: Space.x3),
          const Align(alignment: Alignment.centerLeft, child: OfflineBadge()),
          const SizedBox(height: Space.x5),
          FilledButton.icon(
            onPressed: full
                ? null
                : () => createSignature(context, ref, SignatureSource.draw),
            icon: const Icon(Icons.draw_rounded),
            label: const Text('Draw a signature'),
          ),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full
                      ? null
                      : () => createSignature(
                          context,
                          ref,
                          SignatureSource.camera,
                        ),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Photograph'),
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full
                      ? null
                      : () => createSignature(
                          context,
                          ref,
                          SignatureSource.gallery,
                        ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('From gallery'),
                ),
              ),
            ],
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.only(top: Space.x2),
              child: Text(
                'You have ${SignatureLibrary.capacity} signatures, the '
                'most you can keep. Delete one to add another.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.warning,
                ),
              ),
            ),
          SectionHeader(
            'Saved signatures ($count of '
            '${SignatureLibrary.capacity})',
          ),
          switch (saved) {
            AsyncData(:final value) when value.isEmpty => const EmptyState(
              icon: Icons.draw_outlined,
              title: 'No signatures yet',
              message: 'Draw or photograph your signature to get started.',
            ),
            AsyncData(:final value) => Column(
              children: [for (final s in value) _SignatureRow(signature: s)],
            ),
            AsyncError(:final error) => FailureView(
              error is AppFailure
                  ? error
                  : const AppFailure(
                      FailureCode.unknown,
                      heading: "Your signatures couldn't be loaded",
                      message:
                          'They are still saved on this phone. Try again, or '
                          'restart IDSnap.',
                    ),
              onRetry: () => ref.invalidate(savedSignaturesProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ],
      ),
    );
  }
}

enum _Action { makeDefault, export, delete }

class _SignatureRow extends ConsumerWidget {
  const _SignatureRow({required this.signature});

  final SavedSignature signature;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: Row(
          children: [
            SavedSignatureTile(signature: signature, width: 160),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signature.isDefault ? 'Default signature' : 'Signature',
                    style: context.text.titleSmall,
                  ),
                  Text(
                    '${signature.width} × ${signature.height} px · '
                    '${formatRelativeDate(signature.createdAt)}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_Action>(
              tooltip: 'Signature options',
              onSelected: (a) => _act(context, ref, a),
              itemBuilder: (_) => [
                if (!signature.isDefault)
                  const PopupMenuItem(
                    value: _Action.makeDefault,
                    child: Text('Set as default'),
                  ),
                const PopupMenuItem(
                  value: _Action.export,
                  child: Text('Export transparent PNG'),
                ),
                const PopupMenuItem(
                  value: _Action.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _act(BuildContext context, WidgetRef ref, _Action a) async {
    final library = ref.read(signatureLibraryProvider);
    switch (a) {
      case _Action.makeDefault:
        final r = await library.setDefault(signature.id);
        ref.invalidate(savedSignaturesProvider);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureSnack(context, failure);
      case _Action.export:
        final png = await library.load(signature.id);
        if (!context.mounted) return;
        if (png case Err(:final failure)) {
          showFailureSnack(context, failure);
          return;
        }
        final saved = await ref
            .read(shareServiceProvider)
            .saveToDevice(png.valueOrNull!, 'signature.png');
        if (!context.mounted) return;
        saved.fold((ok) {
          if (ok) showAppSnack(context, 'Saved signature.png');
        }, (f) => showFailureSnack(context, f));
      case _Action.delete:
        final ok = await confirmAction(
          context,
          title: 'Delete this signature?',
          message:
              'It is removed from this phone. PDFs you already signed '
              'are not changed.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        final r = await library.delete(signature.id);
        ref.invalidate(savedSignaturesProvider);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureSnack(context, failure);
    }
  }
}
