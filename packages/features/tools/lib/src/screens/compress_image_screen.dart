import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/screens/compress_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Set<DocumentFormat> compressibleImages = {
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.bmp,
  DocumentFormat.gif,
  DocumentFormat.tiff,
};

/// Common upload caps. `null` = off; `-1` = custom.
const targetPresets = <int?>[
  null,
  100 * 1024,
  200 * 1024,
  500 * 1024,
  1024 * 1024,
  -1,
];
const dimensionPresets = <int?>[null, 2048, 1600, 1080, 720];

class CompressImageScreen extends ConsumerStatefulWidget {
  const CompressImageScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<CompressImageScreen> createState() =>
      _CompressImageScreenState();
}

class _CompressImageScreenState extends ConsumerState<CompressImageScreen>
    with PreselectDocument {
  static const _job = 'compress-image';
  var _inputs = <ToolInput>[];
  var _quality = 75.0;
  int? _maxDimension;
  ImageOutputFormat _format = ImageOutputFormat.jpeg;
  int? _target;
  int? _customTarget;
  int? _originalSize;
  EncodedImage? _result;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => compressibleImages;
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  int? get _targetBytes => _target == -1 ? _customTarget : _target;

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final details = input == null
        ? null
        : ref.watch(imageDetailsProvider(input.path)).value;
    final isPng = _format == ImageOutputFormat.png;
    return ToolScaffold(
      jobKey: _job,
      title: 'Compress image',
      description:
          'Shrink photos for forms and chat apps. Choose a size limit and '
          "we'll keep as much quality as fits.",
      primaryLabel: 'Compress',
      primaryIcon: Icons.photo_size_select_small_rounded,
      onPrimary: input == null ? null : () => _run(input),
      doneSummary: (docs) => _Summary(
        before: _originalSize,
        after: docs.first.sizeBytes,
        original: details,
        result: _result,
        target: _targetBytes,
        preview: docs.first,
      ),
      children: [
        InputPicker(
          accepts: compressibleImages,
          inputs: _inputs,
          onChanged: (v) => setState(() => _inputs = v),
        ),
        if (input != null && details != null)
          Text(
            'Original: ${details.width} × ${details.height} px · '
            '${formatBytes(details.sizeBytes)}',
            style: context.text.bodyMedium,
          ),
        ChoiceGroup<ImageOutputFormat>(
          label: 'Format',
          hint: isPng
              ? 'PNG is lossless — only resizing reduces its size.'
              : 'JPG gives the smallest photos.',
          values: ImageOutputFormat.values,
          selected: _format,
          labelOf: (f) => f.label,
          onSelected: (f) => setState(() => _format = f),
        ),
        if (!isPng)
          ChoiceGroup<int?>(
            label: 'Target size',
            hint: 'Useful when a form says "max 200 KB".',
            values: targetPresets,
            selected: _target,
            labelOf: (t) => switch (t) {
              null => 'Off',
              -1 =>
                _customTarget == null
                    ? 'Custom…'
                    : 'Custom (${formatBytes(_customTarget!)})',
              _ => formatBytes(t),
            },
            onSelected: _selectTarget,
          ),
        if (!isPng && _targetBytes == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quality: ${_quality.round()}',
                style: context.text.titleSmall,
              ),
              Slider(
                value: _quality,
                min: 10,
                max: 100,
                divisions: 18,
                label: '${_quality.round()}',
                onChanged: (v) => setState(() => _quality = v),
              ),
            ],
          ),
        ChoiceGroup<int?>(
          label: 'Maximum size (longest edge)',
          values: dimensionPresets,
          selected: _maxDimension,
          labelOf: (d) => d == null ? 'Original' : '$d px',
          onSelected: (d) => setState(() => _maxDimension = d),
        ),
      ],
    );
  }

  Future<void> _selectTarget(int? value) async {
    if (value != -1) {
      setState(() => _target = value);
      return;
    }
    final text = await promptText(
      context,
      title: 'Target size (KB)',
      confirmLabel: 'Set',
      initial: _customTarget == null ? '' : '${_customTarget! ~/ 1024}',
      hint: 'e.g. 150',
    );
    final kb = int.tryParse(text ?? '');
    if (kb == null || kb <= 0 || !mounted) return;
    setState(() {
      _customTarget = kb * 1024;
      _target = -1;
    });
  }

  void _run(ToolInput input) {
    final isPng = _format == ImageOutputFormat.png;
    final options = ImageCompressionOptions(
      quality: _quality.round(),
      maxDimension: _maxDimension,
      format: _format,
      targetBytes: isPng ? null : _targetBytes,
    );
    final files = ref.read(fileStoreProvider);
    final images = ref.read(imageProcessorProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final bytes = await files.read(input.path);
      _originalSize = bytes.length;
      final r = await images.compress(bytes, options);
      if (r case Err(:final failure)) return Err(failure);
      final enc = r.valueOrNull!;
      final target = options.targetBytes;
      if (target != null && enc.bytes.length > target) {
        // Never save a file that breaks the user's upload limit.
        return Err(
          AppFailure(
            FailureCode.targetSizeUnreachable,
            detail: 'Limit ${formatBytes(target)}',
            action: FailureAction.lowerQuality,
            message:
                "Couldn't reach ${formatBytes(target)} without making the "
                'image unreadable. Choose a smaller maximum size (e.g. '
                '1080 px) and try again.',
          ),
        );
      }
      _result = enc;
      return Ok([
        OutputFile(
          bytes: Uint8List.fromList(enc.bytes),
          format: enc.format == ImageOutputFormat.png
              ? DocumentFormat.png
              : DocumentFormat.jpeg,
          suggestedName: '${input.name} (compressed)',
        ),
      ]);
    }, label: 'Compressing…');
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({
    required this.before,
    required this.after,
    required this.original,
    required this.result,
    required this.target,
    required this.preview,
  });

  final int? before;
  final int after;
  final ImageDetails? original;
  final EncodedImage? result;
  final int? target;
  final Document preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileStoreProvider);
    final r = result;
    final missed = target != null && after > target!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizeComparison(before: before, after: after),
        if (r != null && original != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(
              '${original!.width} × ${original!.height} px → '
              '${r.width} × ${r.height} px',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          ),
        if (missed)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(
              "Couldn't reach ${formatBytes(target!)} without making the "
              'image unreadable. Try a smaller maximum size.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.warning,
              ),
            ),
          ),
        const SizedBox(height: Space.x3),
        ClipRRect(
          borderRadius: Radii.cardAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ImageThumbFull(path: files.absolute(preview.relativePath)),
          ),
        ),
      ],
    );
  }
}

/// Aspect-preserving preview of an image file.
class ImageThumbFull extends ConsumerWidget {
  const ImageThumbFull({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(fileBytesProvider(path))) {
        AsyncData(:final value) => Image.memory(
          value,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        _ => const SizedBox(height: 120),
      };
}
