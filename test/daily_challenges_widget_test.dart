import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens daily challenges and tracks a real started run', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _DailyTestAudio(),
          testDriver: driver,
          dailyChallengesNow: () => DateTime(1970, 1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Daily challenges'));
    await tester.pumpAndSettle();
    expect(find.text('DAILY CHALLENGES'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-challenge-collect_gems')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('daily-challenge-start_runs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('daily-challenge-absorb_hazards')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('daily-claim-start_runs')),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('MAIN MENU'));
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runState, RunState.playing);
    expect(driver.runsStarted, 1);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('RESUME'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runsStarted, 1);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Daily challenges'));
    await tester.pumpAndSettle();
    await driver.flushProgress();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daily-progress-start_runs')))
          .data,
      startsWith('1 / 2'),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('daily-progress-bar-start_runs')),
          )
          .value,
      0.5,
    );
    expect(
      find.byKey(const ValueKey('daily-status-start_runs')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daily-status-start_runs')))
          .data,
      'IN PROGRESS',
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('daily-claim-start_runs')),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('MAIN MENU'));
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await driver.flushProgress();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Daily challenges'));
    await tester.pumpAndSettle();
    await driver.flushProgress();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daily-progress-start_runs')))
          .data,
      startsWith('2 / 2'),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('daily-progress-bar-start_runs')),
          )
          .value,
      1.0,
    );
    expect(find.text('COMPLETE'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('daily-claim-start_runs')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('daily-claim-start_runs')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daily-status-start_runs')))
          .data,
      'CLAIMED',
    );
    expect(find.text('Bonus gems granted: 5'), findsOneWidget);
    expect(find.text('GEMS  5'), findsOneWidget);
    expect(driver.totalGems, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _DailyTestAudio extends GameAudioController {
  @override
  bool get musicEnabled => true;

  @override
  bool get effectsEnabled => true;

  @override
  Future<void> initialize() async {}

  @override
  void setGameState(AudioRunState state) {}

  @override
  void setAppActive(bool active) {}

  @override
  Future<void> setMusicEnabled(bool enabled) async {}

  @override
  Future<void> setEffectsEnabled(bool enabled) async {}

  @override
  void playEffect(GameSoundEffect effect) {}

  @override
  Future<void> shutdown() async {}
}
