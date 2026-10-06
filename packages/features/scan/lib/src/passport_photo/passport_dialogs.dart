import 'dart:math' as math;

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/passport_photo/guide_overlay.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:feature_scan/src/passport_photo/photo_processing.dart';
import 'package:feature_scan/src/passport_photo/print_sheet.dart';
import 'package:flutter/material.dart';

/// Asks for a custom size (mm / in / px) and an optional KB limit.
Future<PhotoPreset?> showCustomSizeDialog(BuildContext context) =>
    showDialog<PhotoPreset>(
      context: context,
      builder: (_) => const _CustomSizeDialog(),
    );

class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog();

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  final _w = TextEditingController(text: '35');
  final _h = TextEditingController(text: '45');
  final _kb = TextEditingController();
  var _unit = SizeUnit.mm;
  String? _error;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _kb.dispose();
    super.dispose();
  }

  void _submit() {
    final w = double.tryParse(_w.text.trim().replaceAll(',', '.'));
    final h = double.tryParse(_h.text.trim().replaceAll(',', '.'));
    final kbText = _kb.text.trim();
    final kb = kbText.isEmpty ? null : int.tryParse(kbText);
    if (kbText.isNotEmpty && kb == null) {
      setState(() => _error = 'Enter the size limit as a whole number of KB.');
      return;
    }
    final error = validateCustomSize(
      width: w,
      height: h,
      unit: _unit,
      maxKb: kb,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(
      context,
    ).pop(PhotoPreset.custom(width: w!, height: h!, unit: _unit, maxKb: kb));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom size'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SizeUnit>(
            segments: [
              for (final u in SizeUnit.values)
                ButtonSegment(value: u, label: Text(u.label)),
            ],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('custom-width'),
                  controller: _w,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Width (${_unit.label})',
                  ),
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: TextField(
                  key: const Key('custom-height'),
                  controller: _h,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Height (${_unit.label})',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('custom-kb'),
            controller: _kb,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max file size in KB (optional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.x3),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Use this size')),
    ],
  );
}

/// Asks for paper and number of copies for a print sheet.
Future<({PrintPaper paper, int count})?> showPrintSheetOptions(
  BuildContext context,
  PhotoPreset preset,
) => showModalBottomSheet<({PrintPaper paper, int count})>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _PrintSheetOptions(preset: preset),
);

class _PrintSheetOptions extends StatefulWidget {
  const _PrintSheetOptions({required this.preset});
  final PhotoPreset preset;

  @override
  State<_PrintSheetOptions> createState() => _PrintSheetOptionsState();
}

class _PrintSheetOptionsState extends State<_PrintSheetOptions> {
  var _paper = PrintPaper.photo4x6;
  int? _count;

  int get _capacity {
    final c = printSheetCapacity(
      _paper,
      photoWidthMm: widget.preset.widthMm,
      photoHeightMm: widget.preset.heightMm,
    );
    return c.columns * c.rows;
  }

  @override
  Widget build(BuildContext context) {
    final cap = _capacity;
    final count = math.min(_count ?? cap, cap);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Print sheet', style: context.text.titleLarge),
            const SizedBox(height: Space.x2),
            Text(
              'Copies at true size with thin cut lines. Print at 100% '
              '(“actual size”), not “fit to page”.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.x4),
            SegmentedButton<PrintPaper>(
              segments: [
                for (final p in PrintPaper.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_paper},
              onSelectionChanged: (s) => setState(() {
                _paper = s.first;
                _count = null;
              }),
            ),
            const SizedBox(height: Space.x4),
            if (cap == 0)
              const Text("This photo size doesn't fit on that paper.")
            else ...[
              Text('$count of $cap photos', style: context.text.titleSmall),
              if (cap > 1)
                Slider(
                  value: count.toDouble(),
                  min: 1,
                  max: cap.toDouble(),
                  divisions: cap - 1,
                  label: '$count',
                  onChanged: (v) => setState(() => _count = v.round()),
                ),
            ],
            const SizedBox(height: Space.x3),
            FilledButton.icon(
              onPressed: cap == 0
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop((paper: _paper, count: count)),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Create print sheet (PDF)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen crop adjuster: drag to move, pinch (or buttons) to zoom.
class CropAdjustPage extends StatefulWidget {
  const CropAdjustPage({
    required this.source,
    required this.preset,
    required this.initial,
    required this.auto,
    super.key,
  });

  final SourcePhoto source;
  final PhotoPreset preset;
  final NRect initial;
  final NRect auto;

  @override
  State<CropAdjustPage> createState() => _CropAdjustPageState();
}

class _CropAdjustPageState extends State<CropAdjustPage> {
  late NRect _rect = widget.initial;
  late NRect _start = widget.initial;

  NRect _adjust({double dx = 0, double dy = 0, double scale = 1}) =>
      adjustCropRect(
        _start,
        imageWidth: widget.source.width,
        imageHeight: widget.source.height,
        aspect: widget.preset.aspect,
        dx: dx,
        dy: dy,
        scale: scale,
      );

  void _zoom(double scale) => setState(() {
    _start = _rect;
    _rect = _adjust(scale: scale);
  });

  @override
  Widget build(BuildContext context) {
    final src = widget.source;
    final imageAspect = src.width / src.height;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Adjust crop'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_rect),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: imageAspect,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size = c.biggest;
                    final guide = GuideGeometry.forPreset(
                      widget.preset,
                      previewAspect: widget.preset.aspect,
                      fill: 1,
                    );
                    final r = _rect;
                    // Guide in the crop's own space, mapped into the image.
                    NRect inCrop(NRect g) => NRect(
                      r.left + g.left * r.width,
                      r.top + g.top * r.height,
                      g.width * r.width,
                      g.height * r.height,
                    );
                    final mapped = GuideGeometry(
                      frame: r,
                      oval: inCrop(guide.oval),
                      eyeLineY: r.top + guide.eyeLineY * r.height,
                      headMin: guide.headMin,
                      headMax: guide.headMax,
                    );
                    return Semantics(
                      label:
                          'Crop area. Drag to move, pinch to zoom. Use the '
                          'buttons below to zoom.',
                      child: GestureDetector(
                        key: const Key('crop-area'),
                        onScaleStart: (_) => _start = _rect,
                        onScaleUpdate: (d) => setState(() {
                          _start = _rect;
                          _rect = _adjust(
                            dx: -d.focalPointDelta.dx / size.width,
                            dy: -d.focalPointDelta.dy / size.height,
                            scale: d.scale == 1 ? 1 : 1 / d.scale,
                          );
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              src.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                            CustomPaint(
                              painter: GuidePainter(
                                guide: mapped,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.x3),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.x2,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Zoom in',
                    onPressed: () => _zoom(0.92),
                    icon: const Icon(Icons.zoom_in_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Zoom out',
                    onPressed: () => _zoom(1.08),
                    icon: const Icon(Icons.zoom_out_rounded),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => setState(() => _rect = widget.auto),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Auto'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
