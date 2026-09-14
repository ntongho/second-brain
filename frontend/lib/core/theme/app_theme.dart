import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

abstract final class AppTheme {
  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        bg: SbTokens.darkBg,
        surface: SbTokens.darkSurface,
        textHi: SbTokens.darkTextHi,
        textLo: SbTokens.darkTextLo,
        line: SbTokens.hairline,
        cta: SbTokens.primary,
        onCta: SbTokens.onPrimary,
      );

  static ThemeData light() => _base(
        brightness: Brightness.light,
        bg: SbTokens.lightBg,
        surface: SbTokens.lightSurface,
        textHi: SbTokens.lightTextHi,
        textLo: SbTokens.lightTextLo,
        line: const Color(0xFFE4E2DC),
        cta: SbTokens.lightTextHi,
        onCta: SbTokens.lightSurface,
      );

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color textHi,
    required Color textLo,
    required Color line,
    required Color cta,
    required Color onCta,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: cta,
      onPrimary: onCta,
      secondary: textLo,
      onSecondary: textHi,
      error: SbTokens.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textHi,
      outline: line,
    );
    final base = ThemeData(brightness: brightness).textTheme;
    final textTheme = base.apply(bodyColor: textHi, displayColor: textHi).copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontSize: SbTokens.display,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: textHi,
            letterSpacing: -0.4,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: SbTokens.title,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: textHi,
            letterSpacing: -0.3,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, color: textHi, letterSpacing: -0.1),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: SbTokens.body,
            height: 1.45,
            color: textHi,
            letterSpacing: -0.1,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: SbTokens.caption,
            height: 1.4,
            color: textLo,
            letterSpacing: 0,
          ),
        );
    final radius = BorderRadius.circular(SbTokens.radiusCard);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      canvasColor: bg,
      dividerColor: line,
      iconTheme: IconThemeData(color: textHi, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textHi,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: textLo, fontSize: 15),
        labelStyle: TextStyle(color: textLo, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: textHi, width: 1)),
        errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: SbTokens.danger)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 40),
          backgroundColor: cta,
          foregroundColor: onCta,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 40),
          foregroundColor: textHi,
          side: BorderSide(color: line),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textLo,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: textHi, linearMinHeight: 1),
    );
  }
}
