# Playa Design System

## Status
- **Phase 1 Complete**: Foundation tokens + Theme + GlassPanel
- **Phase 2 Complete**: Core reusable components (PlayaCard, PlayaSettingsTile, PlayaButton)
- Migration from old `lib/ui/tokens.dart` has begun (backward compatible re-exports)

## Structure

```
lib/design/
├── tokens/
│   ├── colors.dart          # Semantic color system (Jedi Survivor Coruscant Paint inspired)
│   ├── spacing.dart
│   ├── radii.dart
│   ├── effects.dart         # Glass variants, shadows
│   └── typography.dart
├── theme/
│   ├── app_theme.dart
│   └── playa_colors.dart    # ThemeExtension
└── components/
    ├── glass_panel.dart
    ├── playa_card.dart
    ├── playa_settings_tile.dart
    └── playa_button.dart
```

## Usage

### New Code (Recommended)

```dart
import 'package:playa_clean/design/design_system.dart';

// Colors
PlayaColors.glass
PlayaColors.accent

// Effects
PlayaEffects.glass()

// Components
GlassPanel(...)
PlayaCard(...)
PlayaSettingsTile(...)
PlayaButton(...)

// Theme access
final colors = Theme.of(context).extension<PlayaColorsExtension>()!;
```

### During Migration (Old code still works)

Old imports from `lib/ui/tokens.dart` will continue to work for now.

## Next Steps

- **Phase 3**: Systematic migration of major screens (Settings, Library, Player)
- Add more components as needed (Chips, Bottom Sheets, Dialogs, etc.)
- Remove legacy constants from `lib/ui/tokens.dart`
- Build internal Theme Preview / Design System showcase screen

## Rules

1. **Never** hardcode colors outside of `tokens/colors.dart`
2. Prefer `GlassPanel` over raw `Container` for surfaces
3. Use semantic names (`PlayaColors.glass`) instead of raw hex values
4. All new UI work must go through the design system
