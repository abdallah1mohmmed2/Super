import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const navy = Color(0xFF1E293B);
  static const emerald = Color(0xFF10B981);
  static const sky = Color(0xFF0EA5E9);
  static const paper = Color(0xFFF8FAFC);
  static ThemeData get light => ThemeData(
    useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: emerald, primary: navy, secondary: emerald, surface: paper),
    scaffoldBackgroundColor: paper,
    textTheme: GoogleFonts.tajawalTextTheme().apply(bodyColor: navy, displayColor: navy),
    cardTheme: CardThemeData(color: Colors.white, elevation: 1, shadowColor: navy.withValues(alpha: .08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    inputDecorationTheme: InputDecorationTheme(isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blueGrey.shade100)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: navy, elevation: 0, centerTitle: false),
  );
}
