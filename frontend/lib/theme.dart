import 'package:flutter/material.dart';

// Google Fonts package for loading the Inter typeface used throughout the app
import 'package:google_fonts/google_fonts.dart';

/// AgroMind design tokens and theme configuration.
class AppTheme {
  // Private constructor — this class is never instantiated,
  // all members are static and accessed directly via AppTheme.*
  AppTheme._();

  // ---- Brand Colors ----
  // Deep dark background — the base layer of the dark glassmorphic design
  static const Color deepDark = Color(0xFF0F172A);

  // Surface color for cards and panels sitting above the background
  static const Color surface = Color(0xFF1E293B);

  // Lighter surface variant for hover states and nested elements
  static const Color surfaceLight = Color(0xFF334155);

  // Primary accent — Electric Blue used for CTAs, active states, and highlights
  static const Color accent = Color(0xFF3B82F6);

  // Lighter accent variant used for secondary highlights and tab indicators
  static const Color accentLight = Color(0xFF60A5FA);

  // Primary text color — near-white for headings and important content
  static const Color textPrimary = Color(0xFFF1F5F9);

  // Secondary text color — muted slate for subtitles and helper text
  static const Color textSecondary = Color(0xFF94A3B8);

  // Semantic colors for status indicators and feedback messages
  static const Color success = Color(0xFF22C55E);  // Green — analysis complete, valid state
  static const Color warning = Color(0xFFFBBF24);  // Amber — caution, partial results
  static const Color error = Color(0xFFEF4444);    // Red — failures, validation errors

  // Border color for card outlines and input field borders
  static const Color border = Color(0xFF334155);

  // ---- Glassmorphic Decoration ----
  // Default glass card style — subtle white tint with rounded corners and soft border
  // Applied to panels, cards, and overlays throughout the app
  static BoxDecoration get glassDecoration => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),   // 6% white overlay for glass effect
        borderRadius: BorderRadius.circular(16),        // 16px radius on all corners
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),  // Faint white border for depth
        ),
      );

  // Hover state glass decoration — brighter tint and accent-colored border
  // Swapped in when the user hovers over an interactive glass card
  static BoxDecoration get glassDecorationHover => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),    // 10% white — slightly more visible
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),        // Accent border signals interactivity
        ),
      );

  // Dashed border decoration used for empty states and drop zones
  // (e.g. the "no projects yet" placeholder on the dashboard)
  static BoxDecoration get dashedDecoration => BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: textSecondary.withValues(alpha: 0.4), // Muted dashed outline
          width: 2,
        ),
      );

  // ---- Theme Data ----
  static ThemeData get darkTheme {
    // Apply Inter font to the entire Material text theme as the base
    final baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: deepDark,  // All screens use deepDark as their background
      colorScheme: const ColorScheme.dark(
        primary: accent,       // Primary actions (buttons, FABs)
        secondary: accentLight, // Secondary actions and indicators
        surface: surface,      // Card and dialog backgrounds
        error: error,          // Error states and validation messages
      ),

      // Override individual text styles to enforce AgroMind's type hierarchy
      textTheme: baseTextTheme.copyWith(
        // Hero text — large display headings on the landing screen
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
        ),
        // Section headings — used for major screen titles
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        // Sub-section headings — used for card titles and panel headers
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        // Large titles — used for dialog headers and prominent labels
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        // Medium titles — used for list item headers and tab labels
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w500,
        ),
        // Body text styles — primary for content, secondary for supporting text
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: textPrimary),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: textSecondary),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: textSecondary),
      ),

      // AppBar styling — flat, dark, no elevation to blend with the background
      appBarTheme: AppBarTheme(
        backgroundColor: deepDark,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),

      // Filled accent button — used for primary CTAs like "Analyze" and "Create"
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),  // 12px radius for buttons
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Outlined button — used for secondary actions like "Cancel" and "Delete"
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: const BorderSide(color: accent),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Input field styling — filled surface with accent focus border
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,  // Surface-colored background for all text fields
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),  // Subtle border when unfocused
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),  // Accent border on focus
        ),
        hintStyle: GoogleFonts.inter(color: textSecondary),  // Muted hint text
      ),

      // Dialog styling — surface background with rounded corners matching cards
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}