import 'package:flutter/material.dart';

/// 04 §4.1 design tokens. Dark-mode-first; warm-light fallback.
abstract final class SbTokens {
  static const primary = Color(0xFF4F46E5); // Deep Indigo
  static const primaryVariant = Color(0xFF6D28D9); // Electric Violet
  static const citation = Color(0xFF06B6D4); // Muted Cyan
  static const audio = Color(0xFFF59E0B); // Warm Amber (degraded banner)
  static const danger = Color(0xFFEF4444); // Soft Red (offline / errors)
  static const success = Color(0xFF22C55E);

  static const darkBg = Color(0xFF121214);
  static const darkSurface = Color(0xFF1E1E22);
  static const darkTextHi = Color(0xFFF4F4F5);
  static const darkTextLo = Color(0xFFA1A1AA);

  static const lightBg = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextHi = Color(0xFF18181B);
  static const lightTextLo = Color(0xFF71717A);

  static const radiusCard = 14.0;
  static const radiusBubble = 20.0;
  static const radiusFab = 28.0;
  static const motionMs = 180;
  static const grid = 4.0;

  static const display = 28.0;
  static const title = 20.0;
  static const body = 15.0;
  static const caption = 12.0;
}
