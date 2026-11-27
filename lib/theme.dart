import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const plum = Color(0xFF4E2343);
  static const plumDeep = Color(0xFF2B1530);
  static const blush = Color(0xFFFBEFEC);
  static const card = Color(0xFFFFFAF8);
  static const ink = Color(0xFF2A1823);
  static const mute = Color(0xFF7A5F6D);
  static const line = Color(0xFFECD4D0);
  static const gold = Color(0xFFF0AC2E);
  static const rose = Color(0xFFC2416B);
  static const chip = Color(0xFFF4DCD8);
}

TextStyle serif(double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.fraunces(fontSize: size, fontWeight: weight, color: color, height: 1.1);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.plum,
    brightness: b,
    primary: dark ? const Color(0xFFEE7FA3) : AppColors.plum,
    secondary: AppColors.rose,
    tertiary: AppColors.gold,
    surface: dark ? const Color(0xFF17101A) : AppColors.blush,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: GoogleFonts.karlaTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      titleTextStyle: serif(22, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF231928) : AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? const Color(0xFF3A2A3F) : AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? const Color(0xFF3A2A3F) : AppColors.line),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
  );
}
