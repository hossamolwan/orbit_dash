import '../../player_models.dart';

/// Storage boundary for player data.
///
/// Implementations receive the UID resolved by the authenticated repository,
/// never a UID supplied by a screen. Missing documents are represented by
/// `null` from load methods. Implementations should translate backend errors into
/// [PlayerDataAccessException] and must not expose backend exception types.
abstract interface class PlayerDataSource {
  Future<PlayerProfile?> loadProfile(String uid);

  /// Creates [profile] only when its UID has no profile yet. Returns the
  /// existing profile unchanged when one is already present.
  Future<PlayerProfile> createProfileIfAbsent(PlayerProfile profile);

  /// Updates only the player's display name and photo URL. Implementations
  /// own update timestamps and preserve UID, creation time, and schema version.
  Future<PlayerProfile> updateProfile({
    required String uid,
    required String displayName,
    required String? photoUrl,
  });

  Future<PlayerProgress?> loadProgress(String uid);

  Future<PlayerInventory?> loadInventory(String uid);

  Future<PlayerSettings?> loadSettings(String uid);

  /// Writes player preferences only; it must not mutate progression,
  /// inventory ownership, economy, or rewards.
  Future<void> saveSettings(String uid, PlayerSettings settings);
}

/// Backend-neutral failure reported by a player data source.
///
/// Missing records should be returned as `null`, not reported as an access
/// failure. Storage adapters should preserve the underlying cause in logs if
/// needed while keeping backend-specific exception types out of this API.
class PlayerDataAccessException implements Exception {
  const PlayerDataAccessException(this.message);

  final String message;

  @override
  String toString() => 'PlayerDataAccessException: $message';
}

