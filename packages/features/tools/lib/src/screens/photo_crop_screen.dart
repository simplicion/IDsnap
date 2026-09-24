import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/screens/compress_image_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _FaceStatus { idle, detecting, framed, notFound, unavailable }

/// Maps a rect in the rotated image's normalized space back to the original
/// image (rotation is applied clockwise after cropping).
NRect unrotateRect(NRect r, int quarterTurns) {
  (double, double) back(double x, double y) => switch (quarterTurns % 4) {
    1 => (y, 1 - x),
    2 => (1 - x, 1 - y),
    3 => (1 - y, x),
    _ => (x, y),
  };
  final a = back(r.left, r.top);
  final b = back(r.right, r.bottom);
  final left = math.min(a.$1, b.$1);
  final top = math.min(a.$2, b.$2);
  return NRect(left, top, (a.$1 - b.$1).abs(), (a.$2 - b.$2).abs());
}

class PhotoCropScreen extends ConsumerStatefulWidget {
  const PhotoCropScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends ConsumerState<PhotoCropScreen>
    with PreselectDocument {
  static const _job = 'photo-crop';
  var _inputs = <ToolInput>[];
  CropPreset _preset = CropPreset.passportIntl;
  var _turns = 0;
  var _zoom = 1.0;
  Offset _offset = Offset.zero;
  double _startZoom = 1;
  NRect _crop = NRect.full;

  /// Auto-frame result waiting for layout to convert it to zoom/offset.
  NRect? _pendingFrame;
  NRect? _faceBox;
  _FaceStatus _faceStatus = _FaceStatus.idle;
  var _faceRequest = 0;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => compressibleImages;
  @override
  void onPreselected(ToolInput input) => _setInputs([input]);

  void _setInputs(List<ToolInput> v) {
    setState(() {
      _inputs = v;
      _turns = 0;
      _faceBox = null;
      _resetView();
    });
    unawaited(_detectFace());
  }

  /// Finds the face on-device and frames it to the preset's head-size rule.
  Future<void> _detectFace() async {
    final input = _inputs.firstOrNull;
    if (input == null || !_preset.isPortrait) return;
    final request = ++_faceRequest;
    setState(() => _faceStatus = _FaceStatus.detecting);
    final locator = ref.read(faceLocatorProvider);
    final cap = await locator.capability();
    if (!cap.available) {
      if (mounted) setState(() => _faceStatus = _FaceStatus.unavailable);
      return;
    }
    final result = await locator.locateLargestFace(input.path);
    if (!mounted || request != _faceRequest) return;
    final box = result.valueOrNull;
    setState(() {
      _faceBox = box;
      _faceStatus = box == null ? _FaceStatus.notFound : _FaceStatus.framed;
    });
    _applyAutoFrame();
  }

  void _applyAutoFrame() {
    final box = _faceBox;
    final input = _inputs.firstOrNull;
    if (box == null || input == null) return;
    final details = ref.read(imageDetailsProvider(input.path)).value;
    if (details == null) return;
    final rect = autoFramePortrait(
      face: box,
      preset: _preset,
      imageWidth: details.width,
      imageHeight: details.height,
    );
    if (rect == null) return;
    setState(() {
      _turns = 0;
      _pendingFrame = rect;
    });
  }

  void _resetView() {
    _zoom = 1;
    _offset = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final bytes = input == null
        ? null
        : ref.watch(fileBytesProvider(input.path)).value;
    final details = input == null
        ? null
        : ref.watch(imageDetailsProvider(input.path)).value;

    return ToolScaffold(
      jobKey: _job,
      title: 'Passport & ID photo',
      description:
          'Pick a size. We find the face and frame it automatically — '
          'pinch and drag to fine-tune.',
      primaryLabel: 'Save ${_preset.label.toLowerCase()}',
      primaryIcon: Icons.crop_rounded,
      onPrimary: input != null && details != null ? () => _run(input) : null,
      children: [
        InputPicker(
          accepts: compressibleImages,
          inputs: _inputs,
          title: 'Photo',
          onChanged: _setInputs,
        ),
        _PresetPicker(
          selected: _preset,
          onSelected: (p) {
            setState(() {
              _preset = p;
              _resetView();
            });
            if (!p.isPortrait) return;
            if (_faceBox != null) {
              _applyAutoFrame();
            } else {
              unawaited(_detectFace());
            }
          },
        ),
        if (input != null && _preset.isPortrait) _faceChip(context),
        if (bytes != null && details != null) ...[
          _cropper(bytes, details),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _turns = (_turns + 1) % 4;
                  _resetView();
                }),
                icon: const Icon(Icons.rotate_right_rounded),
                label: const Text('Rotate'),
              ),
              const SizedBox(width: Space.x3),
              OutlinedButton.icon(
                onPressed: () => setState(_resetView),
                icon: const Icon(Icons.fit_screen_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
          Text(
            'Output: ${_preset.pixelWidth} × ${_preset.pixelHeight} px '
            '(${_preset.sizeLabel} at ${_preset.dpi} dpi)',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium,
          ),
        ],
        const FidelityNote(
          label: 'Check the official rules',
          explanation:
              "Check your country's official photo rules; DocScan doesn't "
              'verify compliance (head size, background, expression).',
        ),
      ],
    );
  }

