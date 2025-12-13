import 'package:flutter/foundation.dart';

class PerfMetricsService extends ChangeNotifier {
  static final PerfMetricsService instance = PerfMetricsService._();
  PerfMetricsService._();

  DateTime? _appStartAt;
  Duration? _coldStartToFirstFrame;

  DateTime? get appStartAt => _appStartAt;
  Duration? get coldStartToFirstFrame => _coldStartToFirstFrame;

  void markAppStart() {
    _appStartAt ??= DateTime.now();
  }

  void markFirstFrame() {
    final start = _appStartAt;
    if (start == null) return;
    if (_coldStartToFirstFrame != null) return;

    _coldStartToFirstFrame = DateTime.now().difference(start);
    notifyListeners();
  }
}
