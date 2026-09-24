import 'package:meta/meta.dart';

/// Fixed-aspect crop templates for photos and IDs (e.g. passport photos).
///
/// Sizes follow commonly published specifications, but requirements differ by
/// country and agency — the UI must tell users to verify the official rules.
/// DocScan does not validate biometric compliance (head size, background).
@immutable
class CropPreset {
  const CropPreset({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    this.description,
    this.dpi = 300,
  });

  final String id;
  final String label;
  final double widthMm;
  final double heightMm;
  final String? description;
  final int dpi;

  double get aspect => widthMm / heightMm;

  /// Output pixel size at [dpi].
  int get pixelWidth => (widthMm / 25.4 * dpi).round();
  int get pixelHeight => (heightMm / 25.4 * dpi).round();

  String get sizeLabel => widthMm == heightMm && widthMm == 50.8
      ? '2 × 2 in'
      : '${_fmt(widthMm)} × ${_fmt(heightMm)} mm';

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static const passportIntl = CropPreset(
    id: 'passport_35x45',
    label: 'Passport photo',
    widthMm: 35,
    heightMm: 45,
    description: 'Common size in India, UK, EU, Australia and more',
  );
  static const passportUs = CropPreset(
    id: 'passport_us',
    label: 'US passport / visa',
    widthMm: 50.8,
    heightMm: 50.8,
    description: '2 × 2 inch',
  );
  static const visaChina = CropPreset(
    id: 'visa_33x48',
    label: 'China visa',
    widthMm: 33,
    heightMm: 48,
  );
  static const stampSize = CropPreset(
    id: 'stamp_20x25',
    label: 'Stamp size',
    widthMm: 20,
    heightMm: 25,
    description: 'Used on many exam and application forms',
  );
  static const idCard = CropPreset(
    id: 'id_card',
    label: 'ID card',
    widthMm: 85.6,
    heightMm: 53.98,
    description: 'ISO/IEC 7810 ID-1 (credit card size)',
  );
  static const a4 = CropPreset(
    id: 'a4',
    label: 'A4 page',
    widthMm: 210,
    heightMm: 297,
    dpi: 200,
  );
  static const letter = CropPreset(
    id: 'letter',
    label: 'US Letter',
    widthMm: 215.9,
    heightMm: 279.4,
    dpi: 200,
  );
  static const square = CropPreset(
    id: 'square',
    label: 'Square 1:1',
    widthMm: 100,
    heightMm: 100,
    dpi: 108,
  );
  static const photo4x6 = CropPreset(
    id: 'photo_4x6',
    label: 'Photo 4 × 6 in',
    widthMm: 101.6,
    heightMm: 152.4,
  );

  static const List<CropPreset> all = [
    passportIntl,
    passportUs,
    visaChina,
    stampSize,
    idCard,
    a4,
    letter,
    square,
    photo4x6,
  ];
}
