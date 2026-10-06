import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';

/// Ink colours offered for drawn signatures.
enum SignatureInk {
  black(Color(0xFF111111), 'Black'),
  blue(Color(0xFF1A3DA8), 'Blue');

  const SignatureInk(this.color, this.label);
  final Color color;
  final String label;
}

/// A transparent PNG and its pixel size.
@immutable
class SignatureImage {
  const SignatureImage({
    required this.png,
    required this.width,
    required this.height,
  });

  final Uint8List png;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// Stroke width in logical pixels; constant, so pressure never matters.
const signatureStrokeWidth = 3.2;

/// Smooth path through [points]: quadratic curves with each sample as the
/// control point and the midpoints between samples as anchors.
Path smoothStrokePath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    final mid = (p + points[i + 1]) / 2;
    path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// Tight bounds of the drawn ink, including half the stroke width. Curves
/// stay inside their control points, so the sample bounds are exact enough.
/// Null when nothing was drawn.
Rect? signatureInkBounds(
  List<List<Offset>> strokes, {
  double strokeWidth = signatureStrokeWidth,
}) {
  double? l;
  double? t;
  double? r;
  double? b;
  for (final s in strokes) {
    for (final p in s) {
      l = l == null ? p.dx : math.min(l, p.dx);
      t = t == null ? p.dy : math.min(t, p.dy);
      r = r == null ? p.dx : math.max(r, p.dx);
      b = b == null ? p.dy : math.max(b, p.dy);
    }
  }
  if (l == null) return null;
  return Rect.fromLTRB(l, t!, r!, b!).inflate(strokeWidth / 2);
}

void _paintStrokes(
  Canvas canvas,
  List<List<Offset>> strokes,
  Color color,
  double strokeWidth,
) {
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final dot = Paint()
    ..color = color
    ..isAntiAlias = true;
  for (final s in strokes) {
    if (s.isEmpty) continue;
    if (s.length == 1) {
      canvas.drawCircle(s.first, strokeWidth / 2, dot);
    } else {
      canvas.drawPath(smoothStrokePath(s), line);
    }
  }
}

/// Renders [strokes] to a transparent PNG cropped to the ink (plus
/// [padding] logical px) at [pixelRatio]× resolution.
Future<SignatureImage?> renderSignaturePng(
  List<List<Offset>> strokes, {
  required Color color,
  double pixelRatio = 3,
  double strokeWidth = signatureStrokeWidth,
  double padding = 2,
}) async {
  final bounds = signatureInkBounds(
    strokes,
    strokeWidth: strokeWidth,
  )?.inflate(padding);
  if (bounds == null) return null;
  final width = math.max(1, (bounds.width * pixelRatio).ceil());
  final height = math.max(1, (bounds.height * pixelRatio).ceil());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelRatio)
    ..translate(-bounds.left, -bounds.top);
  _paintStrokes(canvas, strokes, color, strokeWidth);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return SignatureImage(
      png: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: width,
      height: height,
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// State of a [SignaturePad]: strokes, ink colour, undo and clear.
class SignaturePadController extends ChangeNotifier {
  final _strokes = <List<Offset>>[];
  SignatureInk _ink = SignatureInk.black;

  /// Samples closer than this (logical px) are dropped to reduce jitter.
  static const minDistance = 0.8;

  List<List<Offset>> get strokes =>
      List.unmodifiable(_strokes.map(List<Offset>.unmodifiable));
  bool get isEmpty => _strokes.every((s) => s.isEmpty);
  bool get canUndo => _strokes.isNotEmpty;

  SignatureInk get ink => _ink;
  set ink(SignatureInk value) {
    if (value == _ink) return;
    _ink = value;
    notifyListeners();
  }

  void begin(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void extend(Offset p) {
    if (_strokes.isEmpty) return begin(p);
    final s = _strokes.last;
    if ((s.last - p).distance < minDistance) return;
    s.add(p);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  /// Trimmed transparent PNG at [pixelRatio]×, or null when empty.
  Future<SignatureImage?> export({double pixelRatio = 3}) =>
      renderSignaturePng(_strokes, color: _ink.color, pixelRatio: pixelRatio);
}

/// On-screen signature canvas. Draw with a finger or stylus.
class SignaturePad extends StatelessWidget {
  const SignaturePad({required this.controller, super.key});

  final SignaturePadController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Signature area. Draw your signature here.',
    child: ClipRRect(
      borderRadius: Radii.cardAll,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: context.ds.border, width: 1.5),
          borderRadius: Radii.cardAll,
        ),
        child: GestureDetector(
          key: const ValueKey('signature-pad'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => controller.begin(d.localPosition),
          onPanUpdate: (d) => controller.extend(d.localPosition),
          child: CustomPaint(
            painter: _PadPainter(controller),
            child: Stack(
              children: [
                Positioned(
                  left: Space.x6,
                  right: Space.x6,
                  bottom: Space.x8,
                  child: IgnorePointer(
                    child: Container(height: 1, color: Colors.black26),
                  ),
                ),
                Positioned(
                  left: Space.x6,
                  bottom: Space.x8 + 4,
                  child: IgnorePointer(
                    child: Text(
                      '×',
                      style: context.text.titleLarge?.copyWith(
                        color: Colors.black38,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.controller) : super(repaint: controller);

  final SignaturePadController controller;

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(
    canvas,
    controller._strokes,
    controller.ink.color,
    signatureStrokeWidth,
  );

  @override
  bool shouldRepaint(_PadPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

/// Checkerboard backdrop that makes transparency visible behind a PNG.
class TransparencyBackdrop extends StatelessWidget {
  const TransparencyBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _CheckerPainter(), child: child);
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 8.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grey = Paint()..color = const Color(0xFFE6E6E6);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), grey);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}