  Widget _cropper(Uint8List bytes, ImageDetails details) {
    final rotated = _turns.isOdd;
    final iw = (rotated ? details.height : details.width).toDouble();
    final ih = (rotated ? details.width : details.height).toDouble();
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final view = constraints.biggest;
          final maxW = view.width * 0.8;
          final maxH = view.height * 0.8;
          var fw = maxW;
          var fh = fw / _preset.aspect;
          if (fh > maxH) {
            fh = maxH;
            fw = fh * _preset.aspect;
          }
          final frame = Rect.fromCenter(
            center: view.center(Offset.zero),
            width: fw,
            height: fh,
          );
          final base = math.max(fw / iw, fh / ih);
          final pending = _pendingFrame;
          if (pending != null) {
            _pendingFrame = null;
            final targetW = fw / pending.width;
            _zoom = (targetW / (iw * base)).clamp(1.0, 6.0);
            final pw = iw * base * _zoom;
            final ph = ih * base * _zoom;
            _offset = Offset(
              pw * (0.5 - pending.left) - fw / 2,
              ph * (0.5 - pending.top) - fh / 2,
            );
          }
          final dw = iw * base * _zoom;
          final dh = ih * base * _zoom;
          final maxDx = (dw - fw) / 2;
          final maxDy = (dh - fh) / 2;
          final offset = Offset(
            _offset.dx.clamp(-maxDx, maxDx),
            _offset.dy.clamp(-maxDy, maxDy),
          );
          final display = Rect.fromCenter(
            center: frame.center + offset,
            width: dw,
            height: dh,
          );
          _crop = NRect(
            (frame.left - display.left) / dw,
            (frame.top - display.top) / dh,
            fw / dw,
            fh / dh,
          );

          return Semantics(
            label:
                'Crop area. Pinch to zoom, drag to move the photo inside '
                'the frame.',
            child: ClipRRect(
              borderRadius: Radii.cardAll,
              child: GestureDetector(
                onScaleStart: (_) => _startZoom = _zoom,
                onScaleUpdate: (d) => setState(() {
                  _zoom = (_startZoom * d.scale).clamp(1.0, 6.0);
                  _offset = offset + d.focalPointDelta;
                }),
                onDoubleTap: () => setState(() {
                  _zoom = _zoom > 1.5 ? 1 : 2;
                }),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: display,
                        child: RotatedBox(
                          quarterTurns: _turns,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _FramePainter(
                              frame: frame,
                              faceGuide: _preset.isPortrait,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _faceChip(BuildContext context) {
    final (icon, text, color) = switch (_faceStatus) {
      _FaceStatus.detecting => (
        Icons.face_retouching_natural_rounded,
        'Finding the face…',
        context.colors.primary,
      ),
      _FaceStatus.framed => (
        Icons.check_circle_rounded,
        'Face found and framed automatically',
        context.ds.success,
      ),
      _FaceStatus.notFound => (
        Icons.face_rounded,
        'No face found — position the photo manually',
        context.ds.warning,
      ),
      _FaceStatus.unavailable => (
        Icons.info_outline_rounded,
        "Automatic framing isn't available on this device",
        context.ds.textSecondary,
      ),
      _FaceStatus.idle => (
        Icons.face_rounded,
        'Automatic framing',
        context.ds.textSecondary,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(color: color),
          ),
        ),
        if (_faceStatus == _FaceStatus.framed ||
            _faceStatus == _FaceStatus.notFound)
          TextButton(
            onPressed: _faceBox != null ? _applyAutoFrame : _detectFace,
            child: Text(_faceBox != null ? 'Re-frame' : 'Retry'),
          ),
      ],
    );
  }

  void _run(ToolInput input) {
    final preset = _preset;
    final turns = _turns;
    final rect = unrotateRect(_crop, turns);
    final files = ref.read(fileStoreProvider);
    final images = ref.read(imageProcessorProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final bytes = await files.read(input.path);
      final r = await images.crop(
        bytes,
        rect,
        outputWidth: preset.pixelWidth,
        outputHeight: preset.pixelHeight,
        quarterTurns: turns,
        quality: 95,
      );
      return r.map(
        (enc) => [
          OutputFile(
            bytes: Uint8List.fromList(enc.bytes),
            format: DocumentFormat.jpeg,
            suggestedName: '${input.name} (${preset.label})',
          ),
        ],
      );
    }, label: 'Cropping photo…');
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.selected, required this.onSelected});

  final CropPreset selected;
  final ValueChanged<CropPreset> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Size', style: context.text.titleSmall),
      const SizedBox(height: Space.x2),
      SizedBox(
        // Grows with the user's text size so labels never clip.
        height: 64 + MediaQuery.textScalerOf(context).scale(46),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: CropPreset.all.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
          itemBuilder: (context, i) {
            final p = CropPreset.all[i];
            final isSel = p.id == selected.id;
            return Semantics(
              selected: isSel,
              button: true,
              label: '${p.label}, ${p.sizeLabel}',
              child: SizedBox(
                width: 132,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: Radii.cardAll,
                    side: BorderSide(
                      color: isSel ? context.colors.primary : context.ds.border,
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(p),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AspectGlyph(aspect: p.aspect, selected: isSel),
                          const Spacer(),
                          Text(
                            p.label,
                            style: context.text.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            p.sizeLabel,
                            style: context.text.bodySmall?.copyWith(
                              color: context.ds.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (selected.description != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.x2),
          child: Text(
            selected.description!,
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
        ),
    ],
  );
}

class _AspectGlyph extends StatelessWidget {
  const _AspectGlyph({required this.aspect, required this.selected});

  final double aspect;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const box = 26.0;
    final w = aspect >= 1 ? box : box * aspect;
    final h = aspect >= 1 ? box / aspect : box;
    final c = selected ? context.colors.primary : context.ds.textSecondary;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.frame,
    required this.faceGuide,
    required this.color,
  });

  final Rect frame;
  final bool faceGuide;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(frame),
    );
    canvas
      ..drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55))
      ..drawRect(
        frame,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    // Rule-of-thirds grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas
        ..drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid)
        ..drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
    }
    if (faceGuide) {
      final oval = Rect.fromCenter(
        center: Offset(frame.center.dx, frame.top + frame.height * 0.44),
        width: frame.width * 0.52,
        height: frame.height * 0.58,
      );
      canvas.drawOval(
        oval,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.faceGuide != faceGuide || old.color != color;
}
