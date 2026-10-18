import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('achievement notice text is explicitly white', (tester) async {
    SharedPreferences.setMockInitialValues({
      AchievementStore.totalGemsKey: 9,
      'orbit_dash_best': 12,
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _UiTestAudio(),
          testDriver: driver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    driver.placeGemAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushAchievements();
    await tester.pump(const Duration(milliseconds: 300));

    final notice = tester.widget<Text>(find.text('First Steps unlocked!'));
    expect(notice.style?.color, Colors.white);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main menu shows spendable wallet balance, not lifetime gems', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      AchievementStore.totalGemsKey: 900,
      GemWallet.stateKey: '{"version":2,"balance":23,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
    });

    await tester.pumpWidget(
      MaterialApp(home: OrbitGamePage(audioController: _UiTestAudio())),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('main-menu-gem-balance')))
          .data,
      '23 G',
    );
    expect(find.text('ORBIT DASH'), findsOneWidget);
    expect(find.byTooltip('Achievements'), findsOneWidget);
    expect(find.byTooltip('Daily challenges'), findsOneWidget);
    expect(find.byTooltip('Cosmetic shop'), findsOneWidget);
    expect(find.byTooltip('Player statistics'), findsOneWidget);
    expect(find.byTooltip('Music on'), findsOneWidget);
    expect(find.byTooltip('Sound effects on'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main menu header fits a narrow layout without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: OrbitGamePage(audioController: _UiTestAudio())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('main-menu-gem-balance')), findsOneWidget);
    expect(find.byTooltip('Achievements'), findsOneWidget);
    expect(find.byTooltip('Daily challenges'), findsOneWidget);
    expect(find.byTooltip('Cosmetic shop'), findsOneWidget);
    expect(find.byTooltip('Player statistics'), findsOneWidget);
    expect(find.text('ORBIT DASH'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _UiTestAudio extends GameAudioController {
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
