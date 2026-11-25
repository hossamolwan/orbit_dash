import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/local_data_preflight.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const playerA = 'preflight-account-a';
  const playerB = 'preflight-account-b';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('classifies missing domains independently', () async {
    final snapshot = await LocalDataPreflight(playerId: playerA).inspect();

    expect(snapshot.isComplete, isTrue);
    expect(snapshot.playerId, playerA);
    expect(snapshot.domains, hasLength(LocalDataDomain.values.length));
    expect(
      snapshot.domains.values.every(
        (result) => result.presence == LocalDataPresence.missing,
      ),
      isTrue,
    );
    expect(snapshot.legacy.presence, LocalDataPresence.missing);
  });

  test('valid default-valued persisted data is Present', () async {
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.keyFor(playerA, GemKeys.state): jsonEncode({
        'version': 2,
        'balance': 0,
        'dailyRewardDate': null,
        'dailyRewardIds': <String>[],
        'purchases': <String, int>{},
      }),
      AccountScopedPreferences.keyFor(playerA, StatsKeys.runsStarted): 0,
      AccountScopedPreferences.keyFor(playerA, SkinKeys.selected):
          ShipSkinId.defaultSkin.name,
      AccountScopedPreferences.keyFor(playerA, DailyKeys.state): jsonEncode({
        'date': '2026-11-25',
        'bonusGems': 0,
        'challenges': <String, Object?>{},
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final before = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };

    final snapshot = await LocalDataPreflight(playerId: playerA).inspect();
    final after = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };

    expect(
      snapshot.domains[LocalDataDomain.gemWallet]!.presence,
      LocalDataPresence.present,
    );
    expect(
      snapshot.domains[LocalDataDomain.statistics]!.presence,
      LocalDataPresence.present,
    );
    expect(
      snapshot.domains[LocalDataDomain.skin]!.presence,
      LocalDataPresence.present,
    );
    expect(
      snapshot.domains[LocalDataDomain.dailyChallenges]!.presence,
      LocalDataPresence.present,
    );
    expect(
      snapshot.domains[LocalDataDomain.achievements]!.presence,
      LocalDataPresence.missing,
    );
    expect(after, before);
  });

  test(
    'achievement, appearance, and best-score domains validate separately',
    () async {
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.keyFor(playerA, AchievementKeys.totalGems): 0,
        AccountScopedPreferences.keyFor(playerA, AchievementKeys.firstSteps):
            false,
        AccountScopedPreferences.keyFor(playerA, AppearanceKeys.orbit):
            OrbitSkinId.defaultOrbit.name,
        AccountScopedPreferences.keyFor(playerA, AppearanceKeys.core):
            CoreSkinId.defaultCore.name,
        AccountScopedPreferences.keyFor(playerA, AppearanceKeys.trail):
            TrailSkinId.classic.name,
        AccountScopedPreferences.keyFor(playerA, SurvivalKeys.best): 0,
      });

      final snapshot = await LocalDataPreflight(playerId: playerA).inspect();

      expect(
        snapshot.domains[LocalDataDomain.achievements]!.presence,
        LocalDataPresence.present,
      );
      expect(
        snapshot.domains[LocalDataDomain.appearance]!.presence,
        LocalDataPresence.present,
      );
      expect(snapshot.domains[LocalDataDomain.appearance]!.schemaVersion, 1);
      expect(
        snapshot.domains[LocalDataDomain.survivalBestScore]!.presence,
        LocalDataPresence.present,
      );
    },
  );

  test(
    'malformed and unsupported data is Invalid with safe metadata',
    () async {
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.keyFor(playerA, GemKeys.state): jsonEncode({
          'version': 99,
          'balance': 0,
          'purchases': <String, int>{},
        }),
        AccountScopedPreferences.keyFor(playerA, DailyKeys.state): '{broken',
        AccountScopedPreferences.keyFor(playerA, StatsKeys.runsStarted): 'zero',
      });

      final snapshot = await LocalDataPreflight(playerId: playerA).inspect();

      final wallet = snapshot.domains[LocalDataDomain.gemWallet]!;
      expect(wallet.presence, LocalDataPresence.invalid);
      expect(wallet.schemaVersion, 99);
      expect(wallet.issueCode, 'unsupportedVersion');
      expect(wallet.presentFields, [GemKeys.state]);
      expect(wallet.toString(), isNot(contains('balance')));
      expect(
        snapshot.domains[LocalDataDomain.dailyChallenges]!.presence,
        LocalDataPresence.invalid,
      );
      expect(
        snapshot.domains[LocalDataDomain.statistics]!.presence,
        LocalDataPresence.invalid,
      );
    },
  );

  test(
    'partial wallet and statistics data do not hide missing domains',
    () async {
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.keyFor(playerA, GemKeys.state): jsonEncode({
          'version': 2,
          'balance': 12,
          'dailyRewardDate': null,
          'dailyRewardIds': <String>[],
          'purchases': <String, int>{},
        }),
        AccountScopedPreferences.keyFor(playerA, StatsKeys.runsStarted): 3,
      });

      final snapshot = await LocalDataPreflight(playerId: playerA).inspect();

      expect(
        snapshot.domains[LocalDataDomain.gemWallet]!.presence,
        LocalDataPresence.present,
      );
      expect(
        snapshot.domains[LocalDataDomain.statistics]!.presence,
        LocalDataPresence.present,
      );
      expect(
        snapshot.domains[LocalDataDomain.statistics]!.missingFields,
        contains(StatsKeys.bestRun),
      );
      expect(
        snapshot.domains[LocalDataDomain.appearance]!.presence,
        LocalDataPresence.missing,
      );
      expect(
        snapshot.domains[LocalDataDomain.skin]!.presence,
        LocalDataPresence.missing,
      );
    },
  );

  test('account A, B, then A inventories stay bound to their UIDs', () async {
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.keyFor(playerA, StatsKeys.runsStarted): 1,
      AccountScopedPreferences.keyFor(playerB, SkinKeys.selected):
          ShipSkinId.defaultSkin.name,
    });

    final firstA = await LocalDataPreflight(playerId: playerA).inspect();
    final inventoryB = await LocalDataPreflight(playerId: playerB).inspect();
    final returningA = await LocalDataPreflight(playerId: playerA).inspect();

    expect(firstA.playerId, playerA);
    expect(
      firstA.domains[LocalDataDomain.statistics]!.presence,
      LocalDataPresence.present,
    );
    expect(inventoryB.playerId, playerB);
    expect(
      inventoryB.domains[LocalDataDomain.statistics]!.presence,
      LocalDataPresence.missing,
    );
    expect(
      inventoryB.domains[LocalDataDomain.skin]!.presence,
      LocalDataPresence.present,
    );
    expect(returningA.playerId, playerA);
    expect(
      returningA.domains[LocalDataDomain.statistics]!.presence,
      LocalDataPresence.present,
    );
    expect(
      returningA.domains[LocalDataDomain.skin]!.presence,
      LocalDataPresence.missing,
    );
  });

  test('legacy keys are reported separately and never changed', () async {
    SharedPreferences.setMockInitialValues({
      GemKeys.state: jsonEncode({
        'version': 2,
        'balance': 40,
        'dailyRewardDate': null,
        'dailyRewardIds': <String>[],
        'purchases': <String, int>{},
      }),
      StatsKeys.runsStarted: 7,
      'orbit_dash_unlocked_stage': 3,
      'orbit_dash_best': 12,
      'orbit_dash_selected_skin_v1': ShipSkinId.defaultSkin.name,
      'orbit_dash_music_enabled': false,
    });
    final preferences = await SharedPreferences.getInstance();
    final before = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };

    final snapshot = await LocalDataPreflight(playerId: playerA).inspect();
    final after = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };

    expect(
      snapshot.domains[LocalDataDomain.gemWallet]!.presence,
      LocalDataPresence.missing,
    );
    expect(
      snapshot.domains[LocalDataDomain.statistics]!.presence,
      LocalDataPresence.missing,
    );
    expect(snapshot.legacy.presence, LocalDataPresence.present);
    expect(snapshot.legacy.detectedKeys, contains(GemKeys.state));
    expect(snapshot.legacy.detectedKeys, contains(StatsKeys.runsStarted));
    expect(snapshot.legacy.detectedKeys, contains('orbit_dash_unlocked_stage'));
    expect(snapshot.legacy.detectedKeys, contains('orbit_dash_best'));
    expect(
      snapshot.legacy.detectedKeys,
      contains('orbit_dash_selected_skin_v1'),
    );
    expect(
      snapshot.legacy.domains[LocalDataDomain.skin]!.presence,
      LocalDataPresence.present,
    );
    expect(after, before);
    expect(after.containsKey('orbit_dash_music_enabled'), isTrue);
    expect(
      snapshot.legacy.detectedKeys,
      isNot(contains('orbit_dash_music_enabled')),
    );
  });

  test(
    'a delayed inspection remains bound to the UID that started it',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final delayed = Completer<SharedPreferences>();
      final inspectionA = LocalDataPreflight(
        playerId: playerA,
        loadPreferences: () => delayed.future,
      ).inspect();
      final snapshotB = await LocalDataPreflight(playerId: playerB).inspect();
      delayed.complete(preferences);
      final snapshotA = await inspectionA;

      expect(snapshotB.playerId, playerB);
      expect(snapshotA.playerId, playerA);
    },
  );

  test(
    'preference read failure is incomplete and does not classify as missing',
    () async {
      final snapshot = await LocalDataPreflight(
        playerId: playerA,
        loadPreferences: () =>
            Future<SharedPreferences>.error(StateError('unavailable')),
      ).inspect();

      expect(snapshot.isComplete, isFalse);
      expect(snapshot.failureCode, 'preferencesUnavailable');
      expect(
        snapshot.domains.values.every(
          (result) => result.presence == LocalDataPresence.invalid,
        ),
        isTrue,
      );
    },
  );

  testWidgets('gameplay store loads wait until preflight completes', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final delayed = Completer<SharedPreferences>();
    final driver = OrbitGameTestDriver(
      preflightPreferencesLoader: () => delayed.future,
    );
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          audioController: _StubAudioController(),
          testDriver: driver,
        ),
      ),
    );

    expect(driver.preflightSnapshot, isNull);
    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('orbit_dash_player_v1_local_'),
      ),
      isEmpty,
    );

    delayed.complete(preferences);
    await tester.pump();
    await driver.flushProgress();

    expect(driver.preflightSnapshot!.isComplete, isTrue);
    expect(
      driver.preflightSnapshot!.playerId,
      AccountScopedPreferences.localPlayerId,
    );
    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('orbit_dash_player_v1_local_'),
      ),
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _StubAudioController extends GameAudioController {
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
  Future<void> shutdown() async => dispose();
}
