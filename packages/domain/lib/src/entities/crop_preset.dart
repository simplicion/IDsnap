import 'package:meta/meta.dart';

/// Fixed-aspect crop templates for photos and IDs (e.g. passport photos).
///
/// Presets are named by size term (passport size, stamp size…), never by
/// country: the same size is accepted in many places, and requirements differ
/// by agency — the UI must tell users to verify the official rules.
/// IDSnap does not validate biometric compliance (head size, background).
///
/// [id]s are persisted and must stay stable even when labels change.
@immutable
class CropPreset {
  const CropPreset({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    this.description,
    this.dpi = 300,
    this.headRatio,
    this.topMarginRatio = 0.09,
  });

  final String id;
  final String label;
  final double widthMm;
  final double heightMm;
  final String? description;
  final int dpi;

  /// Head height (chin to crown) as a fraction of photo height for portrait
  /// presets; `null` for documents. Used by automatic face framing.
  final double? headRatio;

  /// Gap above the crown as a fraction of photo height.
  final double topMarginRatio;

  bool get isPortrait => headRatio != null;

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
    label: 'Passport size photo',
    widthMm: 35,
    heightMm: 45,
    description: 'The most widely used passport photo size',
    headRatio: 0.75,
  );
  static const passportUs = CropPreset(
    id: 'passport_us',
    label: 'Square photo',
    widthMm: 50.8,
    heightMm: 50.8,
    description: '2 × 2 inch passport photo',
    headRatio: 0.6,
    topMarginRatio: 0.12,
  );
  static const visaChina = CropPreset(
    id: 'visa_33x48',
    label: 'Tall photo',
    description: 'Slightly taller than passport size, asked for by some forms',
    widthMm: 33,
    heightMm: 48,
    headRatio: 0.64,
  );
  static const idPhoto = CropPreset(
    id: 'id_30x40',
    label: 'ID photo',
    widthMm: 30,
    heightMm: 40,
    description: 'Small ID and form photo',
    headRatio: 0.7,
  );
  static const stampSize = CropPreset(
    id: 'stamp_20x25',
    label: 'Stamp size',
    widthMm: 20,
    heightMm: 25,
    description: 'Used on many exam and application forms',
    headRatio: 0.62,
    topMarginRatio: 0.1,
  );
  static const passportCanada = CropPreset(
    id: 'passport_canada',
    label: 'Large passport photo',
    widthMm: 50,
    heightMm: 70,
    headRatio: 0.48,
    topMarginRatio: 0.15,
  );
  static const profilePhoto = CropPreset(
    id: 'profile',
    label: 'Profile photo',
    widthMm: 100,
    heightMm: 100,
    dpi: 108,
    description: 'Square headshot for resumes, profiles and ID apps',
    headRatio: 0.5,
    topMarginRatio: 0.14,
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
    label: 'Letter',
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
    idPhoto,
    stampSize,
    visaChina,
    passportCanada,
    profilePhoto,
    idCard,
    a4,
    letter,
    square,
    photo4x6,
  ];
}
