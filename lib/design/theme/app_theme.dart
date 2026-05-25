import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import 'playa_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    final colors = const PlayaColorsExtension();

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PlayaColors.bg,
      canvasColor: PlayaColors.surface,

      // Color scheme (Material 3 foundation)
      colorScheme: const ColorScheme.dark(
        primary: PlayaColors.accent,
        surface: PlayaColors.surface,
        onSurface: PlayaColors.onSurface,
        error: PlayaColors.error,
      ),

      // Typography
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 16, color: PlayaColors.onSurface),
        bodyMedium: TextStyle(fontSize: 14, color: PlayaColors.onSurface),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: PlayaColors.onSurface),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: PlayaColors.onSurface),
      ),

      // Component themes
      cardTheme: CardThemeData(
        color: PlayaColors.surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayaRadii.md),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: PlayaColors.borderSubtle,
        thickness: 1,
        space: PlayaSpacing.md,
      ),

      // Extensions
      extensions: <ThemeExtension<dynamic>>[
        colors,
      ],

      // System UI
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PlayaColors.glass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PlayaRadii.md),
          borderSide: const BorderSide(color: PlayaColors.borderSubtle),
        ),
      ),
    );
  }
}
