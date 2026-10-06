import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/parsers/contact.dart';
import 'package:engine_codes/src/parsers/event.dart';
import 'package:engine_codes/src/parsers/id_card.dart';
import 'package:engine_codes/src/parsers/payment.dart';
import 'package:engine_codes/src/parsers/product.dart';
import 'package:engine_codes/src/parsers/simple.dart';
import 'package:engine_codes/src/symbology.dart';

/// Turns a scanned payload into typed content. Pure, offline, and never
/// throws: anything unrecognized or malformed becomes [TextContent].
abstract final class CodeParser {
  /// Longest payload parsed structurally; longer input is shown as text.
  static const maxStructuredLength = 16 * 1024;

  static CodeContent parseCode(ScannedCode code) =>
      parse(code.raw, symbology: code.symbology);

  static CodeContent parse(
    String raw, {
    CodeSymbology symbology = CodeSymbology.qr,
  }) {
    try {
      return _parse(raw, symbology) ?? TextContent(raw);
    } on Object {
      return TextContent(raw);
    }
  }

  static CodeContent? _parse(String raw, CodeSymbology symbology) {
    final t = raw.trim();
    if (t.isEmpty || t.length > maxStructuredLength) return null;

    if (symbology.product || symbology == CodeSymbology.itf) {
      final product = parseProduct(raw, symbology);
      if (product != null) return product;
    }

    if (t.startsWith('@') || symbology == CodeSymbology.pdf417) {
      final id = parseIdCard(
        raw,
        fromPdf417: symbology == CodeSymbology.pdf417,
      );
      if (id != null) return id;
    }

    final lower = t.length > 16
        ? t.substring(0, 16).toLowerCase()
        : t.toLowerCase();
    bool starts(String p) => lower.startsWith(p);

    if (starts('wifi:')) return parseWifi(raw);
    if (starts('mecard:')) return parseMecard(raw);
    if (starts('begin:vcard')) return parseVCard(raw);
    if (starts('begin:vcalendar') || starts('begin:vevent')) {
      return parseEvent(raw);
    }
    if (starts('matmsg:') || starts('mailto:') || starts('smtp:')) {
      return parseEmail(raw);
    }
    if (starts('tel:')) return parsePhone(raw);
    if (starts('smsto:') ||
        starts('mmsto:') ||
        starts('sms:') ||
        starts('mms:')) {
      return parseSms(raw);
    }
    if (starts('geo:')) return parseGeo(raw);
    if (starts('otpauth://')) return parseOtpAuth(raw);
    if (starts('bcd\n') || starts('bcd\r') || starts('payto://')) {
      return parsePayment(raw);
    }
    if (RegExp(r'^[a-z][a-z0-9+.-]*://pay\?').hasMatch(lower)) {
      final payment = parsePayment(raw);
      if (payment != null) return payment;
    }
    if (starts('mebkm:') ||
        starts('urlto:') ||
        starts('http://') ||
        starts('https://') ||
        starts('www.')) {
      return parseUrl(raw);
    }
    if (isEmailAddress(raw)) return parseEmail(raw);
    return null;
  }
}
