import 'package:flutter/material.dart';

/// Raw palette. Widgets never use these directly — use [DsColors] via
/// `context.ds` or the Material [ColorScheme].
abstract final class Palette {
  static const blue600 = Color(0xFF2457D6);
  static const blue300 = Color(0xFF8EABFF);
  static const blue50 = Color(0xFFEAF0FF);
  static const blue900 = Color(0xFF14234A);
  static const teal600 = Color(0xFF0E8A7E);
  static const teal300 = Color(0xFF6FD6C8);
  static const amber600 = Color(0xFF9A5B00);
  static const amber300 = Color(0xFFFFC36B);
  static const green700 = Color(0xFF197A4A);
  static const green300 = Color(0xFF69D5A0);
  static const red700 = Color(0xFFB42318);
  static const red300 = Color(0xFFFF8D86);
  static const ink = Color(0xFF171A21);
  static const slate = Color(0xFF5F6877);
  static const mist = Color(0xFFF7F8FA);
  static const cloud = Color(0xFFEEF1F6);
  static const line = Color(0xFFDDE2EA);
  static const night = Color(0xFF101216);
  static const nightSurface = Color(0xFF191C22);
  static const nightVariant = Color(0xFF252A33);
  static const nightLine = Color(0xFF343B47);
  static const snow = Color(0xFFF3F5F8);
  static const fog = Color(0xFFB4BBC7);
}

/// 4dp spacing scale.
abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;

  /// Horizontal page gutter on phones.
  static const double gutter = 16;
}

abstract final class Radii {
  static const double sm = 8;
  static const double button = 12;
  static const double card = 16;
  static const double sheet = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
}

/// Semantic colors not covered by [ColorScheme].
@immutable
class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.textSecondary,
    required this.border,
    required this.canvas,
    required this.pdf,
    required this.image,
    required this.text,
    required this.office,
  });

  static const light = DsColors(
    success: Palette.green700,
    onSuccess: Colors.white,
    successContainer: Color(0xFFE3F5EB),
    warning: Palette.amber600,
    warningContainer: Color(0xFFFFF1DC),
    textSecondary: Palette.slate,
    border: Palette.line,
    canvas: Palette.mist,
    pdf: Color(0xFFD14343),
    image: Color(0xFF7A4FD6),
    text: Color(0xFF3B6FD9),
    office: Color(0xFF1C8C5E),
  );

  static const dark = DsColors(
    success: Palette.green300,
    onSuccess: Color(0xFF06331D),
    successContainer: Color(0xFF123A27),
    warning: Palette.amber300,
    warningContainer: Color(0xFF3A2A10),
    textSecondary: Palette.fog,
    border: Palette.nightLine,
    canvas: Palette.night,
    pdf: Color(0xFFFF8A80),
    image: Color(0xFFC3A8FF),
    text: Color(0xFF9BB8FF),
    office: Color(0xFF7ADBB0),
  );

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color textSecondary;
  final Color border;
  final Color canvas;

  /// File-type accent colors (always paired with an icon + label).
  final Color pdf;
  final Color image;
  final Color text;
  final Color office;

  @override
  DsColors copyWith({Color? success}) => this;

  @override
  DsColors lerp(DsColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DsColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      textSecondary: l(textSecondary, other.textSecondary),
      border: l(border, other.border),
      canvas: l(canvas, other.canvas),
      pdf: l(pdf, other.pdf),
      image: l(image, other.image),
      text: l(text, other.text),
      office: l(office, other.office),
    );
  }
}

extension DsContext on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
