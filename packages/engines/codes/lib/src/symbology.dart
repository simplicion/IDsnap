import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Barcode symbologies the scanner reports. Labels are generic terms.
enum CodeSymbology {
  qr('QR code', twoDimensional: true),
  dataMatrix('Data Matrix', twoDimensional: true),
  aztec('Aztec', twoDimensional: true),
  pdf417('PDF417', twoDimensional: true),
  ean13('EAN-13', product: true),
  ean8('EAN-8', product: true),
  upcA('UPC-A', product: true),
  upcE('UPC-E', product: true),
  code128('Code 128'),
  code39('Code 39'),
  code93('Code 93'),
  itf('ITF'),
  codabar('Codabar'),
  unknown('Barcode');

  const CodeSymbology(
    this.label, {
    this.twoDimensional = false,
    this.product = false,
  });

  final String label;

  /// QR, Data Matrix, Aztec, PDF417.
  final bool twoDimensional;

  /// Retail product numbers (EAN/UPC). ITF-14 is handled separately.
  final bool product;

  /// Tolerant lookup by [name] (history JSON); [unknown] when missing.
  static CodeSymbology byName(String? name) => CodeSymbology.values.firstWhere(
    (s) => s.name == name,
    orElse: () => CodeSymbology.unknown,
  );
}

/// One code found by a scanner: its text payload and symbology.
@immutable
class ScannedCode {
  const ScannedCode({required this.raw, required this.symbology, this.bytes});

  /// Builds a code from a scanner result. When the scanner has no text for a
  /// binary payload, the bytes are shown as Latin-1 text.
  factory ScannedCode.from({
    required String? rawValue,
    required CodeSymbology symbology,
    Uint8List? bytes,
  }) {
    final raw = (rawValue != null && rawValue.isNotEmpty)
        ? rawValue
        : (bytes == null ? '' : String.fromCharCodes(bytes));
    return ScannedCode(raw: raw, symbology: symbology, bytes: bytes);
  }

  final String raw;
  final CodeSymbology symbology;
  final Uint8List? bytes;

  @override
  bool operator ==(Object other) =>
      other is ScannedCode && other.raw == raw && other.symbology == symbology;

  @override
  int get hashCode => Object.hash(raw, symbology);

  @override
  String toString() => 'ScannedCode(${symbology.name}, ${raw.length} chars)';
}
