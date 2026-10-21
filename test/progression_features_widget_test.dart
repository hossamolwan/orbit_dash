import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('skin picker locks, selects, persists, and remains cosmetic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AchievementStore.totalGemsKey: 25,
      GemWallet.stateKey:
          '{"version":1,"balance":40,"grants":[],"purchases":{}}',
      'orbit_dash_best': 7,
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _FeatureTestAudio(),
          testDriver: driver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();

    expect(driver.skinUnlocked(ShipSkinId.emerald), isFalse);
    expect(driver.skinUnlocked(ShipSkinId.nebula), isFalse);
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('skin-option-supernova')), findsOneWidget);
    expect(find.textContaining('NEED 60 MORE'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('skin-option-nebula')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('skin-option-emerald')));
    await tester.pumpAndSettle();
    expect(driver.skinUnlocked(ShipSkinId.emerald), isTrue);
    expect(driver.walletBalance, 0);
    expect(find.text('GEMS  0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skin-option-emerald')));
    await tester.pumpAndSettle();
    await driver.flushProgress();
    expect(driver.selectedSkin, ShipSkinId.emerald);
    expect(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.getString(SkinStore.selectedSkinKey),
      ),
      completion(ShipSkinId.emerald.name),
    );

    await tester.ensureVisible(find.text('MAIN MENU'));
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runsStarted, 1);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('RESUME'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runsStarted, 1);
    expect(driver.score, 0);
    driver.placeGemAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushAchievements();
    await driver.flushProgress();
    expect(driver.score, 1);
    expect(driver.walletBalance, 1);
    expect(driver.totalGems, 26);
    expect(driver.selectedSkin, ShipSkinId.emerald);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed queued write does not block a later write and flush reports it',
    (tester) async {
      final driver = OrbitGameTestDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: OrbitGamePage(
            audioController: _FeatureTestAudio(),
            testDriver: driver,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await driver.flushProgress();

      var laterWriteRan = false;
      driver.queueFeatureWrite(
        () async => throw StateError('expected test failure'),
      );
      driver.queueFeatureWrite(() async {
        laterWriteRan = true;
      });
      await expectLater(driver.flushProgress(), throwsStateError);
      expect(laterWriteRan, isTrue);
      await driver.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('statistics count a run, absorbed collision, and one loss once', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _FeatureTestAudio(),
          testDriver: driver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runsStarted, 1);

    driver.placeGemAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushAchievements();
    await driver.flushProgress();
    expect(driver.score, 1);

    driver.placeShieldAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    driver.placeHazardAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushProgress();
    expect(driver.shieldAbsorptions, 1);
    expect(driver.losses, 0);

    driver.placeHazardAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushProgress();
    expect(driver.runState, RunState.over);
    expect(driver.losses, 1);
    await tester.pump(const Duration(seconds: 1));
    await driver.flushProgress();
    expect(driver.losses, 1);

    await tester.tap(find.text('RETRY RUN'));
    await tester.pump();
    await driver.flushProgress();
    expect(driver.runsStarted, 2);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('MAIN MENU'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Player statistics'));
    await tester.pumpAndSettle();
    await driver.flushProgress();
    expect(find.text('PLAYER STATISTICS'), findsOneWidget);
    expect(find.text('LIFETIME GEMS'), findsOneWidget);
    expect(find.text('RUNS STARTED'), findsOneWidget);
    expect(find.text('LOSSES'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FeatureTestAudio extends GameAudioController {
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
