import 'gem_wallet.dart';
import 'player_statistics.dart';
import 'player_sync_contracts.dart';
import 'skins.dart';

/// Read-only projections from the existing local stores into sync contracts.
/// Wallet balances, purchases, reward ledgers, and payment data are never
/// returned by these mappers.
abstract final class PlayerSyncMappers {
  /// Maps current Survival statistics. The existing `_best` preference and
  /// `PlayerStatisticsStore.bestRun` are reconciled with max so neither source
  /// can lower the canonical sync high score.
  static PlayerSyncProgress progress({
    required PlayerStatisticsStore statistics,
    required int survivalBestScore,
  }) {
    if (!statistics.isLoaded) {
      throw StateError('Player statistics must be loaded before mapping.');
    }
    final highScore = statistics.bestRun >= survivalBestScore
        ? statistics.bestRun
        : survivalBestScore;
    return PlayerSyncProgress(
      highScore: highScore,
      runsStarted: statistics.runsStarted,
      losses: statistics.losses,
      shieldAbsorptions: statistics.shieldAbsorptions,
      maxOrbit: statistics.maxOrbit,
    );
  }

  /// Projects catalog-backed cosmetic ownership and equipped slots without
  /// changing wallet, preferences, or store state.
  static PlayerSyncInventory inventory({
    required GemWallet wallet,
    required SkinStore shipStore,
    required AppearanceStore appearanceStore,
  }) {
    if (!wallet.isLoaded || !shipStore.isLoaded || !appearanceStore.isLoaded) {
      throw StateError('Wallet and cosmetic stores must be loaded before mapping.');
    }
    final owned = <String>{
      ...wallet.purchasedItemIds,
      ...PlayerSyncInventory.defaultItemIds,
    };
    return PlayerSyncInventory(
      ownedItemIds: owned,
      equipped: PlayerSyncEquippedCosmetics(
        ship: shipSkins
            .firstWhere((item) => item.id == shipStore.selectedSkin)
            .itemId,
        orbit: appearanceStore.selectedOrbit.itemId,
        core: appearanceStore.selectedCore.itemId,
        trail: 'trail.${appearanceStore.selectedTrail.name}',
      ),
    );
  }
}
