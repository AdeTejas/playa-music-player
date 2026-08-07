import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../utils/accent_hue.dart';
import '../utils/content_mode.dart';
import 'album_art_accent_service.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._();
  static SettingsService get instance => _instance;

  static const String themeClassic = 'classic';
  static const String themeNeon = 'neon';
  static const String themeAlbumArt = 'albumArt';

  /// Accent presets — each hue separated by ≥22° on the color wheel.
  static const Map<String, int> colorPresets = {
    'Ruby Red': 0xFFEF4444,
    'Champagne Gold': 0xFFC9A86A,
    'Lime Shock': 0xFF84CC16,
    'Acid Green': 0xFF22C55E,
    'Arctic Teal': 0xFF14B8A6,
    'Ocean Blue': 0xFF0EA5E9,
    'Electric Indigo': 0xFF6366F1,
    'Nebula Purple': 0xFFA855F7,
    'Magenta': 0xFFC026D3,
    'Neon Pink': 0xFFF472B6,
  };

  static void _validatePresetHues() {
    assert(() {
      AccentHue.assertDistinctPresets(colorPresets);
      return true;
    }());
  }

  SettingsService._();

  late SharedPreferences _prefs;
  bool _initialized = false;

  bool _batterySaver = false;
  bool _lowPerformanceMode = false;
  bool _showSpaceBackground = true;
  bool _highQualityBlur = true;
  bool _frostedGlassBlur = false;
  double _glassBlurSigma = 10.0;
  bool _libraryFrostedBackground = false;
  double _libraryBlurSigma = 14.0;
  double _glassOpacity = 0.22;
  bool _showWaveforms = true;
  bool _screensaverEnabled = false;
  int _screensaverIdleSeconds = 60;
  bool _keepScreenOn = false;
  String _audioFocusMode = 'pause'; // 'pause', 'duck', 'none'

  // Playback audio processing settings
  bool _gaplessPlayback = true;
  int _crossfadeSeconds = 0;
  int _sleepFadeSeconds = 10;
  int _seekSkipSeconds = 10;
  bool _replayGainEnabled = false;
  bool _smartVolumeLimiterEnabled = false;

  // Audio effects (Virtualizer / BassBoost / PresetReverb)
  bool _virtualizerEnabled = false;
  int _virtualizerStrength = 500;
  bool _bassBoostEnabled = false;
  int _bassBoostStrength = 500;
  bool _presetReverbEnabled = false;
  int _presetReverbPreset = 0;

  int _accentColor = 0xFFC9A86A; // Default champagne gold
  String _themeMode = themeClassic;

  // Turntable settings
  int _turntablePerfTier = 2; // 0=off, 1=minimal, 2=full
  bool _turntableSlipmatEnabled = true;
  bool _turntableNeedleDropEnabled = true;
  String _librarySortType =
      'DATE_ADDED'; // 'TITLE', 'ARTIST', 'ALBUM', 'DATE_ADDED'
  int _librarySortOrder = 0; // 0: ASC, 1: DESC
  LibraryBrowseFilter _libraryBrowseFilter = LibraryBrowseFilter.all;

  // Windows scan settings
  List<String> _windowsScanFolders = const <String>[];
  bool _windowsScanRecursive = true;
  List<String> _windowsScanExtensions = const <String>[
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
    'wma',
    'aiff',
    'alac',
  ];

  // Control chips ordering
  List<String> _controlChipOrder = const <String>[
    'speed',
    'bookmark',
    'shuffle',
    'repeat',
    'neural_mix',
    'lyrics',
    'screensaver',
  ];

  // Theme customization colors
  int _glowColor = 0xFF00E5FF; // Default cyan glow
  int _vinylColor = 0xFF1A1A1A; // Default dark vinyl
  int _plinthColor = 0xFF2A2A2A; // Default dark plinth

  // Onboarding
  bool _onboardingComplete = false;
  bool get onboardingComplete => _onboardingComplete;

  // Privacy / telemetry consent (opt-in, off by default)
  bool _telemetryConsent = false;
  bool _telemetryConsentSeen = false;
  bool get telemetryConsent => _telemetryConsent;
  bool get telemetryConsentSeen => _telemetryConsentSeen;

  bool get batterySaver => _batterySaver;
  bool get lowPerformanceMode => _lowPerformanceMode;
  bool get showSpaceBackground => _showSpaceBackground;
  bool get highQualityBlur => _highQualityBlur;
  bool get frostedGlassBlur => _frostedGlassBlur;
  double get glassBlurSigma => _glassBlurSigma;
  bool get libraryFrostedBackground => _libraryFrostedBackground;
  double get libraryBlurSigma => _libraryBlurSigma;
  double get glassOpacity => _glassOpacity;
  bool get showWaveforms => _showWaveforms;
  bool get screensaverEnabled => _screensaverEnabled;
  int get screensaverIdleSeconds => _screensaverIdleSeconds;
  bool get keepScreenOn => _keepScreenOn;
  String get audioFocusMode => _audioFocusMode;
  bool get gaplessPlayback => _gaplessPlayback;
  int get crossfadeSeconds => _crossfadeSeconds;
  int get sleepFadeSeconds => _sleepFadeSeconds;
  int get seekSkipSeconds => _seekSkipSeconds;

  static const List<int> seekSkipOptions = [5, 10, 15, 20, 30, 45, 60];
  bool get replayGainEnabled => _replayGainEnabled;
  bool get smartVolumeLimiterEnabled => _smartVolumeLimiterEnabled;
  bool get virtualizerEnabled => _virtualizerEnabled;
  int get virtualizerStrength => _virtualizerStrength;
  bool get bassBoostEnabled => _bassBoostEnabled;
  int get bassBoostStrength => _bassBoostStrength;
  bool get presetReverbEnabled => _presetReverbEnabled;
  int get presetReverbPreset => _presetReverbPreset;
  int get accentColor => _accentColor;
  String get themeMode => _themeMode;
  bool get isClassicTheme => _themeMode == themeClassic;
  bool get isNeonTheme => _themeMode == themeNeon;
  bool get isAlbumArtTheme => _themeMode == themeAlbumArt;
  int get turntablePerfTier => _turntablePerfTier;
  bool get turntableSlipmatEnabled => _turntableSlipmatEnabled;
  bool get turntableNeedleDropEnabled => _turntableNeedleDropEnabled;
  String get librarySortType => _librarySortType;
  int get librarySortOrder => _librarySortOrder;
  LibraryBrowseFilter get libraryBrowseFilter => _libraryBrowseFilter;
  List<String> get windowsScanFolders => List.unmodifiable(_windowsScanFolders);
  bool get windowsScanRecursive => _windowsScanRecursive;
  List<String> get windowsScanExtensions =>
      List.unmodifiable(_windowsScanExtensions);
  List<String> get controlChipOrder => List.unmodifiable(_controlChipOrder);
  int get glowColor => _glowColor;
  int get vinylColor => _vinylColor;
  int get plinthColor => _plinthColor;

  bool get expensiveEffectsEnabled => !_batterySaver && !_lowPerformanceMode;
  bool get effectiveShowSpaceBackground =>
      _showSpaceBackground && expensiveEffectsEnabled;
  bool get effectiveHighQualityBlur =>
      _highQualityBlur && expensiveEffectsEnabled;
  bool get effectiveFrostedGlassBlur =>
      _frostedGlassBlur && expensiveEffectsEnabled && _glassBlurSigma > 0;
  bool get effectiveLibraryFrostedBackground =>
      _libraryFrostedBackground &&
      expensiveEffectsEnabled &&
      _libraryBlurSigma > 0;
  bool get effectiveShowWaveforms => _showWaveforms && expensiveEffectsEnabled;
  bool get effectiveScreensaverEnabled =>
      _screensaverEnabled && expensiveEffectsEnabled;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _batterySaver = _prefs.getBool('batterySaver') ?? false;
    _showSpaceBackground = _prefs.getBool('showSpaceBackground') ?? true;
    _highQualityBlur = _prefs.getBool('highQualityBlur') ?? true;
    _frostedGlassBlur = _prefs.getBool('frostedGlassBlur') ?? false;
    _glassBlurSigma = _prefs.getDouble('glassBlurSigma') ?? 12.0;
    _libraryFrostedBackground =
        _prefs.getBool('libraryFrostedBackground') ?? false;
    _libraryBlurSigma = _prefs.getDouble('libraryBlurSigma') ?? 20.0;
    _glassOpacity = _prefs.getDouble('glassOpacity') ?? 0.45;
    _showWaveforms = _prefs.getBool('showWaveforms') ?? true;
    _screensaverEnabled = _prefs.getBool('screensaverEnabled') ?? false;
    _screensaverIdleSeconds = (_prefs.getInt('screensaverIdleSeconds') ?? 60)
        .clamp(15, 600);
    _keepScreenOn = _prefs.getBool('keepScreenOn') ?? false;
    if (_keepScreenOn && !_batterySaver) {
      WakelockPlus.enable();
    }
    _audioFocusMode = _prefs.getString('audioFocusMode') ?? 'pause';

    _gaplessPlayback = _prefs.getBool('gaplessPlayback') ?? true;
    _crossfadeSeconds = _prefs.getInt('crossfadeSeconds') ?? 0;
    _sleepFadeSeconds = (_prefs.getInt('sleepFadeSeconds') ?? 10).clamp(0, 30);
    _seekSkipSeconds = _prefs.getInt('seekSkipSeconds') ?? 10;
    if (!seekSkipOptions.contains(_seekSkipSeconds)) {
      _seekSkipSeconds = 10;
    }
    _replayGainEnabled = _prefs.getBool('replayGainEnabled') ?? false;
    _smartVolumeLimiterEnabled =
        _prefs.getBool('smartVolumeLimiterEnabled') ?? false;
    _virtualizerEnabled = _prefs.getBool('virtualizerEnabled') ?? false;
    _virtualizerStrength = (_prefs.getInt('virtualizerStrength') ?? 500).clamp(
      0,
      1000,
    );
    _bassBoostEnabled = _prefs.getBool('bassBoostEnabled') ?? false;
    _bassBoostStrength = (_prefs.getInt('bassBoostStrength') ?? 500).clamp(
      0,
      1000,
    );
    _presetReverbEnabled = _prefs.getBool('presetReverbEnabled') ?? false;
    _presetReverbPreset = (_prefs.getInt('presetReverbPreset') ?? 0).clamp(
      0,
      6,
    );
    _accentColor = _prefs.getInt('accentColor') ?? 0xFFC9A86A;
    _themeMode = _prefs.getString('themeMode') ?? themeClassic;
    _validatePresetHues();
    AlbumArtAccentService.instance.addListener(notifyListeners);

    _turntablePerfTier = (_prefs.getInt('turntablePerfTier') ?? 2).clamp(0, 2);
    _turntableSlipmatEnabled =
        _prefs.getBool('turntableSlipmatEnabled') ?? true;
    _turntableNeedleDropEnabled =
        _prefs.getBool('turntableNeedleDropEnabled') ?? true;
    _librarySortType = _prefs.getString('librarySortType') ?? 'DATE_ADDED';
    _librarySortOrder =
        _prefs.getInt('librarySortOrder') ?? 1; // Default DESC for Date Added
    _libraryBrowseFilter = LibraryBrowseFilter.fromName(
      _prefs.getString('libraryBrowseFilter'),
    );

    _windowsScanFolders =
        _prefs.getStringList('windowsScanFolders') ?? const <String>[];
    _windowsScanRecursive = _prefs.getBool('windowsScanRecursive') ?? true;
    _windowsScanExtensions =
        _prefs.getStringList('windowsScanExtensions') ?? _windowsScanExtensions;

    _controlChipOrder =
        _prefs.getStringList('controlChipOrder') ??
        const <String>[
          'shuffle',
          'repeat',
          'neural_mix',
          'speed',
          'screensaver',
          'bookmark',
          'lyrics',
        ];
    _glowColor = _prefs.getInt('glowColor') ?? 0xFFFF9F40;
    _vinylColor = _prefs.getInt('vinylColor') ?? 0xFF1A1A1A;
    _plinthColor = _prefs.getInt('plinthColor') ?? 0xFF2A2A2A;
    _onboardingComplete = _prefs.getBool('onboardingComplete') ?? false;
    _telemetryConsent = _prefs.getBool('telemetryConsent') ?? false;
    _telemetryConsentSeen = _prefs.getBool('telemetryConsentSeen') ?? false;

    // Check for low performance mode preference, or auto-detect if not set
    if (_prefs.containsKey('lowPerformanceMode')) {
      _lowPerformanceMode = _prefs.getBool('lowPerformanceMode')!;
    } else {
      await _detectDeviceCapabilities();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setGaplessPlayback(bool value) async {
    _gaplessPlayback = value;
    await _prefs.setBool('gaplessPlayback', value);
    notifyListeners();
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    final v = seconds.clamp(0, 12);
    _crossfadeSeconds = v;
    await _prefs.setInt('crossfadeSeconds', v);
    notifyListeners();
  }

  Future<void> setSleepFadeSeconds(int seconds) async {
    final v = seconds.clamp(0, 30);
    _sleepFadeSeconds = v;
    await _prefs.setInt('sleepFadeSeconds', v);
    notifyListeners();
  }

  Future<void> setSeekSkipSeconds(int seconds) async {
    if (!seekSkipOptions.contains(seconds)) return;
    _seekSkipSeconds = seconds;
    await _prefs.setInt('seekSkipSeconds', seconds);
    notifyListeners();
  }

  Future<void> setReplayGainEnabled(bool value) async {
    _replayGainEnabled = value;
    await _prefs.setBool('replayGainEnabled', value);
    notifyListeners();
  }

  Future<void> setSmartVolumeLimiterEnabled(bool value) async {
    _smartVolumeLimiterEnabled = value;
    await _prefs.setBool('smartVolumeLimiterEnabled', value);
    notifyListeners();
  }

  Future<void> setVirtualizerEnabled(bool value) async {
    _virtualizerEnabled = value;
    await _prefs.setBool('virtualizerEnabled', value);
    notifyListeners();
  }

  Future<void> setVirtualizerStrength(int value) async {
    final v = value.clamp(0, 1000);
    _virtualizerStrength = v;
    await _prefs.setInt('virtualizerStrength', v);
    notifyListeners();
  }

  Future<void> setBassBoostEnabled(bool value) async {
    _bassBoostEnabled = value;
    await _prefs.setBool('bassBoostEnabled', value);
    notifyListeners();
  }

  Future<void> setBassBoostStrength(int value) async {
    final v = value.clamp(0, 1000);
    _bassBoostStrength = v;
    await _prefs.setInt('bassBoostStrength', v);
    notifyListeners();
  }

  Future<void> setPresetReverbEnabled(bool value) async {
    _presetReverbEnabled = value;
    await _prefs.setBool('presetReverbEnabled', value);
    notifyListeners();
  }

  Future<void> setPresetReverbPreset(int value) async {
    final v = value.clamp(0, 6);
    _presetReverbPreset = v;
    await _prefs.setInt('presetReverbPreset', v);
    notifyListeners();
  }

  Future<void> _detectDeviceCapabilities() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        // Heuristic: Android SDK < 29 (Android 10) often implies older hardware
        final isOldAndroid = androidInfo.version.sdkInt < 29;

        if (isOldAndroid) {
          if (kDebugMode) {
            debugPrint(
              'Low performance device detected (SDK: ${androidInfo.version.sdkInt})',
            );
          }
          await setLowPerformanceMode(true);
        }
      }
    } catch (e) {
      debugPrint('Error detecting device capabilities: $e');
    }
  }

  Future<void> setLowPerformanceMode(bool value) async {
    _lowPerformanceMode = value;
    await _prefs.setBool('lowPerformanceMode', value);
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
    await _prefs.setBool('keepScreenOn', value);
    notifyListeners();
  }

  Future<void> setAudioFocusMode(String value) async {
    _audioFocusMode = value;
    await _prefs.setString('audioFocusMode', value);
    notifyListeners();
  }

  Future<void> setAccentColor(int value) async {
    final picked = Color(value);
    final others = colorPresets.values
        .where((v) => v != value)
        .map((v) => Color(v));
    final distinct = AccentHue.ensureDistinct(picked, avoid: others);
    _accentColor = distinct.toARGB32();
    await _prefs.setInt('accentColor', _accentColor);
    notifyListeners();
  }

  Future<void> setThemeMode(String value) async {
    final normalized =
        (value == themeNeon || value == themeAlbumArt) ? value : themeClassic;
    _themeMode = normalized;
    await _prefs.setString('themeMode', normalized);
    notifyListeners();
  }

  Future<void> setTurntablePerfTier(int value) async {
    final v = value.clamp(0, 2);
    _turntablePerfTier = v;
    await _prefs.setInt('turntablePerfTier', v);
    notifyListeners();
  }

  Future<void> setTurntableSlipmatEnabled(bool value) async {
    _turntableSlipmatEnabled = value;
    await _prefs.setBool('turntableSlipmatEnabled', value);
    notifyListeners();
  }

  Future<void> setTurntableNeedleDropEnabled(bool value) async {
    _turntableNeedleDropEnabled = value;
    await _prefs.setBool('turntableNeedleDropEnabled', value);
    notifyListeners();
  }

  Future<void> setBatterySaver(bool value) async {
    _batterySaver = value;
    await _prefs.setBool('batterySaver', value);
    if (value) {
      WakelockPlus.disable();
    }
    notifyListeners();
  }

  Future<void> setShowWaveforms(bool value) async {
    _showWaveforms = value;
    await _prefs.setBool('showWaveforms', value);
    notifyListeners();
  }

  Future<void> setScreensaverEnabled(bool value) async {
    _screensaverEnabled = value;
    await _prefs.setBool('screensaverEnabled', value);
    notifyListeners();
  }

  Future<void> setScreensaverIdleSeconds(int seconds) async {
    final v = seconds.clamp(15, 600);
    _screensaverIdleSeconds = v;
    await _prefs.setInt('screensaverIdleSeconds', v);
    notifyListeners();
  }

  Future<void> setShowSpaceBackground(bool value) async {
    _showSpaceBackground = value;
    await _prefs.setBool('showSpaceBackground', value);
    notifyListeners();
  }

  Future<void> setHighQualityBlur(bool value) async {
    _highQualityBlur = value;
    await _prefs.setBool('highQualityBlur', value);
    notifyListeners();
  }

  Future<void> setFrostedGlassBlur(bool value) async {
    _frostedGlassBlur = value;
    await _prefs.setBool('frostedGlassBlur', value);
    notifyListeners();
  }

  Future<void> setGlassBlurSigma(double value) async {
    _glassBlurSigma = value;
    await _prefs.setDouble('glassBlurSigma', value);
    notifyListeners();
  }

  Future<void> setLibraryFrostedBackground(bool value) async {
    _libraryFrostedBackground = value;
    await _prefs.setBool('libraryFrostedBackground', value);
    notifyListeners();
  }

  Future<void> setLibraryBlurSigma(double value) async {
    _libraryBlurSigma = value;
    await _prefs.setDouble('libraryBlurSigma', value);
    notifyListeners();
  }

  Future<void> setGlassOpacity(double value) async {
    _glassOpacity = value;
    await _prefs.setDouble('glassOpacity', value);
    notifyListeners();
  }

  Future<void> setLibrarySort(String type, int order) async {
    _librarySortType = type;
    _librarySortOrder = order;
    await _prefs.setString('librarySortType', type);
    await _prefs.setInt('librarySortOrder', order);
    notifyListeners();
  }

  Future<void> setOnboardingComplete(bool value) async {
    _onboardingComplete = value;
    await _prefs.setBool('onboardingComplete', value);
    notifyListeners();
  }

  Future<void> setTelemetryConsent(bool value) async {
    _telemetryConsent = value;
    await _prefs.setBool('telemetryConsent', value);
    notifyListeners();
  }

  Future<void> setTelemetryConsentSeen(bool value) async {
    _telemetryConsentSeen = value;
    await _prefs.setBool('telemetryConsentSeen', value);
    notifyListeners();
  }

  Future<void> setLibraryBrowseFilter(LibraryBrowseFilter filter) async {
    _libraryBrowseFilter = filter;
    await _prefs.setString('libraryBrowseFilter', filter.name);
    notifyListeners();
  }

  Future<void> setWindowsScanFolders(List<String> folders) async {
    _windowsScanFolders = folders
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    await _prefs.setStringList('windowsScanFolders', _windowsScanFolders);
    notifyListeners();
  }

  Future<void> setWindowsScanRecursive(bool value) async {
    _windowsScanRecursive = value;
    await _prefs.setBool('windowsScanRecursive', value);
    notifyListeners();
  }

  Future<void> setWindowsScanExtensions(List<String> exts) async {
    _windowsScanExtensions = exts
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    await _prefs.setStringList('windowsScanExtensions', _windowsScanExtensions);
    notifyListeners();
  }

  Future<void> setControlChipOrder(List<String> order) async {
    _controlChipOrder = List.unmodifiable(order);
    await _prefs.setStringList('controlChipOrder', order);
    notifyListeners();
  }

  Future<void> setGlowColor(int color) async {
    _glowColor = color;
    await _prefs.setInt('glowColor', color);
    notifyListeners();
  }

  Future<void> setVinylColor(int color) async {
    _vinylColor = color;
    await _prefs.setInt('vinylColor', color);
    notifyListeners();
  }

  Future<void> setPlinthColor(int color) async {
    _plinthColor = color;
    await _prefs.setInt('plinthColor', color);
    notifyListeners();
  }

  /// Raw picker accent — prefer [resolveAccentColor] for display.
  Color get rawAccent => Color(_accentColor);

  void notifyAccentCacheChanged() => notifyListeners();

  /// Theme-aware accent for general UI (sliders, library via [MaterialApp] theme).
  Color resolveAccentColor(Color baseAccent, {MediaItem? item}) {
    switch (_themeMode) {
      case themeNeon:
        final hsv = HSVColor.fromColor(baseAccent);
        return hsv.withSaturation(1.0).withValue(1.0).toColor();

      case themeAlbumArt:
        if (item != null) {
          final cached = AlbumArtAccentService.instance.cachedColorFor(item.id);
          if (cached != null) return cached;
          AlbumArtAccentService.instance.prefetch(item);
          return AccentHue.fallbackForItem(
            item.id,
            baseAccent,
            avoid: colorPresets.values.map((v) => Color(v)),
          );
        }
        return baseAccent;

      default:
        return baseAccent;
    }
  }

  /// Single accent path for Now Playing visuals (waveform + turntable + glow).
  Color resolveNowPlayingAccent({MediaItem? item}) {
    return resolveAccentColor(rawAccent, item: item);
  }

  /// Convenience: resolved accent from the stored picker value.
  Color accentFor({MediaItem? item, bool nowPlaying = false}) {
    if (nowPlaying) return resolveNowPlayingAccent(item: item);
    return resolveAccentColor(rawAccent, item: item);
  }

  /// Resets all settings to sensible defaults.
  /// Useful for debugging or giving users a fresh start.
  Future<void> resetToDefaults() async {
    // Performance & Visuals
    await setLowPerformanceMode(false);
    await setBatterySaver(false);
    await setHighQualityBlur(true);
    await setFrostedGlassBlur(false);
    await setGlassBlurSigma(12.0);
    await setLibraryFrostedBackground(false);
    await setLibraryBlurSigma(20.0);
    await setGlassOpacity(0.45);
    await setShowSpaceBackground(true);
    await setShowWaveforms(true);
    await setScreensaverEnabled(false);
    await setScreensaverIdleSeconds(60);
    await setKeepScreenOn(false);

    // Playback
    await setGaplessPlayback(true);
    await setCrossfadeSeconds(0);
    await setSleepFadeSeconds(10);
    await setSeekSkipSeconds(10);
    await setReplayGainEnabled(false);
    await setSmartVolumeLimiterEnabled(false);
    await setAudioFocusMode('pause');

    // Audio effects
    await setVirtualizerEnabled(false);
    await setVirtualizerStrength(500);
    await setBassBoostEnabled(false);
    await setBassBoostStrength(500);
    await setPresetReverbEnabled(false);
    await setPresetReverbPreset(0);

    // Appearance
    await setAccentColor(0xFFC9A86A);
    await setThemeMode(themeClassic);
    await setGlowColor(0xFFC9A86A);
    await setVinylColor(0xFF1A1A1A);
    await setPlinthColor(0xFF2A2A2A);

    // Turntable
    await setTurntablePerfTier(2);
    await setTurntableSlipmatEnabled(true);
    await setTurntableNeedleDropEnabled(true);

    // Library
    await setLibrarySort('DATE_ADDED', 1);

    // Reset Windows scan defaults
    await setWindowsScanRecursive(true);
    await setWindowsScanExtensions([
      'mp3',
      'm4a',
      'aac',
      'wav',
      'flac',
      'ogg',
      'opus',
      'wma',
      'aiff',
      'alac',
    ]);
    await setWindowsScanFolders([]);

    // Control chips
    await setControlChipOrder([
      'shuffle',
      'repeat',
      'neural_mix',
      'speed',
      'screensaver',
      'bookmark',
      'lyrics',
    ]);

    // Privacy / telemetry (opt-out on reset)
    await setTelemetryConsent(false);
    await setTelemetryConsentSeen(false);

    notifyListeners();
  }
}
