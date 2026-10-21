import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'orbit_dash_best': 12,
      'orbit_dash_survival_best': 12,
    });
  });

  test('bundles the Suno MP3 at the menu music asset path', () async {
    final data = await rootBundle.load(
      'assets/${GameAudioManager.menuMusicAsset}',
    );

    final header = List.generate(4, data.getUint8);
    final hasId3Header =
        header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33;
    final version = (header[1] >> 3) & 0x03;
    final layer = (header[1] >> 1) & 0x03;
    final bitrateIndex = (header[2] >> 4) & 0x0f;
    final sampleRateIndex = (header[2] >> 2) & 0x03;
    final hasMpegAudioFrameHeader =
        header[0] == 0xff &&
        (header[1] & 0xe0) == 0xe0 &&
        version != 0x01 &&
        layer != 0 &&
        bitrateIndex != 0 &&
        bitrateIndex != 0x0f &&
        sampleRateIndex != 0x03;
    expect(hasId3Header || hasMpegAudioFrameHeader, isTrue);
    expect(data.lengthInBytes, greaterThan(1000000));
  });

  group('angular collision helpers', () {
    test('finds the shortest distance across the zero boundary', () {
      expect(
        shortestAngularDistance(0.03, 2 * math.pi - 0.04),
        closeTo(0.07, 1e-12),
      );
      expect(
        shortestAngularDistance(2 * math.pi - 0.04, 0.03),
        closeTo(0.07, 1e-12),
      );
    });

    test('works after multiple full rotations', () {
      expect(
        shortestAngularDistance(8 * math.pi + 0.03, 6 * math.pi - 0.04),
        closeTo(0.07, 1e-12),
      );
    });

    test('preserves the strict collision threshold', () {
      expect(isAngularCollision(0, 0.159), isTrue);
      expect(isAngularCollision(0, 0.16), isFalse);
      expect(isAngularCollision(0, 0.161), isFalse);
    });
  });

  group('achievement persistence', () {
    test('counts gems and unlocks both thresholds exactly once', () async {
      SharedPreferences.setMockInitialValues({
        'orbit_dash_best': 21,
        'orbit_dash_unlocked_stage': 3,
      });
      final store = AchievementStore();
      await store.load();

      for (var gem = 0; gem < 9; gem++) {
        expect(await store.recordGem(), isEmpty);
      }
      expect(store.totalGems, 9);
      expect(store.isUnlocked(AchievementId.firstSteps), isFalse);
      expect(store.isUnlocked(AchievementId.gemCollector), isFalse);
      expect(await store.recordGem(), [AchievementId.firstSteps]);
      expect(store.isUnlocked(AchievementId.gemCollector), isFalse);

      for (var gem = 10; gem < 49; gem++) {
        expect(await store.recordGem(), isEmpty);
      }
      expect(store.totalGems, 49);
      expect(store.isUnlocked(AchievementId.gemCollector), isFalse);
      expect(await store.recordGem(), [AchievementId.gemCollector]);
      expect(await store.recordGem(), isEmpty);
      expect(store.totalGems, 51);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('orbit_dash_best'), 21);
      expect(preferences.getInt('orbit_dash_unlocked_stage'), 3);
      expect(
        preferences.getBool(
          AchievementStore.preferenceKeyFor(AchievementId.firstSteps),
        ),
        isTrue,
      );
      expect(
        preferences.getBool(
          AchievementStore.preferenceKeyFor(AchievementId.gemCollector),
        ),
        isTrue,
      );

      final restored = AchievementStore();
      await restored.load();
      expect(restored.totalGems, 51);
      expect(restored.isUnlocked(AchievementId.firstSteps), isTrue);
      expect(restored.isUnlocked(AchievementId.gemCollector), isTrue);
    });

    test('keeps achievement flags independent and idempotent', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AchievementStore();
      await store.load();
      expect(await store.unlock(AchievementId.savedByShield), [
        AchievementId.savedByShield,
      ]);
      expect(await store.unlock(AchievementId.savedByShield), isEmpty);
      expect(store.isUnlocked(AchievementId.firstSteps), isFalse);
      expect(store.isUnlocked(AchievementId.orbitExplorer), isFalse);
    });
  });
  group('temporary shield', () {
    test('activates for five seconds and expires without a collision', () {
      final shield = TemporaryShield();
      expect(shield.activate(), isTrue);
      expect(shield.isActive, isTrue);
      expect(shield.remaining, const Duration(seconds: 5));

      shield.advance(const Duration(seconds: 4));
      expect(shield.isActive, isTrue);
      expect(shield.remaining, const Duration(seconds: 1));
      shield.advance(const Duration(seconds: 1));
      expect(shield.isActive, isFalse);
      expect(shield.remaining, Duration.zero);
    });

    test('does not extend an active shield and absorbs only one collision', () {
      final shield = TemporaryShield();
      expect(shield.activate(), isTrue);
      shield.advance(const Duration(seconds: 2));
      expect(shield.activate(), isFalse);
      expect(shield.remaining, const Duration(seconds: 3));

      expect(
        shieldCollisionResponse(shield, collision: true),
        ShieldCollisionResponse.absorbed,
      );
      expect(shield.isActive, isFalse);
      expect(
        shieldCollisionResponse(shield, collision: true),
        ShieldCollisionResponse.fatal,
      );
    });

    test('a non-collision leaves the remaining shield duration unchanged', () {
      final shield = TemporaryShield()..activate();
      shield.advance(const Duration(seconds: 2));
      expect(
        shieldCollisionResponse(shield, collision: false),
        ShieldCollisionResponse.noCollision,
      );
      expect(shield.isActive, isTrue);
      expect(shield.remaining, const Duration(seconds: 3));
    });
    test('pickup uses the same lane and angular collection rules as gems', () {
      expect(
        shouldCollectShield(
          playerLane: 2,
          shieldLane: 2,
          playerAngle: 0,
          shieldAngle: .1,
        ),
        isTrue,
      );
      expect(
        shouldCollectShield(
          playerLane: 2,
          shieldLane: 3,
          playerAngle: 0,
          shieldAngle: .01,
        ),
        isFalse,
      );
      expect(
        shouldCollectShield(
          playerLane: 2,
          shieldLane: 2,
          playerAngle: 0,
          shieldAngle: .13,
        ),
        isFalse,
      );
    });
  });
  group('temporary shield game integration', () {
    testWidgets('pickup activates the rendered aura without scoring', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final driver = await _startShieldGame(tester);
      driver.placeShieldAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));

      expect(driver.shieldActive, isTrue);
      await driver.flushAchievements();
      expect(driver.achievementUnlocked(AchievementId.savedByShield), isFalse);
      expect(find.byKey(const ValueKey('shield-aura-visible')), findsOneWidget);
      expect(driver.score, 0);
      expect(driver.runState, RunState.playing);

      driver.placeGemAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.shieldActive, isTrue);
      expect(driver.score, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'absorbs and removes one hazard, then the next hit ends the run',
      (tester) async {
        final driver = await _startShieldGame(tester);
        driver.placeShieldAtPlayer();
        await tester.pump(const Duration(milliseconds: 16));
        expect(driver.shieldActive, isTrue);

        driver.placeHazardAtPlayer();
        await tester.pump(const Duration(milliseconds: 16));
        expect(driver.runState, RunState.playing);
        expect(driver.shieldActive, isFalse);
        expect(driver.hazardCount, 0);
        await driver.flushAchievements();
        expect(driver.achievementUnlocked(AchievementId.savedByShield), isTrue);
        expect(find.text('RUN OVER'), findsNothing);

        driver.placeHazardAtPlayer();
        await tester.pump(const Duration(milliseconds: 16));
        expect(driver.runState, RunState.over);
        expect(find.text('RUN OVER'), findsOneWidget);

        await tester.tap(find.text('RETRY RUN'));
        await tester.pump();
        expect(driver.runState, RunState.playing);
        expect(driver.shieldActive, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('expires after five seconds and restores fatal collisions', (
      tester,
    ) async {
      final driver = await _startShieldGame(tester);
      driver.placeShieldAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.shieldActive, isTrue);

      for (var frame = 0; frame < 120 && driver.shieldActive; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(driver.shieldActive, isFalse);
      expect(find.byKey(const ValueKey('shield-aura-visible')), findsNothing);
      expect(driver.runState, RunState.playing);
      expect(driver.score, 0);

      driver.placeHazardAtPlayer();
      await tester.pump(const Duration(milliseconds: 50));
      expect(driver.runState, RunState.over);
      expect(find.text('RUN OVER'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'freezes the remaining duration during pause, then resumes it',
      (tester) async {
        final driver = await _startShieldGame(tester);
        driver.placeShieldAtPlayer();
        await tester.pump(const Duration(milliseconds: 16));
        expect(driver.shieldActive, isTrue);
        final remainingAtPause = driver.shieldRemaining;

        await tester.tap(find.byTooltip('Pause'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 20));
        expect(driver.runState, RunState.paused);
        expect(driver.shieldRemaining, remainingAtPause);
        expect(
          find.byKey(const ValueKey('shield-aura-visible')),
          findsOneWidget,
        );

        await tester.tap(find.text('RESUME'));
        await tester.pump();
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(driver.runState, RunState.playing);
        expect(driver.shieldActive, isTrue);
        expect(driver.shieldRemaining, lessThan(remainingAtPause));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
  group('hazard cleanup', () {
    test(
      'keeps a hazard near alignment and expires it after a full relative turn',
      () {
        final nearAlignment = math.pi + 0.4;
        expect(hazardLifetimeExpired(nearAlignment - 0.01), isFalse);
        expect(hazardLifetimeExpired(nearAlignment), isFalse);
        expect(hazardLifetimeExpired(nearAlignment + 0.01), isFalse);
        expect(hazardLifetimeExpired(2 * math.pi), isTrue);
      },
    );
  });

  group('score-based difficulty', () {
    test('preserves the starting speed and spawn interval', () {
      expect(playerSpeedForScore(0), 1.55);
      expect(hazardSpawnIntervalForScore(0), 2.0);
    });

    test('speed does not decrease and spawn interval does not increase', () {
      var previousSpeed = playerSpeedForScore(0);
      var previousInterval = hazardSpawnIntervalForScore(0);

      for (var score = 1; score <= 100; score++) {
        final speed = playerSpeedForScore(score);
        final interval = hazardSpawnIntervalForScore(score);
        expect(speed, greaterThanOrEqualTo(previousSpeed));
        expect(interval, lessThanOrEqualTo(previousInterval));
        previousSpeed = speed;
        previousInterval = interval;
      }
    });

    test('respects the established high-score limits', () {
      expect(playerSpeedForScore(100), lessThan(maxSurvivalPlayerSpeed));
      expect(
        hazardSpawnIntervalForScore(100),
        greaterThan(minSurvivalHazardInterval),
      );
      expect(
        playerSpeedForScore(1000),
        lessThanOrEqualTo(maxSurvivalPlayerSpeed),
      );
      expect(hazardSpawnIntervalForScore(1000), minSurvivalHazardInterval);
    });
  });

  test('Survival orbit thresholds and randomized placement stay valid', () {
    expect(survivalOrbitCountForScore(0), 2);
    expect(survivalOrbitCountForScore(9), 2);
    expect(survivalOrbitCountForScore(10), 3);
    expect(survivalOrbitCountForScore(25), 4);
    expect(survivalOrbitCountForScore(45), 5);
    for (final seed in [1, 17, 91]) {
      final random = math.Random(seed);
      for (var i = 0; i < 100; i++) {
        final placement = randomizedGemPlacement(
          orbitCount: 3,
          random: random,
          avoidAngle: 0,
        );
        expect(placement.lane, inInclusiveRange(0, 2));
        expect(placement.angle, inInclusiveRange(0, 2 * math.pi));
        expect(
          shortestAngularDistance(placement.angle, 0),
          greaterThanOrEqualTo(.65),
        );
      }
    }
  });
  test('audio settings default on and persist independently', () async {
    final settings = GameAudioSettings();
    await settings.load();
    expect(settings.musicEnabled, isTrue);
    expect(settings.effectsEnabled, isTrue);

    await settings.setMusicEnabled(false);
    var restored = GameAudioSettings();
    await restored.load();
    expect(restored.musicEnabled, isFalse);
    expect(restored.effectsEnabled, isTrue);
    restored.dispose();

    await settings.setEffectsEnabled(false);
    restored = GameAudioSettings();
    await restored.load();
    expect(restored.musicEnabled, isFalse);
    expect(restored.effectsEnabled, isFalse);
    settings.dispose();
    restored.dispose();
  });

  testWidgets('a Survival run unlocks orbits and continues past 50 gems', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _TestAudioController(),
          testDriver: driver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    expect(driver.orbitCount, 2);
    for (var gem = 1; gem <= 55; gem++) {
      driver.placeGemAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      if (gem == 9) expect(driver.orbitCount, 2);
      if (gem == 10) expect(driver.orbitCount, 3);
      if (gem == 24) expect(driver.orbitCount, 3);
      if (gem == 25) expect(driver.orbitCount, 4);
      if (gem == 45) expect(driver.orbitCount, 5);
      expect(driver.runState, RunState.playing);
    }
    await driver.flushProgress();
    expect(driver.score, 55);
    expect(driver.walletBalance, 55);
    expect(driver.runState, RunState.playing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Survival record uses a separate preference from the campaign record',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'orbit_dash_best': 21,
        'orbit_dash_survival_best': 0,
      });
      final driver = OrbitGameTestDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: OrbitGamePage(
            audioController: _TestAudioController(),
            testDriver: driver,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('START RUN'));
      await tester.pump();
      driver.placeGemAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      driver.placeHazardAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      await driver.flushProgress();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('orbit_dash_best'), 21);
      expect(prefs.getInt('orbit_dash_survival_best'), 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('shows the start screen and starts a run', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    expect(find.text('READY, PILOT?'), findsOneWidget);
    expect(find.text('Dodge the red. Chase the glow.'), findsOneWidget);
    expect(find.text('BEST SURVIVAL'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('START RUN'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('START RUN'));
    await tester.pump();
    expect(find.text('READY, PILOT?'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsOneWidget);
  });

  testWidgets('pause screen resumes or restarts through existing actions', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('CURRENT SCORE'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('RESTART RUN'), findsOneWidget);

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('RESTART RUN'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows the final score and best result, then replays', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'orbit_dash_best': 12,
      'orbit_dash_survival_best': 12,
      'orbit_dash_unlocked_stage': 3,
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(_testApp(testDriver: driver));
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    driver.placeHazardAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('RUN OVER'), findsOneWidget);
    expect(find.text('GEMS COLLECTED'), findsOneWidget);
    expect(find.text('BEST SURVIVAL'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('RETRY RUN'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('RETRY RUN'));
    await tester.pump();
    expect(find.text('RUN OVER'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('start panel fits a compact viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    expect(find.text('START RUN'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
    final buttonRect = tester.getRect(find.text('START RUN'));
    expect(buttonRect.left, greaterThanOrEqualTo(0));
    expect(buttonRect.right, lessThanOrEqualTo(320));
    expect(buttonRect.bottom, lessThanOrEqualTo(568));

    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
    expect(tester.getRect(find.text('RESUME')).bottom, lessThanOrEqualTo(568));
    expect(
      tester.getRect(find.text('RESTART RUN')).bottom,
      lessThanOrEqualTo(568),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live score HUD fits above the orbit on a compact viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    final statusFinder = find.byKey(const ValueKey('survival-status'));
    final scoreFinder = find.byKey(const ValueKey('score'));
    final statusRect = tester.getRect(statusFinder);
    final scoreRect = tester.getRect(scoreFinder);
    final orbitRect = tester.getRect(
      find.byKey(const ValueKey('orbit-lane-0')),
    );
    final statusPosition = tester.widget<Positioned>(
      find.ancestor(of: statusFinder, matching: find.byType(Positioned)),
    );

    expect(statusPosition.top, greaterThanOrEqualTo(0));
    expect(statusRect.top, greaterThanOrEqualTo(0));
    expect(statusRect.bottom, lessThanOrEqualTo(568));
    expect(statusRect.height, greaterThan(0));
    expect(statusRect.bottom, lessThanOrEqualTo(scoreRect.top));
    expect(scoreRect.top, greaterThanOrEqualTo(0));
    expect(scoreRect.bottom, lessThanOrEqualTo(orbitRect.top));
    expect(scoreRect.bottom, lessThanOrEqualTo(568));
    expect(scoreRect.center.dx, closeTo(160, 0.1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live score HUD remains readable on a wider viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    final statusRect = tester.getRect(
      find.byKey(const ValueKey('survival-status')),
    );
    final scoreRect = tester.getRect(find.byKey(const ValueKey('score')));
    expect(statusRect.top, greaterThanOrEqualTo(0));
    expect(statusRect.bottom, lessThanOrEqualTo(900));
    expect(scoreRect.center.dx, closeTo(300, 0.1));
    expect(scoreRect.bottom, lessThanOrEqualTo(900));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('game over panel fits a compact viewport without scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(_testApp(testDriver: driver));
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    driver.placeHazardAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('RUN OVER'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
    for (final label in [
      'RUN OVER',
      'GEMS COLLECTED',
      'RETRY RUN',
      'MAIN MENU',
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.top,
        greaterThanOrEqualTo(0),
        reason: '$label is above screen',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(568),
        reason: '$label is below screen',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('persists gem progress across retry and a recreated game page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({AchievementStore.totalGemsKey: 9});
    final driver = await _startShieldGame(tester);
    driver.placeGemAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushAchievements();

    expect(driver.score, 1);
    expect(driver.totalGems, 10);
    expect(driver.achievementUnlocked(AchievementId.firstSteps), isTrue);
    expect(find.text('First Steps unlocked!'), findsOneWidget);

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pump(const Duration(milliseconds: 400));
    driver.placeGemAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    await driver.flushAchievements();
    expect(driver.totalGems, 11);
    expect(find.text('First Steps unlocked!'), findsNothing);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.tap(find.text('RESTART RUN'));
    await tester.pump();
    await driver.flushAchievements();
    expect(driver.score, 0);
    expect(driver.totalGems, 11);
    expect(driver.achievementUnlocked(AchievementId.firstSteps), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Achievements'));
    await tester.pumpAndSettle();
    expect(find.text('Total gems: 11'), findsOneWidget);
    expect(find.text('First Steps'), findsOneWidget);
    expect(find.text('Gem Collector'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('achievement-status-firstSteps')),
          )
          .data,
      'OPEN',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('achievement-status-gemCollector')),
          )
          .data,
      'LOCKED',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('achievements screen fits a compact phone viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Achievements'));
    await tester.pumpAndSettle();

    expect(find.text('ACHIEVEMENTS'), findsOneWidget);
    for (final achievement in achievementDefinitions) {
      expect(
        find.byKey(ValueKey('achievement-${achievement.id.name}')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('achievement-status-${achievement.id.name}')),
            )
            .data,
        'LOCKED',
      );
      final card = tester.getRect(
        find.byKey(ValueKey('achievement-${achievement.id.name}')),
      );
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('MAIN MENU'));
    await tester.pump();
    expect(
      tester.getRect(find.text('MAIN MENU')).bottom,
      lessThanOrEqualTo(568),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('achievement load failure shows retry and restores saved data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AchievementStore.totalGemsKey: 14,
      AchievementStore.preferenceKeyFor(AchievementId.firstSteps): true,
      'orbit_dash_best': 12,
    });
    var loadAttempts = 0;
    final driver = OrbitGameTestDriver(
      achievementPreferencesLoader: () {
        loadAttempts++;
        if (loadAttempts == 1) {
          throw StateError('Temporary preferences load failure');
        }
        return SharedPreferences.getInstance();
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: OrbitGamePage(testDriver: driver)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Achievements'));
    await tester.pumpAndSettle();

    expect(loadAttempts, 1);
    expect(
      find.text(
        'Could not load saved achievements. Your saved progress is unchanged.',
      ),
      findsOneWidget,
    );
    expect(find.text('Loading saved progress...'), findsNothing);
    expect(find.text('Total gems: 14'), findsNothing);
    expect(find.byKey(const ValueKey('achievement-firstSteps')), findsNothing);
    expect(find.text('RETRY'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(AchievementStore.totalGemsKey), 14);
    expect(
      preferences.getBool(
        AchievementStore.preferenceKeyFor(AchievementId.firstSteps),
      ),
      isTrue,
    );

    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(find.text('Could not load saved achievements.'), findsNothing);
    expect(find.text('Total gems: 14'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('achievement-firstSteps')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('achievement-status-firstSteps')),
          )
          .data,
      'OPEN',
    );
    expect(preferences.getInt(AchievementStore.totalGemsKey), 14);
  });
  group('variable orbit geometry', () {
    for (var count = 2; count <= 5; count++) {
      test('$count orbit lanes have direct, distinct touch targets', () {
        final geometry = OrbitGeometry.forSizeAndCount(
          const Size(360, 360),
          orbitCount: count,
        );
        expect(geometry.radii, hasLength(count));
        for (var lane = 0; lane < count; lane++) {
          final point =
              geometry.center + Offset(geometry.radiusForLane(lane), 0);
          expect(geometry.laneAt(point), lane);
          expect(
            geometry.laneAt(
              geometry.center +
                  Offset(
                    geometry.radiusForLane(lane) + geometry.touchTolerance * .9,
                    0,
                  ),
            ),
            lane,
          );
          expect(laneAfterOrbitTouch(0, geometry, point), lane);
          expect(laneAfterOrbitTouch(lane, geometry, point), lane);
        }
        for (var lane = 0; lane < count - 1; lane++) {
          final midpointRadius =
              (geometry.radii[lane] + geometry.radii[lane + 1]) / 2;
          final midpoint = geometry.center + Offset(midpointRadius, 0);
          expect(geometry.laneAt(midpoint), isNull);
          expect(laneAfterOrbitTouch(lane, geometry, midpoint), lane);
        }
        expect(geometry.laneAt(geometry.center), isNull);
        expect(
          geometry.laneAt(
            geometry.center + Offset(geometry.outerRadius * 1.5, 0),
          ),
          isNull,
        );
      });
    }

    test('two orbit radii preserve the original spacing', () {
      final geometry = OrbitGeometry.forSizeAndCount(
        const Size(360, 360),
        orbitCount: 2,
      );
      expect(geometry.innerRadius, closeTo(360 * .245, .0001));
      expect(geometry.outerRadius, closeTo(360 * .34, .0001));
    });
  });

  testWidgets('five Survival orbits remain tappable on a compact display', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(_testApp(testDriver: driver));
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    for (var gem = 0; gem < 45; gem++) {
      driver.placeGemAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(driver.score, 45);
    expect(driver.orbitCount, 5);
    await _tapOrbitLane(tester, 4, 5);
    expect(find.byKey(const ValueKey('orbit-lane-4')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('lane-aware hazards and gems preserve angle rules', () {
    expect(
      isLaneCollision(
        playerLane: 4,
        hazardLane: 4,
        playerAngle: 0,
        hazardAngle: .1,
      ),
      isTrue,
    );
    expect(
      isLaneCollision(
        playerLane: 1,
        hazardLane: 3,
        playerAngle: 0,
        hazardAngle: .01,
      ),
      isFalse,
    );
    expect(
      shouldCollectGem(playerLane: 3, gemLane: 3, playerAngle: 0, gemAngle: .1),
      isTrue,
    );
    expect(
      shouldCollectGem(
        playerLane: 2,
        gemLane: 4,
        playerAngle: 0,
        gemAngle: .01,
      ),
      isFalse,
    );
    expect(nextOrbitLane(4, 5), 0);
    for (var count = 2; count <= 5; count++) {
      for (var lane = 0; lane < count; lane++) {
        final nextLane = nextOrbitLane(lane, count);
        expect(nextLane, inInclusiveRange(0, count - 1));
        for (var score = 0; score < 8; score++) {
          final hazardLane = hazardLaneForScore(score, lane, count);
          expect(hazardLane, inInclusiveRange(0, count - 1));
          if (count > 2) expect(hazardLane, isNot(lane));
        }
      }
    }
    expect(hazardLaneForScore(2, 0, 2), 1);
  });

  testWidgets('audio controls and cues follow game state transitions', (
    tester,
  ) async {
    final audio = _TestAudioController();
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: audio, testDriver: driver),
      ),
    );
    await tester.pump();

    expect(audio.states, contains(AudioRunState.menu));
    await tester.tap(find.byTooltip('Music on'));
    await tester.pump();
    expect(audio.musicEnabled, isFalse);
    expect(find.byTooltip('Music off'), findsOneWidget);
    await tester.tap(find.byTooltip('Sound effects on'));
    await tester.pump();
    expect(audio.effectsEnabled, isFalse);
    expect(find.byTooltip('Sound effects off'), findsOneWidget);

    await tester.tap(find.byTooltip('Music off'));
    await tester.pump();
    await tester.tap(find.byTooltip('Sound effects off'));
    await tester.pump();
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    expect(audio.states, contains(AudioRunState.playing));
    expect(audio.effects, contains(GameSoundEffect.start));

    await tester.tap(find.byKey(const ValueKey('game-area')));
    await tester.pump();
    expect(audio.effects, isNot(contains(GameSoundEffect.orbitSwitch)));
    expect(audio.states.last, AudioRunState.playing);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(audio.states, contains(AudioRunState.paused));
    expect(audio.effects, contains(GameSoundEffect.pause));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(audio.activeStates, contains(false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(audio.activeStates, contains(true));

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(audio.effects, contains(GameSoundEffect.resume));

    driver.placeHazardAtPlayer();
    await tester.pump(const Duration(milliseconds: 16));
    expect(audio.states, contains(AudioRunState.over));
    expect(audio.effects, contains(GameSoundEffect.collision));

    await tester.tap(find.text('MAIN MENU'));
    await tester.pump();
    expect(find.text('READY, PILOT?'), findsOneWidget);
    expect(audio.states.last, AudioRunState.menu);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<OrbitGameTestDriver> _startShieldGame(WidgetTester tester) async {
  final driver = OrbitGameTestDriver();
  await tester.pumpWidget(
    MaterialApp(
      home: OrbitGamePage(
        audioController: _TestAudioController(),
        testDriver: driver,
      ),
    ),
  );
  await tester.tap(find.text('START RUN'));
  await tester.pump();
  await _tapOrbitLane(tester, 1, 2);
  driver.moveGemAwayFromPlayer();
  await tester.pump(const Duration(milliseconds: 16));
  expect(driver.runState, RunState.playing);
  await driver.flushAchievements();
  return driver;
}

Widget _testApp({OrbitGameTestDriver? testDriver}) => MaterialApp(
  home: OrbitGamePage(
    audioController: _TestAudioController(),
    testDriver: testDriver,
  ),
);

class _TestAudioController extends GameAudioController {
  bool _musicEnabled = true;
  bool _effectsEnabled = true;
  final List<AudioRunState> states = [];
  final List<GameSoundEffect> effects = [];
  final List<bool> activeStates = [];

  @override
  bool get musicEnabled => _musicEnabled;

  @override
  bool get effectsEnabled => _effectsEnabled;

  @override
  Future<void> initialize() async {}

  @override
  void setGameState(AudioRunState state) => states.add(state);

  @override
  void setAppActive(bool active) => activeStates.add(active);

  @override
  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    notifyListeners();
  }

  @override
  Future<void> setEffectsEnabled(bool enabled) async {
    _effectsEnabled = enabled;
    notifyListeners();
  }

  @override
  void playEffect(GameSoundEffect effect) => effects.add(effect);

  @override
  Future<void> shutdown() async => dispose();
}

Future<void> _tapOrbitLane(
  WidgetTester tester,
  int lane,
  int orbitCount,
) async {
  final currentLane = List.generate(5, (index) => index).firstWhere(
    (index) => find.byKey(ValueKey('orbit-lane-$index')).evaluate().isNotEmpty,
  );
  final rect = tester.getRect(find.byKey(ValueKey('orbit-lane-$currentLane')));
  final geometry = OrbitGeometry.forSizeAndCount(
    rect.size,
    orbitCount: orbitCount,
  );
  await tester.tapAt(
    rect.topLeft + geometry.center + Offset(geometry.radiusForLane(lane), 0),
  );
  await tester.pump();
}
