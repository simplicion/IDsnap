import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:flutter/material.dart';

/// Paints the photo outline, the head oval and the eye-level line of a
/// [GuideGeometry] (normalized coordinates) over a preview of any size.
class GuidePainter extends CustomPainter {
  GuidePainter({
    required this.guide,
    required this.color,
    this.dimOutside = true,
  });

  final GuideGeometry guide;
  final Color color;
  final bool dimOutside;

  static Rect toRect(NRect r, Size s) => Rect.fromLTWH(
    r.left * s.width,
    r.top * s.height,
    r.width * s.width,
    r.height * s.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final frame = toRect(guide.frame, size);
    final oval = toRect(guide.oval, size);
    if (dimOutside) {
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(frame),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );
    }
    canvas
      ..drawRect(
        frame,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      ..drawOval(
        oval,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    final y = guide.eyeLineY * size.height;
    final dash = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    for (var x = frame.left + 4; x < frame.right - 4; x += 12) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + 6).clamp(frame.left, frame.right - 4), y),
        dash,
      );
    }
  }

  @override
  bool shouldRepaint(GuidePainter old) =>
      old.guide != guide || old.color != color || old.dimOutside != dimOutside;
}
