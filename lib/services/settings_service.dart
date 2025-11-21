import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._();
  static SettingsService get instance => _instance;

  SettingsService._();

  late SharedPreferences _prefs;
  bool _initialized = false;

  bool _batterySaver = false;
  bool _showSpaceBackground = true;
  bool _highQualityBlur = true;
  bool _showWaveforms = true;
  bool _keepScreenOn = false;
  String _audioFocusMode = 'pause'; // 'pause', 'duck', 'none'
  int _accentColor = 0xFF8D5524; // Default Wood/Walnut
  String _librarySortType = 'DATE_ADDED'; // 'TITLE', 'ARTIST', 'ALBUM', 'DATE_ADDED'
  int _librarySortOrder = 0; // 0: ASC, 1: DESC

  bool get batterySaver => _batterySaver;
  bool get showSpaceBackground => _showSpaceBackground;
  bool get highQualityBlur => _highQualityBlur;
  bool get showWaveforms => _showWaveforms;
  bool get keepScreenOn => _keepScreenOn;
  String get audioFocusMode => _audioFocusMode;
  int get accentColor => _accentColor;
  String get librarySortType => _librarySortType;
  int get librarySortOrder => _librarySortOrder;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _batterySaver = _prefs.getBool('batterySaver') ?? false;
    _showSpaceBackground = _prefs.getBool('showSpaceBackground') ?? true;
    _highQualityBlur = _prefs.getBool('highQualityBlur') ?? true;
    _showWaveforms = _prefs.getBool('showWaveforms') ?? true;
    _keepScreenOn = _prefs.getBool('keepScreenOn') ?? false;
    if (_keepScreenOn) {
      WakelockPlus.enable();
    }
    _audioFocusMode = _prefs.getString('audioFocusMode') ?? 'pause';
    _accentColor = _prefs.getInt('accentColor') ?? 0xFF8D5524;
    _librarySortType = _prefs.getString('librarySortType') ?? 'DATE_ADDED';
    _librarySortOrder = _prefs.getInt('librarySortOrder') ?? 1; // Default DESC for Date Added
    _initialized = true;
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
    _accentColor = value;
    await _prefs.setInt('accentColor', value);
    notifyListeners();
  }

  Future<void> setBatterySaver(bool value) async {
    _batterySaver = value;
    await _prefs.setBool('batterySaver', value);
    // Auto-disable high quality stuff if battery saver is on
    if (value) {
      _showSpaceBackground = false;
      _highQualityBlur = false;
      _keepScreenOn = false; // Disable wakelock for battery saving
      await _prefs.setBool('showSpaceBackground', false);
      await _prefs.setBool('highQualityBlur', false);
      await _prefs.setBool('keepScreenOn', false);
      WakelockPlus.disable(); // Immediately disable if active
    } else {
      // Restore defaults or keep as is? Let's restore defaults for convenience
      _showSpaceBackground = true;
      _highQualityBlur = true;
      await _prefs.setBool('showSpaceBackground', true);
      await _prefs.setBool('highQualityBlur', true);
    }
    notifyListeners();
  }

  Future<void> setShowWaveforms(bool value) async {
    _showWaveforms = value;
    await _prefs.setBool('showWaveforms', value);
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

  Future<void> setLibrarySort(String type, int order) async {
    _librarySortType = type;
    _librarySortOrder = order;
    await _prefs.setString('librarySortType', type);
    await _prefs.setInt('librarySortOrder', order);
    notifyListeners();
  }
}
