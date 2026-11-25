import '../../player_identity.dart';
import '../../player_models.dart';
import 'player_data_source.dart';
import 'player_data_result.dart';
import 'player_repository.dart';

/// Coordinates player data access using the UID from the authentication layer.
///
/// This class performs no persistence itself. It leaves storage behavior to
/// [PlayerDataSource], including the atomic create-if-absent operation.
class AuthenticatedPlayerRepository implements PlayerRepository {
  AuthenticatedPlayerRepository(
    PlayerIdentityService identityService,
    this._dataSource,
  ) : _identity = identityService.state.requireRecoverableIdentity();

  final PlayerIdentity _identity;
  final PlayerDataSource _dataSource;

  String get _uid => _identity.id;

  @override
  Future<PlayerProfile?> loadProfile() async => _dataSource.loadProfile(_uid);

  @override
  Future<PlayerProfile> ensureProfile() async {
    final now = DateTime.now().toUtc();
    return _dataSource.createProfileIfAbsent(
      PlayerProfile(
        uid: _uid,
        displayName: _identity.displayName ?? '',
        photoUrl: _identity.photoUrl,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<PlayerProfile> updateProfile({
    required String displayName,
    required String? photoUrl,
  }) async => _dataSource.updateProfile(
    uid: _uid,
    displayName: displayName,
    photoUrl: photoUrl,
  );

  @override
  Future<PlayerDataResult<PlayerProgress>> loadProgress() async =>
      _dataSource.loadProgress(_uid);

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory() async =>
      _dataSource.loadInventory(_uid);

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings() async =>
      _dataSource.loadSettings(_uid);

  @override
  Future<void> saveSettings(PlayerSettings settings) async =>
      _dataSource.saveSettings(_uid, settings);
}
