import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_codes/engine_codes.dart' show QrErrorLevel, QrMatrix;
import 'package:flutter/material.dart';

// "Show setup QR" (audit H-04): the standard `otpauth://` code for one
// account, so it can be moved to another phone or authenticator app without
// the full backup. Shown only after re-authentication.

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 Base32 without padding.
String base32Encode(Uint8List bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// The Key URI (`otpauth://totp/Issuer:label?secret=…`) for [account].
String otpAuthUri(OtpAccount account, Uint8List secret) {
  final issuer = account.issuer?.trim();
  final hasIssuer = issuer != null && issuer.isNotEmpty;
  final label = hasIssuer ? '$issuer:${account.label}' : account.label;
  final query = <String, String>{
    'secret': base32Encode(secret),
    if (hasIssuer) 'issuer': issuer,
    'algorithm': account.algorithm.label,
    'digits': '${account.digits}',
    if (account.type == OtpType.totp)
      'period': '${account.period}'
    else
      'counter': '${account.counter}',
  };
  final q = query.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'otpauth://${account.type.name}/${Uri.encodeComponent(label)}?$q';
}

/// The setup QR code with a plain warning about what it is.
class SetupQrDialog extends StatelessWidget {
  const SetupQrDialog({required this.title, required this.uri, super.key});

  final String title;
  final String uri;

  @override
  Widget build(BuildContext context) {
    final matrix = QrMatrix.tryEncode(uri, level: QrErrorLevel.low);
    return AlertDialog(
      title: Text('Setup QR · $title'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (matrix == null)
            const Text("This account's key is too long for a QR code.")
          else
            Semantics(
              label: 'Setup QR code for $title',
              image: true,
              child: SizedBox.square(
                dimension: 240,
                child: CustomPaint(painter: _QrPainter(matrix)),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Scan this with the authenticator on your other phone to add '
            'the same account there. Anyone who scans it can generate your '
            'codes — never share or screenshot it.',
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
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
