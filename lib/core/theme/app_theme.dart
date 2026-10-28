import 'package:flutter/material.dart';

class AppTheme {
  static const teal = Color(0xFF0D3B4C);
  static const cyan = Color(0xFF1CA3C8);
  static const amber = Color(0xFFF59E0B);
  static const emergency = Color(0xFFDC2626);
  static const background = Color(0xFFF8FAFC);
  static const slate = Color(0xFF0F172A);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(seedColor: teal).copyWith(
      primary: teal,
      secondary: cyan,
      surface: background,
      error: emergency,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: teal,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cyan,
        foregroundColor: slate,
        minimumSize: const Size.fromHeight(48),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
