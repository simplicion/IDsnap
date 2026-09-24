import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';

/// Compression to a target size and preset crops (e.g. passport photo).
class CompressTab extends StatefulWidget {
  const CompressTab({required this.image, required this.processor, super.key});

  final Uint8List image;
  final ImageProcessor processor;

  @override
  State<CompressTab> createState() => _CompressTabState();
}

class _CompressTabState extends State<CompressTab> {
  double _targetKb = 200;
  ({Result<EncodedImage> result, int ms})? _compressed;

  CropPreset _preset = CropPreset.passportIntl;
  ({Result<EncodedImage> result, int ms})? _cropped;
  bool _busy = false;

  Future<void> _compress() async {
    setState(() => _busy = true);
    final sw = Stopwatch()..start();
    final r = await widget.processor.compress(
      widget.image,
      ImageCompressionOptions(
        targetBytes: (_targetKb * 1024).round(),
        maxDimension: 2400,
      ),
    );
    if (!mounted) return;
    setState(() {
      _compressed = (result: r, ms: sw.elapsedMilliseconds);
      _busy = false;
    });
  }

  Future<void> _crop() async {
    setState(() => _busy = true);
    final sw = Stopwatch()..start();
    final details = await widget.processor.inspect(widget.image);
    final Result<EncodedImage> r;
    if (details case Ok(:final value)) {
      r = await widget.processor.crop(
        widget.image,
        NRect.centeredWithAspect(_preset.aspect, value.width, value.height),
        outputWidth: _preset.pixelWidth,
        outputHeight: _preset.pixelHeight,
      );
    } else {
      r = Err(details.failureOrNull!);
    }
    if (!mounted) return;
    setState(() {
      _cropped = (result: r, ms: sw.elapsedMilliseconds);
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Space.gutter),
    children: [
      Text(
        'Original: ${formatBytes(widget.image.length)}',
        style: context.text.titleMedium,
      ),
      const SectionHeader('Compress to a target size'),
      Row(
        children: [
          Expanded(
            child: Slider(
              value: _targetKb,
              min: 50,
              max: 2000,
              divisions: 39,
              label: '${_targetKb.round()} KB',
              onChanged: (v) => setState(() => _targetKb = v),
            ),
          ),
          Text('${_targetKb.round()} KB'),
          const SizedBox(width: Space.x3),
          FilledButton(
            onPressed: _busy ? null : _compress,
            child: const Text('Compress'),
          ),
        ],
      ),
      if (_compressed case final r?)
        _ResultCard(
          result: r.result,
          ms: r.ms,
          note: 'Target ${_targetKb.round()} KB',
        ),
      const SectionHeader('Crop to a preset'),
      Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          for (final p in CropPreset.all)
            ChoiceChip(
              label: Text('${p.label} · ${p.sizeLabel}'),
              selected: p == _preset,
              onSelected: (_) => setState(() => _preset = p),
            ),
        ],
      ),
      const SizedBox(height: Space.x3),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _crop,
          icon: const Icon(Icons.crop_rounded),
          label: const Text('Crop centered'),
        ),
      ),
      if (_cropped case final r?)
        _ResultCard(
          result: r.result,
          ms: r.ms,
          note:
              'Expected ${_preset.pixelWidth} × ${_preset.pixelHeight} px at ${_preset.dpi} dpi',
        ),
    ],
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.ms,
    required this.note,
  });

  final Result<EncodedImage> result;
  final int ms;
  final String note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x3),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: result.fold(
          (img) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 160,
                  maxHeight: 200,
                ),
                child: Image.memory(Uint8List.fromList(img.bytes)),
              ),
              const SizedBox(width: Space.x4),
              Expanded(
                child: Text(
                  '${img.width} × ${img.height} ${img.format.label}\n'
                  '${formatBytes(img.bytes.length)} · $ms ms\n$note',
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
          (f) => Text(
            '${f.title}: ${f.recovery}',
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ),
    ),
  );
}
