import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/player_statistics.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('gem wallet and skin catalog', () {
    test(
      'pickup deduplication stays in memory and does not grow saved state',
      () async {
        final wallet = GemWallet();
        await wallet.load();
        for (var index = 0; index < 100; index++) {
          expect(await wallet.creditPickupOnce('pickup:$index', 1), isTrue);
        }
        expect(await wallet.creditPickupOnce('pickup:99', 1), isFalse);
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(
          prefs.getString(GemWallet.stateKey)!,
        ) as Map<String, dynamic>;
        expect(saved['balance'], 100);
        expect(saved['dailyRewardIds'], isEmpty);
        expect(saved.containsKey('grants'), isFalse);
        expect(
          prefs.getString(GemWallet.stateKey)!.contains('pickup:'),
          isFalse,
        );
      },
    );

    test(
      'upgrades an existing ledger while keeping only daily reward IDs',
      () async {
        SharedPreferences.setMockInitialValues({
          GemWallet.stateKey: jsonEncode({
            'version': 1,
            'balance': 17,
            'grants': [
              'pickup:old-run:1',
              'daily:2026-10-17:collect_gems',
              'daily:2026-10-16:start_runs',
            ],
            'purchases': {'ship.emerald': 25},
          }),
        });
        final wallet = GemWallet();
        await wallet.load();
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(
          prefs.getString(GemWallet.stateKey)!,
        ) as Map<String, dynamic>;
        expect(wallet.balance, 17);
        expect(wallet.owns('ship.emerald'), isTrue);
        expect(saved['version'], 2);
        expect(saved['dailyRewardIds'], ['collect_gems']);
        expect(
          prefs.getString(GemWallet.stateKey)!.contains('pickup:'),
          isFalse,
        );
      },
    );

    test('starts at zero and ignores legacy gems and skin unlocks', () async {
      SharedPreferences.setMockInitialValues({
        'orbit_dash_total_gems': 900,
        'orbit_dash_unlocked_skins_v1': ['emerald', 'supernova'],
        'orbit_dash_selected_skin_v1': 'supernova',
      });
      final wallet = GemWallet();
      await wallet.load();
      expect(wallet.balance, 0);
      final skins = SkinStore();
      await skins.load(ownedItemIds: wallet.purchasedItemIds);
      expect(skins.selectedSkin, ShipSkinId.defaultSkin);
      expect(wallet.purchasedItemIds, isEmpty);
    });

    test(
      'persists wallet balance and purchases across reinitialization',
      () async {
        final wallet = GemWallet();
        await wallet.load();
        expect(await wallet.creditPickupOnce('pickup:1', 300), isTrue);
        expect(await wallet.purchase(itemId: 'ship.solar', price: 250), isTrue);
        final restored = GemWallet();
        await restored.load();
        expect(restored.balance, 50);
        expect(restored.owns('ship.solar'), isTrue);
        expect(restored.balance, 50);
      },
    );

    test('rejects invalid, unaffordable and duplicate purchases', () async {
      final wallet = GemWallet();
      await wallet.load();
      expect(await wallet.creditPickupOnce('bad', -1), isFalse);
      expect(await wallet.purchase(itemId: 'ship.emerald', price: 40), isFalse);
      await wallet.creditPickupOnce('reward', 40);
      expect(await wallet.purchase(itemId: 'ship.emerald', price: 40), isTrue);
      expect(await wallet.purchase(itemId: 'ship.emerald', price: 40), isFalse);
      expect(wallet.balance, 0);
    });

    test(
      'purchase ledger supports standard and premium catalog entries',
      () async {
        expect(shipSkins.map((skin) => skin.price), [0, 40, 100, 250, 500]);
        expect(
          shipSkins
              .map((skin) => skin.price)
              .followedBy(orbitSkins.map((skin) => skin.price))
              .followedBy(coreSkins.map((skin) => skin.price))
              .where((price) => price > 0)
              .fold<int>(0, (total, price) => total + price),
          1600,
        );
        expect(shipSkins[1].rarity, CosmeticRarity.standard);
        expect(shipSkins[3].rarity, CosmeticRarity.premium);
        final wallet = GemWallet();
        await wallet.load();
        await wallet.creditPickupOnce('gift', 375);
        expect(
          await wallet.purchase(
            itemId: shipSkins[1].itemId,
            price: shipSkins[1].price,
          ),
          isTrue,
        );
        expect(
          await wallet.purchase(
            itemId: shipSkins[3].itemId,
            price: shipSkins[3].price,
          ),
          isTrue,
        );
        expect(wallet.balance, 85);
      },
    );

    test(
      'orbit and core catalogs have stable IDs, prices, rarity and defaults',
      () {
        expect(orbitSkins.map((skin) => skin.itemId), [
          'orbit.defaultOrbit',
          'orbit.aurora',
          'orbit.solar',
        ]);
        expect(orbitSkins.map((skin) => skin.price), [0, 60, 275]);
        expect(
          orbitSkins.every((skin) => skin.category == CosmeticCategory.orbit),
          isTrue,
        );
        expect(orbitSkins[1].rarity, CosmeticRarity.standard);
        expect(orbitSkins[2].rarity, CosmeticRarity.premium);
        expect(coreSkins.map((skin) => skin.itemId), [
          'core.defaultCore',
          'core.crimson',
          'core.glacier',
        ]);
        expect(coreSkins.map((skin) => skin.price), [0, 75, 300]);
        expect(
          coreSkins.every((skin) => skin.category == CosmeticCategory.core),
          isTrue,
        );
        expect(coreSkins[1].rarity, CosmeticRarity.standard);
        expect(coreSkins[2].rarity, CosmeticRarity.premium);
        expect(
          CosmeticCategory.values,
          containsAll([
            CosmeticCategory.ship,
            CosmeticCategory.orbit,
            CosmeticCategory.core,
          ]),
        );
      },
    );

    test(
      'orbit and core purchases and selections persist independently',
      () async {
        final wallet = GemWallet();
        await wallet.load();
        await wallet.creditPickupOnce('gift', 710);
        for (final skin in orbitSkins.skip(1)) {
          expect(
            await wallet.purchase(itemId: skin.itemId, price: skin.price),
            isTrue,
          );
        }
        for (final skin in coreSkins.skip(1)) {
          expect(
            await wallet.purchase(itemId: skin.itemId, price: skin.price),
            isTrue,
          );
        }
        expect(wallet.balance, 0);
        expect(
          await wallet.purchase(itemId: 'orbit.aurora', price: 60),
          isFalse,
        );

        final appearances = AppearanceStore();
        await appearances.load(ownedItemIds: wallet.purchasedItemIds);
        expect(
          await appearances.selectOrbit(
            OrbitSkinId.aurora,
            ownedItemIds: wallet.purchasedItemIds,
          ),
          isTrue,
        );
        expect(
          await appearances.selectCore(
            CoreSkinId.glacier,
            ownedItemIds: wallet.purchasedItemIds,
          ),
          isTrue,
        );
        final restoredWallet = GemWallet();
        await restoredWallet.load();
        final restored = AppearanceStore();
        await restored.load(ownedItemIds: restoredWallet.purchasedItemIds);
        expect(restored.selectedOrbit, OrbitSkinId.aurora);
        expect(restored.selectedCore, CoreSkinId.glacier);
        expect(restoredWallet.owns('orbit.aurora'), isTrue);
        expect(restoredWallet.owns('core.glacier'), isTrue);
        expect(restoredWallet.balance, 0);
      },
    );

    test(
      'invalid and unowned appearance selections fall back to defaults',
      () async {
        SharedPreferences.setMockInitialValues({
          AppearanceStore.selectedOrbitKey: 'solar',
          AppearanceStore.selectedCoreKey: 'unknown',
        });
        final appearances = AppearanceStore();
        await appearances.load();
        expect(appearances.selectedOrbit, OrbitSkinId.defaultOrbit);
        expect(appearances.selectedCore, CoreSkinId.defaultCore);

        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(AppearanceStore.selectedOrbitKey, 'aurora');
        await preferences.setString(AppearanceStore.selectedCoreKey, 'crimson');
        final unowned = AppearanceStore();
        await unowned.load(ownedItemIds: {'ship.solar'});
        expect(unowned.selectedOrbit, OrbitSkinId.defaultOrbit);
        expect(unowned.selectedCore, CoreSkinId.defaultCore);
        expect(
          await unowned.selectOrbit(OrbitSkinId.aurora, ownedItemIds: {}),
          isFalse,
        );
        expect(
          await unowned.selectCore(CoreSkinId.crimson, ownedItemIds: {}),
          isFalse,
        );
        expect(
          await unowned.selectOrbit(OrbitSkinId.defaultOrbit, ownedItemIds: {}),
          isTrue,
        );
        expect(
          await unowned.selectCore(CoreSkinId.defaultCore, ownedItemIds: {}),
          isTrue,
        );
      },
    );

    test('persists equipped skin and ignores legacy ownership keys', () async {
      final wallet = GemWallet();
      await wallet.load();
      await wallet.creditPickupOnce('gift', 40);
      await wallet.purchase(itemId: 'ship.emerald', price: 40);
      final skins = SkinStore();
      await skins.load(ownedItemIds: wallet.purchasedItemIds);
      expect(
        await skins.select(
          ShipSkinId.emerald,
          ownedItemIds: wallet.purchasedItemIds,
        ),
        isTrue,
      );
      final restored = SkinStore();
      await restored.load(ownedItemIds: wallet.purchasedItemIds);
      expect(restored.selectedSkin, ShipSkinId.emerald);
      expect(
        await restored.select(
          ShipSkinId.supernova,
          ownedItemIds: wallet.purchasedItemIds,
        ),
        isFalse,
      );
    });

    test(
      'malformed wallet data resets cleanly and lifetime stats stay separate',
      () async {
        SharedPreferences.setMockInitialValues({
          GemWallet.stateKey: '{broken',
          'orbit_dash_total_gems': 40,
        });
        final wallet = GemWallet();
        await wallet.load();
        expect(wallet.balance, 0);
        final achievement = AchievementStore();
        await achievement.load();
        expect(achievement.totalGems, 40);
        await wallet
            .purchase(itemId: 'ship.x', price: -1)
            .then((result) => expect(result, isFalse));
      },
    );

    test(
      'failed persistence never reports a pickup or purchase as successful',
      () async {
        final prefs = await SharedPreferences.getInstance();
        var fail = false;
        final wallet = GemWallet(
          loadPreferences: () async {
            if (fail) throw StateError('simulated persistence failure');
            return prefs;
          },
        );
        await wallet.load();
        fail = true;
        await expectLater(
          wallet.creditPickupOnce('pickup:failed', 1),
          throwsStateError,
        );
        await expectLater(
          wallet.purchase(itemId: 'ship.emerald', price: 1),
          throwsStateError,
        );
        expect(wallet.balance, 0);
        expect(wallet.owns('ship.emerald'), isFalse);
      },
    );
  });

  group('player statistics store', () {
    test('records counters and counts each completed stage once', () async {
      final store = PlayerStatisticsStore();
      await store.load(highestUnlockedStage: 1);
      await store.recordRunStarted();
      await store.recordRunStarted();
      await store.recordShieldAbsorption();
      await store.recordLoss();
      await store.recordStageCompleted(2);
      await store.recordStageCompleted(2);

      expect(store.runsStarted, 2);
      expect(store.shieldAbsorptions, 1);
      expect(store.losses, 1);
      expect(store.completedStages, {2});
      expect(store.distinctStagesCompleted, 1);
    });

    test(
      'migrates only stages before the unlocked stage and is repeatable',
      () async {
        SharedPreferences.setMockInitialValues({
          'orbit_dash_unlocked_stage': 4,
          PlayerStatisticsStore.completedStagesKey: ['2', 'invalid', '8'],
        });
        final first = PlayerStatisticsStore();
        await first.load(highestUnlockedStage: 4);
        expect(first.completedStages, {1, 2, 3});

        final restored = PlayerStatisticsStore();
        await restored.load(highestUnlockedStage: 4);
        expect(restored.completedStages, {1, 2, 3});
        expect(restored.distinctStagesCompleted, 3);
      },
    );

    test(
      'invalid counters do not prevent later progress from being saved',
      () async {
        SharedPreferences.setMockInitialValues({
          PlayerStatisticsStore.runsStartedKey: 'invalid',
          PlayerStatisticsStore.lossesKey: -10,
        });
        final store = PlayerStatisticsStore();
        await store.load(highestUnlockedStage: 1);
        expect(store.runsStarted, 0);
        expect(store.losses, 0);
        await store.recordRunStarted();
        expect(store.runsStarted, 1);
      },
    );
  });
}
