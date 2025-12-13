import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../widgets/static_turntable.dart';

class WidgetService {
  static const String _androidWidgetName = 'TurntableWidgetProvider';

  static Future<void> updateWidget({
    MediaItem? mediaItem,
    bool isPlaying = false,
  }) async {
    if (mediaItem == null) return;

    await HomeWidget.saveWidgetData<String>('widget_title', mediaItem.title);
    await HomeWidget.saveWidgetData<String>(
      'widget_artist',
      mediaItem.artist ?? 'Unknown',
    );

    // Render Turntable Image
    await HomeWidget.renderFlutterWidget(
      StaticTurntable(isPlaying: isPlaying),
      key: 'widget_turntable_image',
      logicalSize: const Size(200, 200),
    );

    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      androidName: _androidWidgetName,
    );
  }
}
