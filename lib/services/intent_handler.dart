import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class IntentHandler {
  static const MethodChannel _channel = MethodChannel(
    'com.playa.intent_handler',
  );

  static StreamController<String?>? _intentStreamController;

  static Future<void> setupIntentHandling() async {
    if (!Platform.isAndroid) return;

    _intentStreamController = StreamController<String?>.broadcast();

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        final String? data = call.arguments as String?;
        _intentStreamController?.add(data);
      }
    });
  }

  static Future<String?> getInitialIntent() async {
    if (!Platform.isAndroid) return null;

    try {
      final String? result = await _channel.invokeMethod('getInitialIntent');
      return result;
    } catch (e) {
      return null;
    }
  }

  static Stream<String?> get receivedIntentStream {
    return _intentStreamController?.stream ?? const Stream.empty();
  }

  static void dispose() {
    _intentStreamController?.close();
  }
}
