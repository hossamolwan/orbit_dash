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

    expect(
      [data.getUint8(0), data.getUint8(1), data.getUint8(2)],
      [0x49, 0x44, 0x33],
    );
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
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    for (var frame = 0; frame < 220; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('GAME OVER').evaluate().isNotEmpty) break;
    }

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('FINAL SCORE'), findsOneWidget);
    expect(find.text('BEST FLIGHT'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('GAME OVER'), findsNothing);
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
      tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent,
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
      tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent,
      0,
    );
    expect(tester.getRect(find.text('RESUME')).bottom, lessThanOrEqualTo(568));
    expect(
      tester.getRect(find.text('RESTART RUN')).bottom,
      lessThanOrEqualTo(568),
    );
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
      if (find.text('GAME OVER').evaluate().isNotEmpty) break;
    }

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent,
      0,
    );
    for (final label in [
      'GAME OVER',
      'FINAL SCORE',
      'PLAY AGAIN',
      'MAIN MENU',
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$label is above screen');
      expect(
        rect.bottom,
        lessThanOrEqualTo(568),
        reason: '$label is below screen',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('taps switch orbits only inside the complete play area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final audio = _TestAudioController();
    await tester.pumpWidget(OrbitDashApp(audioController: audio));
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    final playArea = tester.getRect(find.byKey(const ValueKey('game-area')));
    final distantPoint = Offset(playArea.left + 8, playArea.top + 8);
    expect(find.byKey(const ValueKey('orbit-lane-0')), findsOneWidget);

    await tester.tapAt(distantPoint);
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-lane-1')), findsOneWidget);
    expect(
      audio.effects.where((effect) => effect == GameSoundEffect.orbitSwitch),
      hasLength(1),
    );

    await tester.tapAt(distantPoint);
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-lane-0')), findsOneWidget);
    expect(
      audio.effects.where((effect) => effect == GameSoundEffect.orbitSwitch),
      hasLength(2),
    );

    await tester.tapAt(Offset(playArea.center.dx, playArea.top - 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-lane-0')), findsOneWidget);
    expect(
      audio.effects.where((effect) => effect == GameSoundEffect.orbitSwitch),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    expect(audio.effects, contains(GameSoundEffect.orbitSwitch));
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
      if (find.text('GAME OVER').evaluate().isNotEmpty) break;
    }
    expect(audio.states, contains(AudioRunState.over));
    expect(audio.effects, contains(GameSoundEffect.gemCollect));
    expect(audio.effects, contains(GameSoundEffect.collision));

    await tester.tap(find.text('MAIN MENU'));
    await tester.pump();
    expect(find.text('READY, PILOT?'), findsOneWidget);
    expect(audio.states.last, AudioRunState.menu);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
