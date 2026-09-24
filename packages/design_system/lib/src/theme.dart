import 'package:docscan_design_system/src/tokens.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Material 3 themes built from DESIGN.md tokens. Uses the platform system
/// font (Roboto / SF) — nothing is fetched at runtime.
abstract final class AppTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: Palette.blue600,
      onPrimary: Colors.white,
      primaryContainer: Palette.blue50,
      onPrimaryContainer: Palette.blue900,
      secondary: Palette.teal600,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFDDF5F1),
      onSecondaryContainer: Color(0xFF053B35),
      tertiary: Palette.amber600,
      onTertiary: Colors.white,
      error: Palette.red700,
      onError: Colors.white,
      errorContainer: Color(0xFFFDE7E5),
      onErrorContainer: Color(0xFF5C0F09),
      surface: Colors.white,
      onSurface: Palette.ink,
      onSurfaceVariant: Palette.slate,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFAFBFC),
      surfaceContainer: Palette.mist,
      surfaceContainerHigh: Palette.cloud,
      surfaceContainerHighest: Color(0xFFE6EAF1),
      outline: Color(0xFFB9C1CE),
      outlineVariant: Palette.line,
      scrim: Colors.black,
      inverseSurface: Palette.ink,
      onInverseSurface: Palette.snow,
      inversePrimary: Palette.blue300,
    ),
    ds: DsColors.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: Palette.blue300,
      onPrimary: Palette.blue900,
      primaryContainer: Color(0xFF223A78),
      onPrimaryContainer: Color(0xFFDCE5FF),
      secondary: Palette.teal300,
      onSecondary: Color(0xFF003731),
      secondaryContainer: Color(0xFF0F4B44),
      onSecondaryContainer: Color(0xFFC4F2EA),
      tertiary: Palette.amber300,
      onTertiary: Color(0xFF3F2A00),
      error: Palette.red300,
      onError: Color(0xFF5C0F09),
      errorContainer: Color(0xFF5A1D18),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Palette.nightSurface,
      onSurface: Palette.snow,
      onSurfaceVariant: Palette.fog,
      surfaceContainerLowest: Color(0xFF0C0E11),
      surfaceContainerLow: Color(0xFF15181D),
      surfaceContainer: Palette.nightSurface,
      surfaceContainerHigh: Palette.nightVariant,
      surfaceContainerHighest: Color(0xFF2E3440),
      outline: Color(0xFF5A6373),
      outlineVariant: Palette.nightLine,
      scrim: Colors.black,
      inverseSurface: Palette.snow,
      onInverseSurface: Palette.ink,
      inversePrimary: Palette.blue600,
    ),
    ds: DsColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required DsColors ds,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 28,
            height: 34 / 28,
            fontWeight: FontWeight.w600,
          ),
          headlineSmall: const TextStyle(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            height: 24 / 17,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: const TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: const TextStyle(fontSize: 16, height: 24 / 16),
          bodyMedium: const TextStyle(fontSize: 14, height: 20 / 14),
          bodySmall: const TextStyle(fontSize: 12.5, height: 18 / 12.5),
          labelLarge: const TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: const TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    const buttonShape = RoundedRectangleBorder(borderRadius: Radii.buttonAll);
    const minButton = Size(64, 52);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: ds.canvas,
      extensions: [ds],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: ds.canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardAll,
          side: BorderSide(color: ds.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minButton,
          shape: buttonShape,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Space.x5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minButton,
          shape: buttonShape,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x4,
        ),
        border: const OutlineInputBorder(
          borderRadius: Radii.buttonAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.buttonAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.buttonAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        side: BorderSide(color: ds.border),
        labelStyle: text.labelLarge?.copyWith(fontSize: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.buttonAll),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dividerTheme: DividerThemeData(color: ds.border, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
        minVerticalPadding: Space.x3,
        iconColor: scheme.onSurfaceVariant,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
