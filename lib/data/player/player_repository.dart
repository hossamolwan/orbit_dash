import '../../player_models.dart';

/// Repository boundary consumed by application features.
///
/// Calls are scoped to the currently authenticated player. No operation takes
/// a UID from its caller.
abstract interface class PlayerRepository {
  Future<PlayerProfile?> loadProfile();

  Future<PlayerProfile> ensureProfile();

  Future<PlayerProfile> updateProfile({
    required String displayName,
    required String? photoUrl,
  });

  Future<PlayerProgress?> loadProgress();

  Future<PlayerInventory?> loadInventory();

  Future<PlayerSettings?> loadSettings();

  Future<void> saveSettings(PlayerSettings settings);
}
