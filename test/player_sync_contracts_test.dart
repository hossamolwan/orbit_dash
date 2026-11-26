import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/local_data_validation.dart';
import 'package:orbit_dash/player_statistics.dart';
import 'package:orbit_dash/player_sync_contracts.dart';
import 'package:orbit_dash/player_sync_mappers.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PlayerSyncProgress', () {
    test('round-trips canonical fields and distinguishes missing data', () {
      final defaults = PlayerSyncProgress.defaults();
      expect(
        PlayerSyncProgress.decode(exists: true, data: defaults.toMap()).status,
        PlayerSyncDataStatus.valid,
      );
      expect(
        PlayerSyncProgress.decode(exists: false).status,
        PlayerSyncDataStatus.missing,
      );
      expect(
        PlayerSyncProgress.decode(exists: true, data: defaults.toMap())
            .value
            ?.toMap(),
        defaults.toMap(),
      );
      expect(defaults.toMap().keys, {
        'schemaVersion',
        'highScore',
        'runsStarted',
        'losses',
        'shieldAbsorptions',
        'maxOrbit',
      });
    });

    test('reports malformed types, ranges, and schema as invalid', () {
      final defaults = PlayerSyncProgress.defaults().toMap();
      for (final invalid in [
        {...defaults, 'highScore': '12'},
        {...defaults, 'runsStarted': -1},
        {...defaults, 'losses': LocalDataValidation.maxPersistedCounter + 1},
        {...defaults, 'maxOrbit': 6},
        {...defaults, 'schemaVersion': 2},
        {...defaults, 'level': 1},
        'not a document',
      ]) {
        final result = PlayerSyncProgress.decode(exists: true, data: invalid);
        expect(result.status, PlayerSyncDataStatus.invalid);
        expect(result.issues, isNotEmpty);
      }
      expect(
        PlayerSyncProgress.decode(exists: false, data: defaults).status,
        PlayerSyncDataStatus.invalid,
      );
    });

    test('maps current local statistics and reconciles duplicate best scores',
        () async {
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.localKey(PlayerStatisticsStore.runsStartedKey):
            7,
        AccountScopedPreferences.localKey(PlayerStatisticsStore.lossesKey): 2,
        AccountScopedPreferences.localKey(
          PlayerStatisticsStore.shieldAbsorptionsKey,
        ): 3,
        AccountScopedPreferences.localKey(PlayerStatisticsStore.bestRunKey): 42,
        AccountScopedPreferences.localKey(PlayerStatisticsStore.maxOrbitKey): 4,
      });
      final preferences = await SharedPreferences.getInstance();
      final stats = PlayerStatisticsStore();
      await stats.load();
      final before = _snapshot(preferences);

      final progress = PlayerSyncMappers.progress(
        statistics: stats,
        survivalBestScore: 50,
      );

      expect(progress.highScore, 50);
      expect(progress.runsStarted, 7);
      expect(progress.losses, 2);
      expect(progress.shieldAbsorptions, 3);
      expect(progress.maxOrbit, 4);
      expect(progress.toMap().keys, isNot(contains('level')));
      expect(_snapshot(preferences), before);

      final otherBestWins = PlayerSyncMappers.progress(
        statistics: stats,
        survivalBestScore: 40,
      );
      expect(otherBestWins.highScore, 42);
    });

    test('requires local statistics to be loaded before mapping', () {
      expect(
        () => PlayerSyncMappers.progress(
          statistics: PlayerStatisticsStore(),
          survivalBestScore: 0,
        ),
        throwsStateError,
      );
    });
  });

  group('PlayerSyncInventory', () {
    test('round-trips defaults with four independently equipped slots', () {
      final defaults = PlayerSyncInventory.defaults();
      final decoded = PlayerSyncInventory.decode(
        exists: true,
        data: defaults.toMap(),
      );

      expect(decoded.status, PlayerSyncDataStatus.valid);
      expect(decoded.value, isNotNull);
      expect(decoded.value!.equipped.toMap().keys, {
        'ship',
        'orbit',
        'core',
        'trail',
      });
      expect(decoded.value!.ownedItemIds, PlayerSyncInventory.defaultItemIds);
      expect(
        PlayerSyncInventory.decode(exists: false).status,
        PlayerSyncDataStatus.missing,
      );
    });

    test('rejects unknown, duplicate, wrong-slot, and unowned item IDs', () {
      final defaults = PlayerSyncInventory.defaults().toMap();
      final equipped = Map<String, Object?>.from(
        defaults['equipped']! as Map,
      );

      final unknown = Map<String, Object?>.from(defaults)
        ..['ownedItemIds'] = [
          ...(defaults['ownedItemIds']! as List),
          'ship.notInCatalog',
        ];
      expect(
        PlayerSyncInventory.decode(exists: true, data: unknown).status,
        PlayerSyncDataStatus.invalid,
      );

      final duplicates = Map<String, Object?>.from(defaults)
        ..['ownedItemIds'] = [
          ...(defaults['ownedItemIds']! as List),
          'ship.defaultSkin',
        ];
      expect(
        PlayerSyncInventory.decode(exists: true, data: duplicates).issues,
        contains(
          isA<PlayerSyncValidationIssue>().having(
            (issue) => issue.message,
            'message',
            contains('Duplicate'),
          ),
        ),
      );

      final wrongSlot = {...equipped, 'ship': 'orbit.aurora'};
      final wrongSlotMap = Map<String, Object?>.from(defaults)
        ..['equipped'] = wrongSlot;
      expect(
        PlayerSyncInventory.decode(exists: true, data: wrongSlotMap).issues,
        contains(
          isA<PlayerSyncValidationIssue>().having(
            (issue) => issue.message,
            'message',
            contains('belongs to orbit'),
          ),
        ),
      );

      final unowned = Map<String, Object?>.from(defaults)
        ..['equipped'] = {...equipped, 'ship': 'ship.emerald'};
      expect(
        PlayerSyncInventory.decode(exists: true, data: unowned).issues,
        contains(
          isA<PlayerSyncValidationIssue>().having(
            (issue) => issue.message,
            'message',
            contains('not owned'),
          ),
        ),
      );
    });

    test('rejects malformed collections, slot types, and schema versions', () {
      final defaults = PlayerSyncInventory.defaults().toMap();
      final badOwned = Map<String, Object?>.from(defaults)
        ..['ownedItemIds'] = 'ship.defaultSkin';
      final badEquipped = Map<String, Object?>.from(defaults)
        ..['equipped'] = {'ship': false};
      final badVersion = Map<String, Object?>.from(defaults)
        ..['schemaVersion'] = 9;
      final unsupportedField = Map<String, Object?>.from(defaults)
        ..['walletBalance'] = 99;

      for (final value in [
        badOwned,
        badEquipped,
        badVersion,
        unsupportedField,
      ]) {
        final result = PlayerSyncInventory.decode(exists: true, data: value);
        expect(result.status, PlayerSyncDataStatus.invalid);
        expect(result.issues, isNotEmpty);
      }
    });

    test('maps local cosmetics read-only without exposing wallet state', () async {
      final walletKey = AccountScopedPreferences.localKey(GemWallet.stateKey);
      SharedPreferences.setMockInitialValues({
        walletKey: jsonEncode({
          'version': 3,
          'balance': 987,
          'dailyRewardLedger': [
            {
              'date': '2026-01-01',
              'ids': ['challenge'],
            },
          ],
          'purchases': {
            'ship.emerald': 40,
            'orbit.void': 300,
            'core.quantum': 1400,
            'trail.spectrum': 1400,
          },
        }),
        AccountScopedPreferences.localKey(SkinStore.selectedSkinKey): 'emerald',
        AccountScopedPreferences.localKey(AppearanceStore.selectedOrbitKey):
            OrbitSkinId.voidOrbit.name,
        AccountScopedPreferences.localKey(AppearanceStore.selectedCoreKey):
            CoreSkinId.quantum.name,
        AccountScopedPreferences.localKey(AppearanceStore.selectedTrailKey):
            TrailSkinId.spectrum.name,
      });
      final preferences = await SharedPreferences.getInstance();
      final wallet = GemWallet();
      await wallet.load();
      final ships = SkinStore();
      final appearances = AppearanceStore();
      await ships.load(ownedItemIds: wallet.purchasedItemIds);
      await appearances.load(ownedItemIds: wallet.purchasedItemIds);
      final before = _snapshot(preferences);

      final inventory = PlayerSyncMappers.inventory(
        wallet: wallet,
        shipStore: ships,
        appearanceStore: appearances,
      );
      final serialized = inventory.toMap();

      expect(inventory.equipped.ship, 'ship.emerald');
      expect(inventory.equipped.orbit, 'orbit.void');
      expect(inventory.equipped.core, 'core.quantum');
      expect(inventory.equipped.trail, 'trail.spectrum');
      expect(inventory.ownedItemIds, containsAll([
        'ship.emerald',
        'orbit.void',
        'core.quantum',
        'trail.spectrum',
      ]));
      expect(serialized.keys, {'schemaVersion', 'ownedItemIds', 'equipped'});
      expect(serialized, isNot(contains('balance')));
      expect(serialized, isNot(contains('purchases')));
      expect(serialized, isNot(contains('dailyRewardLedger')));
      expect(_snapshot(preferences), before);
      expect(wallet.balance, 987);
    });

    test('rejects unknown local ownership instead of dropping it', () async {
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.localKey(GemWallet.stateKey): jsonEncode({
          'version': 3,
          'balance': 3,
          'dailyRewardLedger': <Object?>[],
          'purchases': {'legacy.unknown': 3},
        }),
      });
      final wallet = GemWallet();
      await wallet.load();
      final ships = SkinStore();
      final appearances = AppearanceStore();
      await ships.load(ownedItemIds: wallet.purchasedItemIds);
      await appearances.load(ownedItemIds: wallet.purchasedItemIds);

      expect(
        () => PlayerSyncMappers.inventory(
          wallet: wallet,
          shipStore: ships,
          appearanceStore: appearances,
        ),
        throwsA(isA<PlayerSyncValidationException>()),
      );
      expect(wallet.owns('legacy.unknown'), isTrue);
    });

    test('requires source stores to be loaded before mapping', () {
      expect(
        () => PlayerSyncMappers.inventory(
          wallet: GemWallet(),
          shipStore: SkinStore(),
          appearanceStore: AppearanceStore(),
        ),
        throwsStateError,
      );
    });
  });
}

Map<String, Object?> _snapshot(SharedPreferences preferences) => {
  for (final key in preferences.getKeys()) key: preferences.get(key),
};
