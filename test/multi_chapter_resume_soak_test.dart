import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/models/listening_progress.dart';
import 'package:playa_clean/utils/content_mode.dart';
import 'package:playa_clean/utils/resume_soak_check.dart';

void main() {
  test('synthetic resume soak checks all pass', () {
    final report = ResumeSoakCheck.runSyntheticChecks();
    expect(report.ok, isTrue, reason: report.summary);
    expect(report.failed, 0);
    expect(report.passed, greaterThanOrEqualTo(5));
  });

  test('live checks flag unresolvable progress', () {
    final recent = [
      ListeningProgress(
        seriesKey: 'missing::book',
        title: 'Missing Book',
        artist: 'Nobody',
        lastSongPath: '/does/not/exist.mp3',
        positionMs: 60000,
        updatedAt: DateTime.now(),
        contentMode: ContentMode.audiobook,
      ),
    ];

    final report = ResumeSoakCheck.runLiveChecks(
      library: const [],
      recent: recent,
    );

    expect(report.failed, greaterThan(0));
    expect(report.summary, contains('FAIL'));
  });
}