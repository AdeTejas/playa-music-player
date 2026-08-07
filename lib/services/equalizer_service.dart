import 'dart:io';
import 'package:flutter/services.dart';

import 'settings_service.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel(
    'com.paxpiece.playa/equalizer',
  );

  static Future<void> initializeEqualizer(int audioSessionId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('initializeEqualizer', {
        'audioSessionId': audioSessionId,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<int> getEqualizerBands() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getEqualizerBands');
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<List<int>> getBandLevelRange() async {
    if (!Platform.isAndroid) return [-1500, 1500];
    try {
      final result = await _channel.invokeMethod('getBandLevelRange');
      return List<int>.from(result);
    } on MissingPluginException {
      return [-1500, 1500];
    } on PlatformException {
      return [-1500, 1500];
    }
  }

  static Future<int> getBandLevel(int band) async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getBandLevel', {'band': band});
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<List<int>> getAllBandLevels() async {
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod('getAllBandLevels');
      return List<int>.from(result);
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<List<int>> getBandCenterFrequencies() async {
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod('getBandCenterFrequencies');
      return List<int>.from(result);
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<void> setBandLevel(int band, int level) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBandLevel', {'band': band, 'level': level});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<List<String>> getPresetNames() async {
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod('getPresetNames');
      return List<String>.from(result);
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<void> usePreset(int preset) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('usePreset', {'preset': preset});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<int> getCurrentPreset() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getCurrentPreset');
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isEnabled');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  // ── Audio Effects: Virtualizer (headphone spatialization) ────────────────

  static Future<bool> getVirtualizerSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('getVirtualizerSupported');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<int> getVirtualizerStrength() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getVirtualizerStrength');
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<void> setVirtualizerStrength(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVirtualizerStrength', {
        'strength': strength,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isVirtualizerEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isVirtualizerEnabled');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setVirtualizerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVirtualizerEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  // ── Audio Effects: BassBoost ─────────────────────────────────────────────

  static Future<bool> getBassBoostSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('getBassBoostSupported');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<int> getBassBoostStrength() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getBassBoostStrength');
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<void> setBassBoostStrength(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBassBoostStrength', {
        'strength': strength,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isBassBoostEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isBassBoostEnabled');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setBassBoostEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBassBoostEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  // ── Audio Effects: PresetReverb (room simulation) ────────────────────────

  /// Re-applies persisted audio-effect settings after a fresh native session
  /// (a new track, session change, or app restart resets the effects).
  static Future<void> restoreEffectsFromSettings() async {
    if (!Platform.isAndroid) return;
    final s = SettingsService.instance;
    try {
      await setVirtualizerStrength(s.virtualizerStrength);
      await setVirtualizerEnabled(s.virtualizerEnabled);
      await setBassBoostStrength(s.bassBoostStrength);
      await setBassBoostEnabled(s.bassBoostEnabled);
      await usePresetReverb(s.presetReverbPreset);
      await setPresetReverbEnabled(s.presetReverbEnabled);
    } on PlatformException {
      return;
    }
  }

  static Future<List<String>> getPresetReverbPresets() async {
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod('getPresetReverbPresets');
      return List<String>.from(result);
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<int> getCurrentPresetReverb() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod('getCurrentPresetReverb');
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<void> usePresetReverb(int preset) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('usePresetReverb', {'preset': preset});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isPresetReverbEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isPresetReverbEnabled');
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setPresetReverbEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setPresetReverbEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('release');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
