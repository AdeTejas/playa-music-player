import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidSonicDnaResult {
  final double? bpm;
  final String? key;
  final double confidence;

  const AndroidSonicDnaResult({
    required this.bpm,
    required this.key,
    required this.confidence,
  });
}

class SonicDnaAndroidAnalyzer {
  static const MethodChannel _channel = MethodChannel(
    'com.paxpiece.playa/sonic_dna',
  );

  static Future<AndroidSonicDnaResult> analyze(
    String uriOrPath, {
    int maxSeconds = 90,
    int targetSampleRate = 11025,
  }) async {
    if (!defaultTargetPlatform.toString().contains('android')) {
      return const AndroidSonicDnaResult(bpm: null, key: null, confidence: 0);
    }

    try {
      final res = await _channel
          .invokeMapMethod<String, dynamic>('analyzeTrack', {
            'uri': uriOrPath,
            'maxSeconds': maxSeconds,
            'targetSampleRate': targetSampleRate,
          });

      if (res == null) {
        return const AndroidSonicDnaResult(bpm: null, key: null, confidence: 0);
      }

      final bpm = (res['bpm'] as num?)?.toDouble();
      final key = res['key'] as String?;
      final confidence = (res['confidence'] as num?)?.toDouble() ?? 0.0;
      return AndroidSonicDnaResult(bpm: bpm, key: key, confidence: confidence);
    } catch (e) {
      return const AndroidSonicDnaResult(bpm: null, key: null, confidence: 0);
    }
  }
}
