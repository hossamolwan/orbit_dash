/// Builds stable SharedPreferences keys for one authenticated player's data.
///
/// Older installations used unscoped keys. They are intentionally not read or
/// migrated because the previous account that owned them cannot be determined.
class AccountScopedPreferences {
  AccountScopedPreferences(String playerId) : playerId = _validate(playerId);

  /// `local` is reserved for isolated, unauthenticated/test callers.
  static const localPlayerId = 'local';

  final String playerId;

  String key(String legacyKey) =>
      'orbit_dash_player_v1_${Uri.encodeComponent(playerId)}_$legacyKey';

  static String keyFor(String playerId, String legacyKey) =>
      AccountScopedPreferences(playerId).key(legacyKey);

  static String localKey(String legacyKey) => keyFor(localPlayerId, legacyKey);

  static String _validate(String playerId) {
    if (playerId.trim().isEmpty) {
      throw ArgumentError.value(playerId, 'playerId', 'Must not be empty.');
    }
    return playerId;
  }
}
