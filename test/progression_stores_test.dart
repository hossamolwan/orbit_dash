import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/player_statistics.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('skin store', () {
    test(
      'unlocks skins from approved lifetime and stage requirements',
      () async {
        final store = SkinStore();
        await store.load(lifetimeGems: 24, completedStages: {1, 2});
        expect(store.unlockedSkins, {ShipSkinId.defaultSkin});

        await store.updateProgress(lifetimeGems: 25, completedStages: {1, 2});
        expect(store.isUnlocked(ShipSkinId.emerald), isTrue);
        expect(store.isUnlocked(ShipSkinId.nebula), isFalse);
        expect(store.isUnlocked(ShipSkinId.solar), isFalse);

        await store.updateProgress(
          lifetimeGems: 75,
          completedStages: {1, 2, 3},
        );
        expect(store.isUnlocked(ShipSkinId.nebula), isTrue);
        expect(store.isUnlocked(ShipSkinId.solar), isTrue);
        expect(store.isUnlocked(ShipSkinId.supernova), isFalse);

        await store.updateProgress(
          lifetimeGems: 75,
          completedStages: {1, 2, 3, 5},
        );
        expect(store.isUnlocked(ShipSkinId.supernova), isTrue);
      },
    );

    test(
      'persists selection and rejects locked or invalid selections',
      () async {
        final store = SkinStore();
        await store.load(lifetimeGems: 25, completedStages: {});
        expect(await store.select(ShipSkinId.nebula), isFalse);
        expect(await store.select(ShipSkinId.emerald), isTrue);

        final restored = SkinStore();
        await restored.load(lifetimeGems: 25, completedStages: {});
        expect(restored.selectedSkin, ShipSkinId.emerald);

        SharedPreferences.setMockInitialValues({
          SkinStore.unlockedSkinsKey: ['unknown'],
          SkinStore.selectedSkinKey: 'unknown',
        });
        final invalid = SkinStore();
        await invalid.load(lifetimeGems: 0, completedStages: {});
        expect(invalid.unlockedSkins, {ShipSkinId.defaultSkin});
        expect(invalid.selectedSkin, ShipSkinId.defaultSkin);
      },
    );

    test(
      'invalid preference types safely fall back to the default skin',
      () async {
        SharedPreferences.setMockInitialValues({
          SkinStore.unlockedSkinsKey: 7,
          SkinStore.selectedSkinKey: 7,
        });
        final store = SkinStore();
        await store.load(lifetimeGems: 0, completedStages: {});
        expect(store.unlockedSkins, {ShipSkinId.defaultSkin});
        expect(store.selectedSkin, ShipSkinId.defaultSkin);
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
