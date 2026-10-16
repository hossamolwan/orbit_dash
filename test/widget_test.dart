import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'orbit_dash_best': 12});
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
      expect(find.byKey(const ValueKey('shield-aura-visible')), findsOneWidget);
      expect(driver.score, 0);
      expect(driver.runState, RunState.playing);
      expect(await StageProgressStore().loadUnlockedStage(), 1);

      driver.placeGemAtPlayer();
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.shieldActive, isTrue);
      expect(driver.score, 1);
      expect(await StageProgressStore().loadUnlockedStage(), 1);
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
        expect(find.text('STAGE FAILED'), findsNothing);

        driver.placeHazardAtPlayer();
        await tester.pump(const Duration(milliseconds: 16));
        expect(driver.runState, RunState.over);
        expect(find.text('STAGE FAILED'), findsOneWidget);

        await tester.tap(find.text('RETRY STAGE'));
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
      expect(find.text('STAGE FAILED'), findsOneWidget);
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
      expect(playerSpeedForScore(100), 3.05);
      expect(hazardSpawnIntervalForScore(100), 0.85);
      expect(playerSpeedForScore(1000), 3.05);
      expect(hazardSpawnIntervalForScore(1000), 0.85);
    });
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

  testWidgets('shows the start screen and starts a run', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    expect(find.text('READY, PILOT?'), findsOneWidget);
    expect(find.text('Dodge the red. Chase the glow.'), findsOneWidget);
    expect(find.text('BEST FLIGHT'), findsOneWidget);
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
    expect(find.text('RESTART STAGE'), findsOneWidget);

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('RESTART STAGE'));
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
      StageProgressStore.preferenceKey: 3,
    });
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    for (var frame = 0; frame < 220; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('STAGE FAILED').evaluate().isNotEmpty) break;
    }

    expect(find.text('STAGE FAILED'), findsOneWidget);
    expect(find.text('FINAL SCORE'), findsOneWidget);
    expect(find.text('BEST FLIGHT'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('RETRY STAGE'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('RETRY STAGE'));
    await tester.pump();
    expect(find.text('STAGE FAILED'), findsNothing);
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
      tester.getRect(find.text('RESTART STAGE')).bottom,
      lessThanOrEqualTo(568),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live score sits above the orbit on a compact viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    final scoreRect = tester.getRect(find.byKey(const ValueKey('score')));
    final orbitRect = tester.getRect(
      find.byKey(const ValueKey('orbit-lane-0')),
    );
    expect(find.textContaining('STAGE 1'), findsOneWidget);
    expect(scoreRect.top, greaterThanOrEqualTo(0));
    expect(scoreRect.bottom, lessThanOrEqualTo(orbitRect.top));
    expect(scoreRect.bottom, lessThanOrEqualTo(568));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('game over panel fits a compact viewport without scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    for (var frame = 0; frame < 220; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('STAGE FAILED').evaluate().isNotEmpty) break;
    }

    expect(find.text('STAGE FAILED'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
    for (final label in [
      'STAGE FAILED',
      'FINAL SCORE',
      'RETRY STAGE',
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

  test('stage definitions expose the required goals and orbit counts', () {
    expect(
      orbitStages
          .map(
            (stage) => [
              stage.number,
              stage.name,
              stage.targetScore,
              stage.orbitCount,
            ],
          )
          .toList(),
      [
        [1, 'First Orbit', 10, 2],
        [2, 'Gem Hunter', 15, 3],
        [3, 'Asteroid Rush', 25, 4],
        [4, 'Cosmic Trial', 35, 5],
        [5, 'Orbital Master', 50, 5],
      ],
    );
  });

  test('stage completion gate fires once and can reset for replay', () {
    final gate = StageCompletionGate();
    final firstStage = orbitStages.first;
    final finalStage = orbitStages.last;
    expect(gate.completeIfReached(9, firstStage), isFalse);
    expect(gate.completeIfReached(10, firstStage), isTrue);
    expect(gate.completeIfReached(11, firstStage), isFalse);
    gate.reset();
    expect(gate.completeIfReached(50, finalStage), isTrue);
    expect(gate.completeIfReached(51, finalStage), isFalse);
  });

  test('stage progress defaults safely and never moves backward', () async {
    final store = StageProgressStore();
    expect(await store.loadUnlockedStage(), 1);
    await store.unlockThrough(3);
    expect(await store.loadUnlockedStage(), 3);
    await store.unlockThrough(2);
    expect(await store.loadUnlockedStage(), 3);

    SharedPreferences.setMockInitialValues({
      StageProgressStore.preferenceKey: 99,
    });
    expect(await store.loadUnlockedStage(), 1);
    SharedPreferences.setMockInitialValues({
      StageProgressStore.preferenceKey: 0,
    });
    expect(await store.loadUnlockedStage(), 1);
    SharedPreferences.setMockInitialValues({
      StageProgressStore.preferenceKey: 'invalid',
    });
    expect(await store.loadUnlockedStage(), 1);
  });

  testWidgets('stage picker only starts unlocked stages', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT STAGE'));
    await tester.pumpAndSettle();

    final lockedStage = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('stage-option-2')),
    );
    expect(lockedStage.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('stage-option-2')));
    await tester.pump();
    expect(find.text('SELECT STAGE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stage-option-1')));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.textContaining('STAGE 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'collecting target gems unlocks and advances stages exactly once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const testStages = [
        StageDefinition(
          number: 1,
          name: 'Test First',
          targetScore: 1,
          orbitCount: 2,
        ),
        StageDefinition(
          number: 2,
          name: 'Test Second',
          targetScore: 1,
          orbitCount: 3,
        ),
        StageDefinition(
          number: 3,
          name: 'Test Third',
          targetScore: 1,
          orbitCount: 4,
        ),
        StageDefinition(
          number: 4,
          name: 'Test Fourth',
          targetScore: 1,
          orbitCount: 5,
        ),
        StageDefinition(
          number: 5,
          name: 'Test Final',
          targetScore: 1,
          orbitCount: 5,
        ),
      ];
      final audio = _TestAudioController();
      await tester.pumpWidget(
        MaterialApp(
          home: OrbitGamePage(audioController: audio, stages: testStages),
        ),
      );
      await tester.tap(find.text('START RUN'));
      await tester.pump();
      await _tapOrbitLane(tester, 1, 2);
      for (var frame = 0; frame < 45; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('STAGE COMPLETE').evaluate().isNotEmpty) break;
      }
      expect(find.text('STAGE COMPLETE'), findsOneWidget);
      expect(
        audio.effects.where((effect) => effect == GameSoundEffect.gemCollect),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('STAGE COMPLETE'), findsOneWidget);
      expect(await StageProgressStore().loadUnlockedStage(), 2);

      for (var stageNumber = 2; stageNumber <= 5; stageNumber++) {
        await tester.tap(find.text('CONTINUE TO STAGE $stageNumber'));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('STAGE $stageNumber'), findsOneWidget);
        final orbitCounts = [2, 3, 4, 5, 5];
        await _completeTestStage(tester, orbitCounts[stageNumber - 1]);
        if (stageNumber < 5) {
          expect(find.text('STAGE COMPLETE'), findsOneWidget);
          expect(
            await StageProgressStore().loadUnlockedStage(),
            stageNumber + 1,
          );
        } else {
          expect(find.text('GAME COMPLETE'), findsOneWidget);
          expect(await StageProgressStore().loadUnlockedStage(), 5);
        }
      }
      expect(
        audio.effects.where((effect) => effect == GameSoundEffect.gemCollect),
        hasLength(5),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('GAME COMPLETE'), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      await tester.tap(find.text('PLAY AGAIN'));
      await tester.pump();
      expect(find.textContaining('STAGE 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('score')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
      expect(geometry.innerRadius, closeTo(360 * .34 * .72, .0001));
      expect(geometry.outerRadius, closeTo(360 * .34, .0001));
    });
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

  testWidgets(
    'unlocked five-orbit stage fits compact viewport and accepts direct orbit taps',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'orbit_dash_best': 12,
        StageProgressStore.preferenceKey: 4,
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        OrbitDashApp(audioController: _TestAudioController()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SELECT STAGE'));
      await tester.pumpAndSettle();

      expect(find.text('LOCKED'), findsOneWidget);
      await tester.ensureVisible(find.text('4. Cosmic Trial'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stage-option-4')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('current-stage')), findsOneWidget);
      expect(find.textContaining('STAGE 4'), findsOneWidget);
      final paintRect = tester.getRect(
        find.byKey(const ValueKey('orbit-lane-0')),
      );
      final geometry = OrbitGeometry.forSizeAndCount(
        paintRect.size,
        orbitCount: 5,
      );
      final target =
          paintRect.topLeft + geometry.center + Offset(geometry.outerRadius, 0);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('game-area')))
            .contains(target),
        isTrue,
      );
      await tester.tapAt(target);
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-lane-4')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('audio controls and cues follow game state transitions', (
    tester,
  ) async {
    final audio = _TestAudioController();
    await tester.pumpWidget(OrbitDashApp(audioController: audio));
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

    for (var frame = 0; frame < 220; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('STAGE FAILED').evaluate().isNotEmpty) break;
    }
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
  const stages = [
    StageDefinition(
      number: 1,
      name: 'Shield Test',
      targetScore: 50,
      orbitCount: 2,
    ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: OrbitGamePage(
        audioController: _TestAudioController(),
        stages: stages,
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
  return driver;
}

OrbitDashApp _testApp() =>
    OrbitDashApp(audioController: _TestAudioController());

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

Future<void> _completeTestStage(WidgetTester tester, int orbitCount) async {
  if (orbitCount > 2) {
    await _tapOrbitLane(tester, orbitCount - 1, orbitCount);
  }
  await _tapOrbitLane(tester, 1, orbitCount);
  for (var frame = 0; frame < 45; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('STAGE COMPLETE').evaluate().isNotEmpty ||
        find.text('GAME COMPLETE').evaluate().isNotEmpty) {
      break;
    }
  }
}
