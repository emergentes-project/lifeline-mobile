import 'package:flutter/material.dart';

class AppTheme {
  // Official Lifeline Color Palette from Style Guide
  static const teal = Color(0xFF0D3B4C); // Deep Rescue Teal (Primary Brand)
  static const cyan = Color(0xFF1CA3C8); // Lifeline Cyan (Interactive / AI)
  static const amber = Color(0xFFF59E0B); // Alert Amber (Offline / Warning)
  static const emergency = Color(0xFFDC2626); // Emergency Red (Critical / Urgency)
  static const background = Color(0xFFF8FAFC); // Clinical White (Background)
  static const slate = Color(0xFF0F172A); // Dark Slate (High contrast text)
  static const slateMuted = Color(0xFF64748B); // Muted Slate (Subtitles / Captions)
  static const border = Color(0xFFCBD5E1); // Neutral input and card borders
  static const borderLight = Color(0xFFE2E8F0); // Subtle card and divider borders
  static const cardBackground = Colors.white;
  static const surfaceMuted = Color(0xFFF1F5F9); // Light pill / container background

  // Soft badge backgrounds and foregrounds
  static const cyanSoft = Color(0xFFE0F2FE);
  static const cyanDark = Color(0xFF0369A1);
  static const amberSoft = Color(0xFFFEF3C7);
  static const amberDark = Color(0xFFB45309);
  static const redSoft = Color(0xFFFEE2E2);
  static const redDark = Color(0xFFB91C1C);
  static const tealSoft = Color(0xFFCCFBF1);
  static const tealDark = Color(0xFF0F766E);

  static const String fontHeading = 'Montserrat';
  static const String fontBody = 'Inter';

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: teal,
      onPrimary: Colors.white,
      secondary: cyan,
      onSecondary: Colors.white,
      error: emergency,
      onError: Colors.white,
      surface: cardBackground,
      onSurface: slate,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: teal,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        fontFamily: fontHeading,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardBackground,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: borderLight, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cyan,
        foregroundColor: Colors.white,
        disabledBackgroundColor: border,
        disabledForegroundColor: slateMuted,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: fontHeading,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: slate,
        disabledForegroundColor: slateMuted,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: const BorderSide(color: border, width: 1.4),
        textStyle: const TextStyle(
          fontFamily: fontHeading,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cyanDark,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          fontFamily: fontHeading,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: slate,
      contentTextStyle: const TextStyle(
        fontFamily: fontBody,
        color: Colors.white,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: cyan, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: emergency, width: 1.2),
      ),
      labelStyle: const TextStyle(
        fontFamily: fontBody,
        color: slateMuted,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        fontFamily: fontHeading,
        color: teal,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(
        fontFamily: fontBody,
        color: Color(0xFF94A3B8),
        fontSize: 14,
      ),
      helperStyle: const TextStyle(
        fontFamily: fontBody,
        color: slateMuted,
        fontSize: 12,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: cyan,
      unselectedItemColor: slateMuted,
      selectedLabelStyle: TextStyle(
        fontFamily: fontHeading,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: fontHeading,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 6,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      dragHandleColor: border,
      dragHandleSize: Size(44, 4),
    ),
    dividerTheme: const DividerThemeData(
      color: borderLight,
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: fontHeading,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: slate,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontHeading,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: slate,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontHeading,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: slate,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontFamily: fontHeading,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: slate,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontFamily: fontHeading,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: slate,
      ),
      titleSmall: TextStyle(
        fontFamily: fontHeading,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: slate,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 15,
        color: slate,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        color: slate,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 12,
        color: slateMuted,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        fontFamily: fontHeading,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: slate,
      ),
    ),
  );
}
