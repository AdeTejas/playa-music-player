import 'dart:io';
import 'package:flutter/services.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel(
    'com.paxpiece.playa/equalizer',
  );

  static Future<void> initializeEqualizer(int audioSessionId) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('initializeEqualizer', {
      'audioSessionId': audioSessionId,
    });
  }

  static Future<int> getEqualizerBands() async {
    if (!Platform.isAndroid) return 0;
    return await _channel.invokeMethod('getEqualizerBands');
  }

  static Future<List<int>> getBandLevelRange() async {
    if (!Platform.isAndroid) return [-1500, 1500];
    final result = await _channel.invokeMethod('getBandLevelRange');
    return List<int>.from(result);
  }

  static Future<int> getBandLevel(int band) async {
    if (!Platform.isAndroid) return 0;
    return await _channel.invokeMethod('getBandLevel', {'band': band});
  }

  static Future<List<int>> getAllBandLevels() async {
    if (!Platform.isAndroid) return [];
    final result = await _channel.invokeMethod('getAllBandLevels');
    return List<int>.from(result);
  }

  static Future<List<int>> getBandCenterFrequencies() async {
    if (!Platform.isAndroid) return [];
    final result = await _channel.invokeMethod('getBandCenterFrequencies');
    return List<int>.from(result);
  }

  static Future<void> setBandLevel(int band, int level) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setBandLevel', {'band': band, 'level': level});
  }

  static Future<List<String>> getPresetNames() async {
    if (!Platform.isAndroid) return [];
    final result = await _channel.invokeMethod('getPresetNames');
    return List<String>.from(result);
  }

  static Future<void> usePreset(int preset) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('usePreset', {'preset': preset});
  }

  static Future<int> getCurrentPreset() async {
    if (!Platform.isAndroid) return 0;
    return await _channel.invokeMethod('getCurrentPreset');
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setEnabled', {'enabled': enabled});
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod('isEnabled');
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
