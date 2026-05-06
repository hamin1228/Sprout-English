import 'package:flutter/material.dart';

/// AI English Learning App 공통 테마 및 색상
class AppTheme {
  // Primary 색상 - HTML 디자인의 #137fec
  static const Color primary = Color(0xFF137FEC);
  
  // 배경 색상
  static const Color backgroundLight = Color(0xFFF6F7F8);
  static const Color backgroundDark = Color(0xFF101922);
  
  // 텍스트 색상
  static const Color textDark = Color(0xFF111418);
  static const Color textLight = Colors.white;
  static const Color textSecondary = Color(0xFF617589);
  
  // 추가 색상
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFFFC107);
  static const Color accent = Color(0xFF50E3C2);
  
  // 보더 색상
  static Color get borderLight => Colors.black.withOpacity(0.1);
  static Color get borderDark => Colors.white.withOpacity(0.1);
  
  /// Material 3 라이트 테마
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: primary,
      surface: Colors.white,
      background: backgroundLight,
    ),
    scaffoldBackgroundColor: backgroundLight,
    fontFamily: 'Lexend',
    
    // AppBar 테마
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: textDark),
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        fontFamily: 'Lexend',
      ),
    ),
    
    // Card 테마
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderLight),
      ),
    ),
    
    // Text 테마
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textDark,
        fontFamily: 'Lexend',
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textDark,
        fontFamily: 'Lexend',
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: textDark,
        fontFamily: 'Lexend',
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: textDark,
        fontFamily: 'Lexend',
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textSecondary,
        fontFamily: 'Lexend',
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: textSecondary,
        fontFamily: 'Lexend',
      ),
    ),
    
    // ElevatedButton 테마
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lexend',
        ),
      ),
    ),
  );
  
  /// Material 3 다크 테마  
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: primary,
      surface: const Color(0xFF1C1C1E),
      background: backgroundDark,
    ),
    scaffoldBackgroundColor: backgroundDark,
    fontFamily: 'Lexend',
    
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundDark,
      elevation: 0,
      iconTheme: IconThemeData(color: textLight),
      titleTextStyle: TextStyle(
        color: textLight,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        fontFamily: 'Lexend',
      ),
    ),
    
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1C1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderDark),
      ),
    ),
  );
}
