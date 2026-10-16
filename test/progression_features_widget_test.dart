import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('skin picker locks, selects, persists, and remains cosmetic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AchievementStore.totalGemsKey: 25,
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

    expect(driver.skinUnlocked(ShipSkinId.emerald), isTrue);
    expect(driver.skinUnlocked(ShipSkinId.nebula), isFalse);
    await tester.tap(find.byTooltip('Ship skins'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('skin-option-supernova')), findsOneWidget);
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
    expect(driver.selectedSkin, ShipSkinId.emerald);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('statistics count a run, absorbed collision, and one loss once', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _FeatureTestAudio(),
          testDriver: driver,
          stages: const [
            StageDefinition(
              number: 1,
              name: 'Statistics Test',
              targetScore: 50,
              orbitCount: 2,
            ),
          ],
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

    await tester.tap(find.text('RETRY STAGE'));
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

  testWidgets(
    'stage completion history stays distinct and unlocks stage skins',
    (tester) async {
      const stages = [
        StageDefinition(number: 1, name: 'One', targetScore: 1, orbitCount: 2),
        StageDefinition(number: 2, name: 'Two', targetScore: 1, orbitCount: 3),
        StageDefinition(
          number: 3,
          name: 'Three',
          targetScore: 1,
          orbitCount: 4,
        ),
        StageDefinition(number: 4, name: 'Four', targetScore: 1, orbitCount: 5),
        StageDefinition(number: 5, name: 'Five', targetScore: 1, orbitCount: 5),
      ];
      final driver = OrbitGameTestDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: OrbitGamePage(
            audioController: _FeatureTestAudio(),
            stages: stages,
            testDriver: driver,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await driver.flushProgress();
      await tester.tap(find.text('START RUN'));
      await tester.pump();

      for (var stage = 1; stage <= 5; stage++) {
        if (stage > 1) {
          await tester.tap(find.text('CONTINUE TO STAGE $stage'));
          await tester.pump();
          await tester.pump();
        }
        await _completeStage(tester, stages[stage - 1].orbitCount);
        await driver.flushProgress();
        expect(driver.runsStarted, stage);
        expect(driver.distinctStagesCompleted, stage);
        if (stage == 3) expect(driver.skinUnlocked(ShipSkinId.solar), isTrue);
        if (stage < 5) {
          expect(find.text('STAGE COMPLETE'), findsOneWidget);
        }
      }
      expect(find.text('GAME COMPLETE'), findsOneWidget);
      expect(driver.skinUnlocked(ShipSkinId.supernova), isTrue);
      await driver.flushProgress();
      expect(driver.distinctStagesCompleted, 5);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _completeStage(WidgetTester tester, int orbitCount) async {
  if (orbitCount > 2) await _tapLane(tester, orbitCount - 1, orbitCount);
  await _tapLane(tester, 1, orbitCount);
  for (var frame = 0; frame < 45; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('STAGE COMPLETE').evaluate().isNotEmpty ||
        find.text('GAME COMPLETE').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Stage did not complete within the expected gameplay frames.');
}

Future<void> _tapLane(WidgetTester tester, int lane, int orbitCount) async {
  final currentLaneNumber = List<int>.generate(orbitCount, (i) => i).firstWhere(
    (lane) =>
        find.byKey(ValueKey<String>('orbit-lane-$lane')).evaluate().isNotEmpty,
  );
  final rect = tester.getRect(
    find.byKey(ValueKey<String>('orbit-lane-$currentLaneNumber')),
  );
  final geometry = OrbitGeometry.forSizeAndCount(
    rect.size,
    orbitCount: orbitCount,
  );
  await tester.tapAt(
    rect.topLeft + geometry.center + Offset(geometry.radiusForLane(lane), 0),
  );
  await tester.pump();
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
