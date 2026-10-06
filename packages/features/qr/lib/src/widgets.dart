import 'package:engine_codes/engine_codes.dart';
import 'package:flutter/material.dart';

IconData kindIcon(CodeKind kind) => switch (kind) {
  CodeKind.text => Icons.notes_rounded,
  CodeKind.url => Icons.link_rounded,
  CodeKind.wifi => Icons.wifi_rounded,
  CodeKind.contact => Icons.contact_page_rounded,
  CodeKind.email => Icons.email_rounded,
  CodeKind.phone => Icons.phone_rounded,
  CodeKind.sms => Icons.sms_rounded,
  CodeKind.geo => Icons.place_rounded,
  CodeKind.event => Icons.event_rounded,
  CodeKind.otpAuth => Icons.shield_rounded,
  CodeKind.payment => Icons.payments_rounded,
  CodeKind.product => Icons.qr_code_rounded,
  CodeKind.idCard => Icons.badge_rounded,
};

/// Draws a [QrMatrix] with a white quiet zone, scaled to fit.
class QrMatrixView extends StatelessWidget {
  const QrMatrixView(this.matrix, {super.key, this.size = 240});

  final QrMatrix matrix;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'QR code preview',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _QrPainter(matrix)),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.matrix);

  final QrMatrix matrix;

  @override
  void paint(Canvas canvas, Size size) {
    final total = matrix.size + QrMatrix.quietZone * 2;
    final module = size.shortestSide / total;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var r = 0; r < matrix.size; r++) {
      for (var c = 0; c < matrix.size; c++) {
        if (!matrix.isDark(r, c)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (c + QrMatrix.quietZone) * module,
            (r + QrMatrix.quietZone) * module,
            module + 0.5,
            module + 0.5,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => !identical(old.matrix, matrix);
}
