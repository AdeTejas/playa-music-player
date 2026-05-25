import 'package:flutter/material.dart';

/// Playa Design System - Semantic Colors
///
/// This is the single source of truth for all colors in the app.
/// Never use raw Color(0xFF...) values outside of this file.
class PlayaColors {
  const PlayaColors._();

  // ==================== BASE PALETTE ====================
  static const Color bg = Color(0xFF06070A);
  static const Color surface = Color(0xFF14161B);
  static const Color surfaceVariant = Color(0xFF1B1F26);
  static const Color card = Color(0xFF1F232B);

  // Text colors
  static const Color onBg = Color(0xFFE8DCCA);
  static const Color onSurface = Color(0xFFE8DCCA);
  static const Color onSurfaceVariant = Color(0xFFA68B6C);
  
  /// Compatibility alias for onSurfaceVariant
  static const Color onSurface2 = onSurfaceVariant;

  // ==================== ACCENT ====================
  // Default accent (can be overridden at runtime via ThemeExtension)
  static const Color accent = Color(0xFF00E5FF);

  // ==================== GLASS SYSTEM ====================
  /// Light glass overlay (used for subtle highlights)
  static const Color glassLight = Color(0x0DFFFFFF);

  /// Standard dark glass tint (most common)
  static const Color glass = Color(0x2A06070A);

  /// Stronger glass for modals / important surfaces
  static const Color glassStrong = Color(0x4006070A);

  /// Very subtle glass (used on nav bars, toolbars)
  static const Color glassSubtle = Color(0x0806070A);

  // ==================== BORDERS ====================
  static const Color borderSubtle = Color(0x1AFFFFFF);
  static const Color border = Color(0x33FFFFFF);
  static const Color borderStrong = Color(0x4DFFFFFF);

  // ==================== SEMANTIC COLORS ====================
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFEF5350);
  static const Color info = Color(0xFF29B6F6);

  // ==================== OVERLAYS ====================
  static const Color overlay = Color(0x80000000);
  static const Color scrim = Color(0xB3000000);
}
