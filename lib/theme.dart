import 'package:flutter/material.dart';

/// Colours from the existing Masomo brand: the app bar orange-brown and the
/// launcher icon's deep brown and golden "M".
class Brand {
  static const primary = Color(0xFFB3590A);
  static const deep = Color(0xFF8B3A0F);
  static const gold = Color(0xFFF7A21B);
  static const ink = Color(0xFF2A1E17);
  static const muted = Color(0xFF6E625A);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF7F4F1);
  static const line = Color(0xFFE6DED7);
  static const good = Color(0xFF2E7A4E);
  static const goodSoft = Color(0xFFE3F2E8);
  static const bad = Color(0xFFB0281F);
  static const badSoft = Color(0xFFFBE7E5);
  static const primarySoft = Color(0xFFF9EBDD);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Brand.primary).copyWith(
    primary: Brand.primary,
    onPrimary: Colors.white,
    secondary: Brand.gold,
    surface: Brand.surface,
    onSurface: Brand.ink,
    error: Brand.bad,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: Brand.background);
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.background,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.ink),
    ),
    textTheme: base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink),
    cardTheme: const CardThemeData(
      color: Brand.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Brand.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.line),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Brand.surface, indicatorColor: Brand.primarySoft),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: Brand.line),
      selectedColor: Brand.primarySoft,
    ),
  );
}
