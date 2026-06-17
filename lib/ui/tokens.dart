// lib/ui/tokens.dart
// Temporary compatibility layer during Design System migration (Phase 3)
// New code should import from: package:playa_clean/design/design_system.dart

import '../design/design_system.dart';

// Re-export the new design system (recommended for new code)
export '../design/design_system.dart';

// --- Legacy constants (point to new design system values) ---
// These exist so old code doesn't break during migration.
const double kSp = 8.0;
const double kRadius = 14.0;
const double kTextXs = 12.0;
const double kTextSm = 14.0;
const double kTextMd = 16.0;
const double kTextLg = 18.0;
const double kTextXl = 20.0;

// Global UI Constants
const double kNavHeight = 64.0;
const double kIconMd = 24.0;

const kColorBg = PlayaColors.bg;
const kColorSurface = PlayaColors.surface;
const kColorCard = PlayaColors.card;
const kColorOn = PlayaColors.onSurface;
const kColorOn2 = PlayaColors.onSurfaceVariant;
const kColorDeepPanel = PlayaColors.deepPanel;
const kColorAppAccent = PlayaColors.accent;
const kColorGlassBlackTint = PlayaColors.glass;
const kColorGlassClear = PlayaColors.glassSubtle;
