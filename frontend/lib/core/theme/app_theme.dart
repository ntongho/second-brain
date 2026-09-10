import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:second_brain/core/theme/tokens.dart';

abstract final class AppTheme {
  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        bg: SbTokens.darkBg,
        surface: SbTokens.darkSurface,
        textHi: SbTokens.darkTextHi,
        textLo: SbTokens.darkTextLo,
      );

  static ThemeData light() => _base(
        brightness: Brightness.light,
        bg: SbTokens.lightBg,
        surface: SbTokens.lightSurface,
        textHi: SbTokens.lightTextHi,
        textLo: SbTokens.lightTextLo,
      );

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color textHi,
    required Color textLo,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: SbTokens.primary,
      onPrimary: Colors.white,
      secondary: SbTokens.primaryVariant,
      onSecondary: Colors.white,
      error: SbTokens.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textHi,
    );
    final baseText = GoogleFonts.interTextTheme(ThemeData(brightness: brightness).textTheme);
    final textTheme = baseText.apply(bodyColor: textHi, displayColor: textHi).copyWith(
      displaySmall: GoogleFonts.inter(
        fontSize: SbTokens.display,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        color: textHi,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: SbTokens.title,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        color: textHi,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: textHi),
      bodyMedium: GoogleFonts.inter(
        fontSize: SbTokens.body,
        height: 22 / 15,
        color: textHi,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: SbTokens.caption,
        height: 16 / 12,
        color: textLo,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      canvasColor: bg,
      iconTheme: IconThemeData(color: textHi),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textHi,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SbTokens.radiusCard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: GoogleFonts.inter(color: textLo),
        labelStyle: GoogleFonts.inter(color: textLo),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SbTokens.radiusCard),
          borderSide: BorderSide(color: textLo.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SbTokens.radiusCard),
          borderSide: BorderSide(color: textLo.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SbTokens.radiusCard),
          borderSide: const BorderSide(color: SbTokens.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SbTokens.radiusCard),
          borderSide: const BorderSide(color: SbTokens.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          backgroundColor: SbTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SbTokens.radiusCard),
          ),
        ),
      ),
    );
  }
}
