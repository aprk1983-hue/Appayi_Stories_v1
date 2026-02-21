import 'package:flutter/material.dart';
import 'package:audio_story_app/utils/app_fonts.dart';

class AppTheme {
  static const String headingFont = AppFonts.heading;
  static const String bodyFont    = AppFonts.body;

  static TextTheme _textTheme(Color color) {
    final base = TextStyle(fontFamily: bodyFont, color: color);
    final head = TextStyle(fontFamily: headingFont, fontWeight: FontWeight.w700, color: color);

    return TextTheme(
      // Headings in heading font
      displayLarge:  head.copyWith(fontSize: 48),
      displayMedium: head.copyWith(fontSize: 40),
      displaySmall:  head.copyWith(fontSize: 34),
      headlineLarge: head.copyWith(fontSize: 28),
      headlineMedium:head.copyWith(fontSize: 24),
      headlineSmall: head.copyWith(fontSize: 20),

      // Everything else in body font
      titleLarge:  base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      titleMedium: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall:  base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),

      bodyLarge:   base.copyWith(fontSize: 16),
      bodyMedium:  base.copyWith(fontSize: 14),
      bodySmall:   base.copyWith(fontSize: 12),

      labelLarge:  base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: base.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
      labelSmall:  base.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
    );
  }

  static ThemeData get darkTheme {
    final cs = ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark);
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: cs,
      // Make body font the global default
      fontFamily: bodyFont,
      scaffoldBackgroundColor: const Color(0xFF0E0E12),
      textTheme: _textTheme(Colors.white),
      primaryTextTheme: _textTheme(Colors.white),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        hintStyle: TextStyle(fontFamily: bodyFont, color: Colors.white.withOpacity(0.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final cs = ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light);
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: cs,
      fontFamily: bodyFont,
      textTheme: _textTheme(Colors.black87),
      primaryTextTheme: _textTheme(Colors.white),
      appBarTheme: AppBarTheme(backgroundColor: cs.primary, foregroundColor: Colors.white, elevation: 0),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
