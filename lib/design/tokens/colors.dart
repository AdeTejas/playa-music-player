import 'package:flutter/material.dart';

/// Playa Design System — premium matte palette.
///
/// Warm stone surfaces with layered graphite depth, pearl highlights,
/// and a restrained champagne accent.
class PlayaColors {
  const PlayaColors._();

  // ==================== BASE MATTE PALETTE ====================
  static const Color deepVoid = Color(0xFF060504);
  static const Color bg = Color(0xFF0C0B0A);
  static const Color surface = Color(0xFF151412);
  static const Color surfaceVariant = Color(0xFF1E1C19);
  static const Color card = Color(0xFF282522);

  /// Matte hardware tones (turntable, speaker housings)
  static const Color matteGraphite = Color(0xFF1C1A17);
  static const Color matteGunmetal = Color(0xFF302C28);
  static const Color matteSlate = Color(0xFF433E39);
  static const Color matteWarm = Color(0xFF2A2622);
  static const Color matteCool = Color(0xFF1A1D20);

  // Text — warm stone neutrals
  static const Color onBg = Color(0xFFEDE9E4);
  static const Color onSurface = Color(0xFFEDE9E4);
  static const Color onSurfaceVariant = Color(0xFFA39E97);

  static const Color onSurface2 = onSurfaceVariant;

  // ==================== ACCENT ====================
  /// Default: champagne gold — muted luxury, not neon
  static const Color accent = Color(0xFFC9A86A);

  // ==================== TRANSPARENT GLASS (warm matte tint) ====================
  static const Color glass = Color(0x42151412);
  static const Color glassStrong = Color(0x661E1C19);
  static const Color glassDeep = Color(0x54181614);
  static const Color glassSubtle = Color(0x300C0B0A);
  static const Color glassLight = Color(0x3824201C);

  static const Color deepPanel = Color(0xEE151412);
  static const Color deepPanelElevated = Color(0xF21E1C19);

  // ==================== BORDERS ====================
  static const Color borderSubtle = Color(0x1AFFF8F0);
  static const Color border = Color(0x33FFF8F0);
  static const Color borderStrong = Color(0x4DFFF8F0);

  // ==================== SEMANTIC COLORS ====================
  static const Color success = Color(0xFF6B9478);
  static const Color warning = Color(0xFFC9A04E);
  static const Color error = Color(0xFFB8727A);
  static const Color info = Color(0xFF7A9AA8);

  static const Color trackMuted = Color(0x18FFF8F0);
  static const Color sonic = Color(0xFF8A7A66);

  // ==================== OVERLAYS ====================
  static const Color overlay = Color(0x96000000);
  static const Color scrim = Color(0xD9000000);
}