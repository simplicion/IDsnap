import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/target_size.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compress by a quality level, or to fit under an upload limit.
enum PdfCompressMode { quality, targetSize }

class CompressPdfScreen extends ConsumerStatefulWidget {
  const CompressPdfScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends ConsumerState<CompressPdfScreen>
    with PreselectDocument {
  static const _job = 'compress-pdf';
  var _inputs = <ToolInput>[];
  PdfCompressionLevel _level = PdfCompressionLevel.recommended;
  var _mode = PdfCompressMode.quality;

  /// A value from [pdfTargetPresets], or -1 for [_customTarget].
  int _target = 200 * 1024;
  int? _customTarget;
  int? _originalSize;

  int? get _targetBytes => _target == -1 ? _customTarget : _target;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    return ToolScaffold(
      jobKey: _job,
      title: 'Compress PDF',
      description: 'Make a PDF smaller for email and upload forms.',
      primaryLabel: _mode == PdfCompressMode.targetSize && _targetBytes != null
          ? 'Compress under ${formatBytes(_targetBytes!)}'
          : 'Compress',
      primaryIcon: Icons.compress_rounded,
      onPrimary: input == null ? null : () => _run(input),
      doneSummary: (docs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizeComparison(before: _originalSize, after: docs.first.sizeBytes),
          if (_mode == PdfCompressMode.targetSize && _targetBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.x2),
              child: Text(
                'Under your ${formatBytes(_targetBytes!)} limit ✓',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.success,
                ),
              ),
            ),
        ],
      ),
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: (v) => setState(() => _inputs = v),
        ),
        SegmentedButton<PdfCompressMode>(
          segments: const [
            ButtonSegment(
              value: PdfCompressMode.quality,
              label: Text('By quality'),
              icon: Icon(Icons.tune_rounded),
            ),
            ButtonSegment(
              value: PdfCompressMode.targetSize,
              label: Text('Target size'),
              icon: Icon(Icons.straighten_rounded),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        if (_mode == PdfCompressMode.targetSize)
          ChoiceGroup<int>(
            label: 'Keep the PDF under',
            hint: 'Tries stronger compression until it fits the limit.',
            values: const [...pdfTargetPresets, -1],
            selected: _target,
            labelOf: (v) => v != -1
                ? formatBytes(v)
                : _customTarget == null
                ? 'Custom…'
                : 'Custom (${formatBytes(_customTarget!)})',
            onSelected: _selectTarget,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Compression level', style: context.text.titleSmall),
              const SizedBox(height: Space.x2),
              for (final l in PdfCompressionLevel.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: _LevelCard(
                    level: l,
                    selected: l == _level,
                    onTap: () => setState(() => _level = l),
                  ),
                ),
            ],
          ),
        const FidelityNote(
          label: 'Pages become images',
          explanation:
              'Compression re-draws every page as a picture. It looks the '
              "same, but text won't be selectable or searchable afterwards.",
          limitations: [
            'Forms, links and bookmarks are not kept.',
            'Your original PDF is not changed.',
          ],
        ),
      ],
    );
  }

  Future<void> _selectTarget(int value) async {
    if (value != -1) {
      setState(() => _target = value);
      return;
    }
    final text = await promptText(
      context,
      title: 'Target size (KB)',
      confirmLabel: 'Set',
      initial: _customTarget == null ? '' : '${_customTarget! ~/ 1024}',
      hint: 'e.g. 250',
    );
    final kb = int.tryParse(text?.trim() ?? '');
    if (!mounted) return;
    if (kb == null || kb < 10) {
      if (text != null) {
        showAppSnack(context, 'Enter a size of at least 10 KB.');
      }
      return;
    }
    setState(() {
      _customTarget = kb * 1024;
      _target = -1;
    });
  }

  void _run(ToolInput input) {
    final level = _level;
    final target = _mode == PdfCompressMode.targetSize ? _targetBytes : null;
    final pdf = ref.read(pdfEngineProvider);
    final files = ref.read(fileStoreProvider);
    final inspect = ref.read(inspectInputProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final pre = await inspect(
        input.path,
        accepts: const {DocumentFormat.pdf},
        nameHint: input.fileLabel,
      );
      if (pre case Err(:final failure)) {
        return Err(failure.withDetail(input.fileLabel));
      }
      final original = input.sizeBytes ?? await files.size(input.path);
      _originalSize = original;
      final count = await pdf.pageCount(input.path);
      if (count case Err(:final failure)) return Err(failure);
      final Uint8List bytes;
      if (target != null) {
        if (original <= target) {
          return Err(
            NoticeFailure(
              'This PDF is already ${formatBytes(original)}, under your '
              '${formatBytes(target)} limit, so nothing was saved. Your '
              'original is unchanged.',
            ),
          );
        }
        final fitted = await compressPdfToTarget(
          pdf,
          input.path,
          target,
          onStep: (f) => report(f * 0.95),
        );
        if (fitted case Err(:final failure)) return Err(failure);
        bytes = fitted.valueOrNull!.bytes;
        // Defensive: never report success above the user's limit.
        if (bytes.length > target) return Err(pdfTargetUnreachable(target));
      } else {
        final r = await pdf.compress(input.path, level, onProgress: report);
        if (r case Err(:final failure)) return Err(failure);
        bytes = r.valueOrNull!;
      }
      if (bytes.length >= original * 0.98) {
        return const Err(
          NoticeFailure(
            "This PDF is already compact — compressing wouldn't make it "
            'smaller, so nothing was saved. Your original is unchanged.',
          ),
        );
      }
      return Ok([
        OutputFile(
          bytes: bytes,
          format: DocumentFormat.pdf,
          suggestedName: '${input.name} (compressed)',
          expectedPages: count.valueOrNull,
        ),
      ]);
    }, label: 'Compressing pages…');
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final PdfCompressionLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Card(
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: BorderSide(
          color: selected ? context.colors.primary : context.ds.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? context.colors.primary
                    : context.ds.textSecondary,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.label, style: context.text.titleSmall),
                    Text(
                      level.hint,
                      style: context.text.bodySmall?.copyWith(
                        color: context.ds.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text('${level.dpi} dpi', style: context.text.labelMedium),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "2.4 MB → 640 KB · 73% smaller".
class SizeComparison extends StatelessWidget {
  const SizeComparison({required this.before, required this.after, super.key});

  final int? before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final b = before;
    final saved = b == null || b == 0 ? null : (1 - after / b) * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (b != null) ...[
                  Text(formatBytes(b), style: context.text.titleMedium),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.x3),
                    child: Icon(Icons.arrow_forward_rounded),
                  ),
                ],
                Text(
                  formatBytes(after),
                  style: context.text.titleMedium?.copyWith(
                    color: context.ds.success,
                  ),
                ),
              ],
            ),
            if (saved != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x1),
                child: Text(
                  saved > 0
                      ? '${saved.round()}% smaller'
                      : '${(-saved).round()}% larger',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
