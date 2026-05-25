import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Error/crash report structure
class ErrorReport {
  final String title;
  final String message;
  final String stackTrace;
  final Map<String, dynamic> context;
  final DateTime timestamp;

  ErrorReport({
    required this.title,
    required this.message,
    required this.stackTrace,
    this.context = const {},
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
    'title': title,
    'message': message,
    'stackTrace': stackTrace,
    'context': context,
    'timestamp': timestamp.toIso8601String(),
  };
}

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  late SharedPreferences _prefs;
  bool _initialized = false;
  final List<ErrorReport> _errors = [];

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;

    // Load persisted errors
    final persistedErrors = _prefs.getStringList('error_reports') ?? [];
    if (kDebugMode) debugPrint('[ANALYTICS] Loaded ${persistedErrors.length} persisted error reports');
  }

  static void logEvent(String name, Map<String, Object?> params) {
    developer.log('analytics_event:$name $params', name: 'analytics.service');
    if (kDebugMode) debugPrint('[ANALYTICS] Event: $name | $params');
  }

  /// Log an error/crash
  Future<void> logError({
    required String title,
    required String message,
    required String stackTrace,
    Map<String, dynamic> context = const {},
  }) async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }

    final error = ErrorReport(
      title: title,
      message: message,
      stackTrace: stackTrace,
      context: context,
    );

    _errors.add(error);
    developer.log('error:$title $message', name: 'analytics.service');
    if (kDebugMode) {
      debugPrint('[ERROR_REPORT] ❌ $title: $message');
      debugPrint('[ERROR_REPORT] Stack: $stackTrace');
    }

    // Persist to SharedPreferences
    await _persistErrors();
  }

  /// Convenience method to log exceptions
  Future<void> logException(
    Object exception,
    StackTrace stackTrace, {
    Map<String, dynamic> context = const {},
  }) async {
    await logError(
      title: exception.runtimeType.toString(),
      message: exception.toString(),
      stackTrace: stackTrace.toString(),
      context: context,
    );
  }

  Future<void> _persistErrors() async {
    if (!_initialized) return;
    final errorJsonList = _errors.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList('error_reports', errorJsonList);
  }

  /// Get all error reports
  List<ErrorReport> getErrors() => List.unmodifiable(_errors);

  /// Clear error reports
  Future<void> clearErrors() async {
    _errors.clear();
    if (_initialized) {
      await _prefs.remove('error_reports');
    }
    if (kDebugMode) debugPrint('[ANALYTICS] Error reports cleared');
  }

  /// Print diagnostics
  void printDiagnostics() {
    if (!kDebugMode) return;
    debugPrint('=== ANALYTICS DIAGNOSTICS ===');
    debugPrint('Errors logged: ${_errors.length}');
    if (_errors.isNotEmpty) {
      debugPrint('Recent errors:');
      _errors.take(5).forEach((e) => debugPrint('  - ${e.title}: ${e.message}'));
    }
    debugPrint('==============================');
  }
}

