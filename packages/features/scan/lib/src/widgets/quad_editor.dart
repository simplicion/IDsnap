import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';

/// Returns a user-facing problem with [quad], or `null` when it can be used
/// for perspective correction.
String? validateQuad(Quad quad) {
  if (!quad.isConvex) {
    return 'The corners cross over. Drag them into a clear four-sided shape.';
  }
  if (quad.area < 0.02) return 'The selected area is too small.';
  return null;
}

/// Image with four draggable corners and edge midpoints. A magnifier follows
/// the finger so corners can be placed precisely.
class QuadEditor extends StatefulWidget {
  const QuadEditor({
    required this.image,
    required this.imageSize,
    required this.quad,
    required this.onChanged,
    super.key,
  });

  final Uint8List image;
  final Size imageSize;
  final Quad quad;
  final ValueChanged<Quad> onChanged;

  @override
  State<QuadEditor> createState() => _QuadEditorState();
}

class _QuadEditorState extends State<QuadEditor> {
  static const _hitRadius = 44.0;
  static const _loupe = 104.0;
  static const _loupeLift = 96.0;

  int? _active;
  Offset? _finger;

  Offset _toScreen(NPoint p, Size s) => Offset(p.x * s.width, p.y * s.height);

  List<Offset> _handles(Size s) {
    final pts = [for (final p in widget.quad.points) _toScreen(p, s)];
    return [
      ...pts,
      for (var i = 0; i < 4; i++) Offset.lerp(pts[i], pts[(i + 1) % 4], 0.5)!,
    ];
  }

  void _start(Offset pos, Size size) {
    final handles = _handles(size);
    var best = -1;
    var bestDist = _hitRadius;
    for (var i = 0; i < handles.length; i++) {
      // Corners win ties with midpoints.
      final d = (handles[i] - pos).distance - (i < 4 ? 6 : 0);
      if (d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    setState(() {
      _active = best < 0 ? null : best;
      _finger = best < 0 ? null : pos;
    });
  }

  void _move(Offset pos, Offset delta, Size size) {
    final active = _active;
    if (active == null) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    var quad = widget.quad;
    NPoint shift(NPoint p) => NPoint(p.x + dx, p.y + dy);
    if (active < 4) {
      quad = quad.withPoint(active, shift(quad.points[active]));
    } else {
      final i = active - 4;
      final j = (i + 1) % 4;
      quad = quad
          .withPoint(i, shift(quad.points[i]))
          .withPoint(j, shift(quad.points[j]));
    }
    setState(() => _finger = pos);
    widget.onChanged(quad);
  }

  void _end() => setState(() {
    _active = null;
    _finger = null;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const pad = 20.0;
      final maxW = math.max(1, constraints.maxWidth - pad * 2);
      final maxH = math.max(1, constraints.maxHeight - pad * 2);
      final scale = math.min(
        maxW / widget.imageSize.width,
        maxH / widget.imageSize.height,
      );
      final size = Size(
        widget.imageSize.width * scale,
        widget.imageSize.height * scale,
      );
      final origin = Offset(
        (constraints.maxWidth - size.width) / 2,
        (constraints.maxHeight - size.height) / 2,
      );
      final valid = validateQuad(widget.quad) == null;
      final finger = _finger;
      final loupeBelow =
          finger != null && finger.dy + origin.dy < _loupe + _loupeLift;

      return Stack(
        children: [
          Positioned(
            left: origin.dx,
            top: origin.dy,
            width: size.width,
            height: size.height,
            child: Image.memory(
              widget.image,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy,
            width: size.width,
            height: size.height,
            child: Semantics(
              label:
                  'Page corners editor. Drag the round handles to the corners of the page.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _start(d.localPosition, size),
                onPanUpdate: (d) => _move(d.localPosition, d.delta, size),
                onPanEnd: (_) => _end(),
                onPanCancel: _end,
                child: CustomPaint(
                  size: size,
                  painter: _QuadPainter(
                    handles: _handles(size),
                    active: _active,
                    line: valid ? context.colors.primary : context.colors.error,
                    scrim: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
          if (finger != null)
            Positioned(
              left: origin.dx + finger.dx - _loupe / 2,
              top:
                  origin.dy +
                  finger.dy -
                  _loupe / 2 +
                  (loupeBelow ? _loupeLift : -_loupeLift),
              child: IgnorePointer(
                child: RawMagnifier(
                  size: const Size(_loupe, _loupe),
                  magnificationScale: 2.2,
                  focalPointOffset: Offset(
                    0,
                    loupeBelow ? -_loupeLift : _loupeLift,
                  ),
                  decoration: MagnifierDecoration(
                    shape: CircleBorder(
                      side: BorderSide(color: context.colors.primary, width: 3),
                    ),
                    shadows: const [
                      BoxShadow(blurRadius: 12, color: Colors.black38),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: context.colors.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.handles,
    required this.active,
    required this.line,
    required this.scrim,
  });

  final List<Offset> handles;
  final int? active;
  final Color line;
  final Color scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()..addPolygon(handles.sublist(0, 4), true);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(quad, Offset.zero);
    canvas
      ..drawPath(outside, Paint()..color = scrim)
      ..drawPath(
        quad,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    for (var i = 0; i < handles.length; i++) {
      final isCorner = i < 4;
      final isActive = i == active;
      final fill = Paint()..color = isActive ? line : Colors.white;
      final stroke = Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      if (isCorner) {
        final r = isActive ? 14.0 : 11.0;
        canvas
          ..drawCircle(handles[i], r, fill)
          ..drawCircle(handles[i], r, stroke);
      } else {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: handles[i], width: 22, height: 10),
          const Radius.circular(5),
        );
        canvas
          ..drawRRect(rect, fill)
          ..drawRRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.handles != handles || old.active != active || old.line != line;
}

/// Decodes [bytes] to read the image's pixel size.
Future<Size> decodeImageSize(Uint8List bytes) async {
  final image = await decodeImageFromList(bytes);
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  return size;
}
