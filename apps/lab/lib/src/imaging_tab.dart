import 'dart:async';

import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';

class _FilterRun {
  const _FilterRun(this.filter, this.result, this.ms);

  final EnhancementFilter filter;
  final Result<Uint8List> result;
  final int ms;
}

/// Runs detection, then renders every [EnhancementFilter] with timings.
class ImagingTab extends StatefulWidget {
  const ImagingTab({required this.image, required this.processor, super.key});

  final Uint8List image;
  final ImageProcessor processor;

  @override
  State<ImagingTab> createState() => _ImagingTabState();
}

class _ImagingTabState extends State<ImagingTab> {
  ImageDetails? _details;
  Result<DetectedQuad>? _detected;
  int? _detectMs;
  final List<_FilterRun> _runs = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final p = widget.processor;
    final details = (await p.inspect(widget.image)).valueOrNull;
    final sw = Stopwatch()..start();
    final detected = await p.detectDocument(widget.image);
    final detectMs = sw.elapsedMilliseconds;
    if (!mounted) return;
    setState(() {
      _details = details;
      _detected = detected;
      _detectMs = detectMs;
    });
    final quad = detected.valueOrNull;
    for (final f in EnhancementFilter.values) {
      final watch = Stopwatch()..start();
      final out = await p.renderPage(
        widget.image,
        PageEdits(
          quad: quad != null && quad.isConfident ? quad.quad : null,
          filter: f,
        ),
        preset: QualityPreset.small,
      );
      if (!mounted) return;
      setState(() => _runs.add(_FilterRun(f, out, watch.elapsedMilliseconds)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final det = _detected;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Wrap(
              spacing: Space.x6,
              runSpacing: Space.x2,
              children: [
                _Stat(
                  'Image',
                  _details == null
                      ? '…'
                      : '${_details!.width} × ${_details!.height}',
                ),
                _Stat(
                  'Size',
                  _details == null ? '…' : formatBytes(_details!.sizeBytes),
                ),
                _Stat('Detection', _detectMs == null ? '…' : '$_detectMs ms'),
                _Stat('Confidence', switch (det) {
                  null => '…',
                  Ok(:final value) =>
                    '${(value.confidence * 100).round()}%${value.isConfident ? '' : ' (ask user)'}',
                  Err(:final failure) => failure.title,
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x4),
        if (_details != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: AspectRatio(
                aspectRatio: _details!.width / _details!.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(widget.image, fit: BoxFit.fill),
                    if (det?.valueOrNull case final q?)
                      CustomPaint(
                        painter: QuadPainter(
                          q.quad,
                          q.isConfident
                              ? context.ds.success
                              : context.ds.warning,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SectionHeader('Filters (small preset)'),
        GridView.extent(
          maxCrossAxisExtent: 220,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.x3,
          crossAxisSpacing: Space.x3,
          childAspectRatio: 0.72,
          children: [
            for (final r in _runs)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: r.result.fold(
                        (bytes) => Image.memory(bytes, fit: BoxFit.contain),
                        (f) => Center(child: Text(f.title)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.x2),
                      child: Text(
                        '${r.filter.label}\n${r.ms} ms · ${formatBytes(r.result.valueOrNull?.length ?? 0)}',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: context.text.labelMedium?.copyWith(
          color: context.ds.textSecondary,
        ),
      ),
      Text(value, style: context.text.titleMedium),
    ],
  );
}

/// Draws a normalized [Quad] over an image.
class QuadPainter extends CustomPainter {
  QuadPainter(this.quad, this.color);

  final Quad quad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final p in quad.points) Offset(p.x * size.width, p.y * size.height),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas
      ..drawPath(path, Paint()..color = color.withValues(alpha: 0.18))
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    for (final p in pts) {
      canvas.drawCircle(p, 7, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(QuadPainter old) => old.quad != quad || old.color != color;
}
