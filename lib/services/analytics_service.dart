import 'dart:developer' as developer;

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  static void logEvent(String name, Map<String, Object?> params) {
    developer.log('analytics_event:$name $params', name: 'analytics.service');
  }
}
