import 'dart:typed_data';

import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/text_utils.dart';
import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';
import 'package:qr/qr.dart';

/// Builds standard payloads that every scanner app understands.
abstract final class QrPayload {
  /// `WIFI:T:WPA;S:<ssid>;P:<password>;H:true;;` with `\ ; , : "` escaped.
  static String wifi({
    required String ssid,
    String password = '',
    WifiSecurity security = WifiSecurity.wpa,
    bool hidden = false,
  }) {
    String esc(String v) => escapeBackslashes(v, ';,:"');
    final b = StringBuffer('WIFI:T:${security.code};S:${esc(ssid)};');
    if (security != WifiSecurity.open && password.isNotEmpty) {
      b.write('P:${esc(password)};');
    }
    if (hidden) b.write('H:true;');
    b.write(';');
    return b.toString();
  }

  static String contact(ContactCard card) => card.toVCard();

  static String email({required String to, String? subject, String? body}) =>
      EmailContent(
        '',
        to: [to.trim()],
        subject: cleanOrNull(subject),
        body: cleanOrNull(body),
      ).mailtoUri;

  static String phone(String number) =>
      PhoneContent('', number: number.trim()).telUri;

  /// `SMSTO:<number>:<message>` (the most widely supported form).
  static String sms({required String number, String? message}) {
    final n = number.trim().replaceAll(RegExp('[^0-9+*#]'), '');
    final m = message?.trim() ?? '';
    return m.isEmpty ? 'SMSTO:$n' : 'SMSTO:$n:$m';
  }

  /// Adds `https://` when the scheme is missing.
  static String url(String url) {
    final t = url.trim();
    if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t)) return t;
    return 'https://$t';
  }
}

/// QR error-correction levels; higher survives more damage but holds less.
enum QrErrorLevel {
  low('Low', '7%', QrErrorCorrectLevel.L),
  medium('Medium', '15%', QrErrorCorrectLevel.M),
  quartile('Quartile', '25%', QrErrorCorrectLevel.Q),
  high('High', '30%', QrErrorCorrectLevel.H);

  const QrErrorLevel(this.label, this.recovery, this.qrValue);

  final String label;

  /// Share of the symbol that can be damaged and still read.
  final String recovery;

  /// The `qr` package constant.
  final int qrValue;
}

/// A QR symbol as a square grid of dark/light modules.
@immutable
class QrMatrix {
  const QrMatrix._(this.size, this.version, this.level, this._dark);

  /// Encodes [data] (UTF-8, byte mode). Null when it doesn't fit in the
  /// largest QR version at [level].
  static QrMatrix? tryEncode(
    String data, {
    QrErrorLevel level = QrErrorLevel.medium,
  }) {
    try {
      final code = QrCode.fromData(
        data: data,
        errorCorrectLevel: level.qrValue,
      );
      final image = QrImage(code);
      final n = image.moduleCount;
      final dark = List<bool>.filled(n * n, false);
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          dark[r * n + c] = image.isDark(r, c);
        }
      }
      return QrMatrix._(n, image.typeNumber, level, dark);
    } on Object {
      return null;
    }
  }

  /// Modules per side (21 for version 1).
  final int size;

  /// QR version 1–40.
  final int version;
  final QrErrorLevel level;
  final List<bool> _dark;

  bool isDark(int row, int col) => _dark[row * size + col];

  /// Quiet zone recommended around the symbol, in modules.
  static const quietZone = 4;

  /// PNG of about [pixels] square (rounded to whole modules, never smaller
  /// than one pixel per module), black on white with a quiet zone.
  Uint8List toPng({int pixels = 1024}) {
    final total = size + quietZone * 2;
    final module = (pixels / total).floor().clamp(1, 1 << 12);
    final side = module * total;
    final image = img.Image(width: side, height: side, numChannels: 1);
    img.fill(image, color: img.ColorUint8.rgb(255, 255, 255));
    final black = img.ColorUint8.rgb(0, 0, 0);
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (!isDark(r, c)) continue;
        final x = (c + quietZone) * module;
        final y = (r + quietZone) * module;
        img.fillRect(
          image,
          x1: x,
          y1: y,
          x2: x + module - 1,
          y2: y + module - 1,
          color: black,
        );
      }
    }
    return img.encodePng(image);
  }
}
