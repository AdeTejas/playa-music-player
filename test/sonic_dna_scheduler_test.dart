import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/services/sonic_dna_scheduler.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await SettingsService.instance.setOnboardingComplete(false);
  });

  tearDown(() {
    SonicDnaScheduler.instance.resetForTest();
    SonicDnaScheduler.instance.debugBatteryState = null;
    SonicDnaScheduler.instance.songsOverride = null;
    SonicDnaScheduler.instance.runAnalysisOverride = null;
  });

  oaq.SongModel song(int id) => oaq.SongModel({'_id': id, '_data': 'c:/x$id.mp3'});

  test('does not auto-run when not charging', () async {
    final sched = SonicDnaScheduler.instance;
    sched.debugBatteryState = BatteryState.discharging;
    sched.songsOverride = () => [song(1)];

    var calls = 0;
    sched.runAnalysisOverride = (_) async => calls++;
    await SettingsService.instance.setOnboardingComplete(true);

    await sched.start();

    expect(calls, 0);
    expect(sched.autoRunInProgress, isFalse);
  });

  test('runs analysis when charging and idle', () async {
    final sched = SonicDnaScheduler.instance;
    sched.debugBatteryState = BatteryState.charging;
    sched.songsOverride = () => [song(1), song(2)];

    var calls = 0;
    List<oaq.SongModel>? received;
    sched.runAnalysisOverride = (songs) async {
      calls++;
      received = songs;
    };
    await SettingsService.instance.setOnboardingComplete(true);

    await sched.start();

    expect(calls, 1);
    expect(received!.length, 2);
  });

  test('does not run while onboarding is incomplete', () async {
    final sched = SonicDnaScheduler.instance;
    sched.debugBatteryState = BatteryState.full;
    sched.songsOverride = () => [song(1)];

    var calls = 0;
    sched.runAnalysisOverride = (_) async => calls++;

    await sched.start();

    expect(calls, 0);
  });

  test('does not run when the library is empty', () async {
    final sched = SonicDnaScheduler.instance;
    sched.debugBatteryState = BatteryState.charging;
    sched.songsOverride = () => [];

    var calls = 0;
    sched.runAnalysisOverride = (_) async => calls++;
    await SettingsService.instance.setOnboardingComplete(true);

    await sched.start();

    expect(calls, 0);
  });

  test('unplugging cancels an in-progress auto-run', () async {
    final sched = SonicDnaScheduler.instance;
    sched.debugBatteryState = BatteryState.charging;
    sched.songsOverride = () => [song(1)];
    await SettingsService.instance.setOnboardingComplete(true);

    final completer = Completer<void>();
    sched.runAnalysisOverride = (_) => completer.future;

    unawaited(sched.start());
    await Future<void>.delayed(Duration.zero);
    expect(sched.autoRunInProgress, isTrue);

    sched.handleBatteryState(BatteryState.discharging);
    expect(sched.autoRunInProgress, isFalse);

    completer.complete();
    await Future<void>.delayed(Duration.zero);
  });
}
