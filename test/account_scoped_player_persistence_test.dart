import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/daily_challenges.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/player_statistics.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const playerA = 'firebase-uid-A';
  const playerB = 'firebase-uid-B';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all player stores isolate A and B and restore A on return', () async {
    final walletA = GemWallet(playerId: playerA);
    final achievementsA = AchievementStore(playerId: playerA);
    final statisticsA = PlayerStatisticsStore(playerId: playerA);
    final challengesA = DailyChallengeStore(
      playerId: playerA,
      now: () => DateTime(2026, 10, 17),
    );
    final skinA = SkinStore(playerId: playerA);
    final appearanceA = AppearanceStore(playerId: playerA);
    await Future.wait([
      walletA.load(),
      achievementsA.load(),
      statisticsA.load(),
      challengesA.load(),
      skinA.load(),
      appearanceA.load(),
    ]);

    expect(walletA.balance, 0);
    expect(achievementsA.totalGems, 0);
    expect(statisticsA.runsStarted, 0);
    expect(challengesA.challenges.every((item) => item.progress == 0), isTrue);
    expect(skinA.selectedSkin, ShipSkinId.defaultSkin);

    await walletA.creditPickupOnce('a-pickup', 100);
    expect(await walletA.purchase(itemId: 'ship.emerald', price: 40), isTrue);
    for (var index = 0; index < 10; index++) {
      await achievementsA.recordGem();
    }
    await achievementsA.unlock(AchievementId.savedByShield);
    await statisticsA.recordRunStarted();
    await statisticsA.recordSurvivalRun(55, 3);
    await statisticsA.recordStageCompleted(2);
    final challengeA = challengesA.challenges.first;
    await challengesA.recordEvent(
      challengeA.definition.event,
      amount: challengeA.definition.goal,
    );
    await challengesA.claimReward(
      challengeA.definition.id,
      onGrant: (amount) => walletA.creditDailyRewardOnce(
        dateKey: challengesA.dateKey,
        challengeId: challengeA.definition.id,
        amount: amount,
      ),
    );
    expect(
      await skinA.select(
        ShipSkinId.emerald,
        ownedItemIds: walletA.purchasedItemIds,
      ),
      isTrue,
    );
    final ownedCosmetics = {'orbit.aurora', 'core.crimson', 'trail.solar'};
    await appearanceA.load(ownedItemIds: ownedCosmetics);
    await appearanceA.selectOrbit(
      OrbitSkinId.aurora,
      ownedItemIds: ownedCosmetics,
    );
    await appearanceA.selectCore(
      CoreSkinId.crimson,
      ownedItemIds: ownedCosmetics,
    );
    await appearanceA.selectTrail(
      TrailSkinId.solar,
      ownedItemIds: ownedCosmetics,
    );

    final walletB = GemWallet(playerId: playerB);
    final achievementsB = AchievementStore(playerId: playerB);
    final statisticsB = PlayerStatisticsStore(playerId: playerB);
    final challengesB = DailyChallengeStore(
      playerId: playerB,
      now: () => DateTime(2026, 10, 17),
    );
    final skinB = SkinStore(playerId: playerB);
    final appearanceB = AppearanceStore(playerId: playerB);
    await Future.wait([
      walletB.load(),
      achievementsB.load(),
      statisticsB.load(),
      challengesB.load(),
      skinB.load(),
      appearanceB.load(),
    ]);

    expect(walletB.balance, 0);
    expect(walletB.purchasedItemIds, isEmpty);
    expect(achievementsB.totalGems, 0);
    expect(achievementsB.isUnlocked(AchievementId.savedByShield), isFalse);
    expect(statisticsB.runsStarted, 0);
    expect(statisticsB.bestRun, 0);
    expect(statisticsB.completedStages, isEmpty);
    expect(challengesB.challenges.every((item) => item.progress == 0), isTrue);
    expect(challengesB.challenges.every((item) => !item.rewardClaimed), isTrue);
    expect(skinB.selectedSkin, ShipSkinId.defaultSkin);
    expect(appearanceB.selectedOrbit, OrbitSkinId.defaultOrbit);
    expect(appearanceB.selectedCore, CoreSkinId.defaultCore);
    expect(appearanceB.selectedTrail, TrailSkinId.classic);

    await walletB.creditPickupOnce('b-pickup', 25);
    await achievementsB.recordGem();
    await statisticsB.recordRunStarted();
    await challengesB.recordEvent(DailyChallengeEvent.runStarted);
    expect(
      await appearanceB.selectOrbit(
        OrbitSkinId.solar,
        ownedItemIds: {'orbit.solar'},
      ),
      isTrue,
    );

    final restoredWalletA = GemWallet(playerId: playerA);
    final restoredAchievementsA = AchievementStore(playerId: playerA);
    final restoredStatisticsA = PlayerStatisticsStore(playerId: playerA);
    final restoredChallengesA = DailyChallengeStore(
      playerId: playerA,
      now: () => DateTime(2026, 10, 17),
    );
    final restoredSkinA = SkinStore(playerId: playerA);
    final restoredAppearanceA = AppearanceStore(playerId: playerA);
    await Future.wait([
      restoredWalletA.load(),
      restoredAchievementsA.load(),
      restoredStatisticsA.load(),
      restoredChallengesA.load(),
      restoredSkinA.load(ownedItemIds: {'ship.emerald'}),
      restoredAppearanceA.load(ownedItemIds: ownedCosmetics),
    ]);

    expect(restoredWalletA.balance, 60 + challengeA.definition.gemReward);
    expect(restoredWalletA.owns('ship.emerald'), isTrue);
    expect(restoredAchievementsA.totalGems, 10);
    expect(
      restoredAchievementsA.isUnlocked(AchievementId.savedByShield),
      isTrue,
    );
    expect(restoredStatisticsA.runsStarted, 1);
    expect(restoredStatisticsA.bestRun, 55);
    expect(restoredStatisticsA.completedStages, contains(2));
    expect(
      restoredChallengesA.challenges
          .firstWhere((item) => item.definition.id == challengeA.definition.id)
          .rewardClaimed,
      isTrue,
    );
    expect(restoredSkinA.selectedSkin, ShipSkinId.emerald);
    expect(restoredAppearanceA.selectedOrbit, OrbitSkinId.aurora);
    expect(restoredAppearanceA.selectedCore, CoreSkinId.crimson);
    expect(restoredAppearanceA.selectedTrail, TrailSkinId.solar);

    final restoredWalletB = GemWallet(playerId: playerB);
    final restoredAchievementsB = AchievementStore(playerId: playerB);
    final restoredStatisticsB = PlayerStatisticsStore(playerId: playerB);
    final restoredChallengesB = DailyChallengeStore(
      playerId: playerB,
      now: () => DateTime(2026, 10, 17),
    );
    final restoredAppearanceB = AppearanceStore(playerId: playerB);
    await Future.wait([
      restoredWalletB.load(),
      restoredAchievementsB.load(),
      restoredStatisticsB.load(),
      restoredChallengesB.load(),
      restoredAppearanceB.load(ownedItemIds: {'orbit.solar'}),
    ]);
    expect(restoredWalletB.balance, 25);
    expect(restoredAchievementsB.totalGems, 1);
    expect(restoredStatisticsB.runsStarted, 1);
    expect(
      restoredChallengesB.challenges
          .firstWhere(
            (item) => item.definition.event == DailyChallengeEvent.runStarted,
          )
          .progress,
      1,
    );
    expect(restoredAppearanceB.selectedOrbit, OrbitSkinId.solar);
  });

  test(
    'unowned legacy keys are ignored instead of assigned to an account',
    () async {
      SharedPreferences.setMockInitialValues({
        GemWallet.stateKey: jsonEncode({
          'version': 2,
          'balance': 800,
          'dailyRewardDate': null,
          'dailyRewardIds': <String>[],
          'purchases': {'ship.supernova': 500},
        }),
        AchievementStore.totalGemsKey: 95,
        PlayerStatisticsStore.runsStartedKey: 25,
        SkinStore.selectedSkinKey: ShipSkinId.supernova.name,
        AppearanceStore.selectedOrbitKey: OrbitSkinId.radiant.name,
      });

      for (final playerId in [playerA, playerB]) {
        final wallet = GemWallet(playerId: playerId);
        final achievements = AchievementStore(playerId: playerId);
        final statistics = PlayerStatisticsStore(playerId: playerId);
        final skin = SkinStore(playerId: playerId);
        final appearance = AppearanceStore(playerId: playerId);
        await Future.wait([
          wallet.load(),
          achievements.load(),
          statistics.load(),
          skin.load(),
          appearance.load(),
        ]);
        expect(wallet.balance, 0);
        expect(wallet.purchasedItemIds, isEmpty);
        expect(achievements.totalGems, 0);
        expect(statistics.runsStarted, 0);
        expect(skin.selectedSkin, ShipSkinId.defaultSkin);
        expect(appearance.selectedOrbit, OrbitSkinId.defaultOrbit);
      }
    },
  );

  test(
    'a delayed old-account load can only write to its bound UID keys',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final delayedPreferences = Completer<SharedPreferences>();
      final walletA = GemWallet(
        playerId: playerA,
        loadPreferences: () => delayedPreferences.future,
      );
      final loadA = walletA.load();

      final walletB = GemWallet(playerId: playerB);
      await walletB.load();
      await walletB.creditPickupOnce('b', 30);

      delayedPreferences.complete(preferences);
      await loadA;
      await walletA.creditPickupOnce('a', 12);

      final restoredA = GemWallet(playerId: playerA);
      final restoredB = GemWallet(playerId: playerB);
      await Future.wait([restoredA.load(), restoredB.load()]);
      expect(restoredA.balance, 12);
      expect(restoredB.balance, 30);
      expect(
        preferences.getString(
          AccountScopedPreferences.keyFor(playerA, GemWallet.stateKey),
        ),
        isNotNull,
      );
      expect(
        preferences.getString(
          AccountScopedPreferences.keyFor(playerB, GemWallet.stateKey),
        ),
        isNotNull,
      );
    },
  );
}
