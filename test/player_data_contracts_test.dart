import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/authenticated_player_repository.dart';
import 'package:orbit_dash/data/player/player_data_source.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';

void main() {
  group('AuthenticatedPlayerRepository', () {
    test('scopes reads and writes to the authenticated identity', () async {
      final source = _FakePlayerDataSource();
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'authenticated-uid'),
          ),
        ),
        source,
      );

      await repository.loadProfile();
      expect(source.lastUid, 'authenticated-uid');

      final created = await repository.ensureProfile(
        displayName: 'Pilot',
        photoUrl: 'https://example.test/pilot.png',
      );
      expect(created.uid, 'authenticated-uid');
      expect(created.displayName, 'Pilot');
      expect(created.photoUrl, 'https://example.test/pilot.png');
      expect(created.createdAt.isUtc, isTrue);
      expect(created.updatedAt, created.createdAt);

      await repository.updateProfile(
        displayName: 'New Pilot',
        photoUrl: null,
      );
      expect(source.lastUid, 'authenticated-uid');
      expect(source.lastDisplayName, 'New Pilot');
      expect(source.lastPhotoUrl, isNull);

      await repository.updateProfile(
        displayName: 'Pilot Again',
        photoUrl: 'https://example.test/updated.png',
      );
      expect(source.lastDisplayName, 'Pilot Again');
      expect(source.lastPhotoUrl, 'https://example.test/updated.png');

      await repository.saveSettings(const PlayerSettings(musicEnabled: false));
      expect(source.lastUid, 'authenticated-uid');
      expect(source.savedSettings, const PlayerSettings(musicEnabled: false));
    });

    test('does not access data without a recoverable authenticated identity', () {
      final source = _FakePlayerDataSource();
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.unauthenticated,
          ),
        ),
        source,
      );

      expect(repository.loadProgress(), throwsA(isA<PlayerIdentityException>()));
      expect(source.lastUid, isNull);
    });

    test('preserves backend-neutral data access failures', () async {
      final source = _FakePlayerDataSource()
        ..profileError = const PlayerDataAccessException('temporarily unavailable');
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'uid'),
          ),
        ),
        source,
      );

      await expectLater(
        repository.loadProfile(),
        throwsA(isA<PlayerDataAccessException>()),
      );
    });

    test('exposes missing data as null', () async {
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'uid'),
          ),
        ),
        _FakePlayerDataSource(),
      );

      expect(await repository.loadProfile(), isNull);
      expect(await repository.loadSettings(), isNull);
    });
  });
}

class _FakeIdentityService implements PlayerIdentityService {
  const _FakeIdentityService(this.state);

  @override
  final PlayerIdentitySnapshot state;

  @override
  Stream<PlayerIdentitySnapshot> get states => Stream.value(state);

  @override
  Future<void> initialize() async {}

  @override
  Future<PlayerIdentity> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
}

class _FakePlayerDataSource implements PlayerDataSource {
  String? lastUid;
  String? lastDisplayName;
  String? lastPhotoUrl;
  PlayerSettings? savedSettings;
  PlayerDataAccessException? profileError;

  @override
  Future<PlayerProfile?> loadProfile(String uid) async {
    lastUid = uid;
    if (profileError case final error?) throw error;
    return null;
  }

  @override
  Future<PlayerProfile> createProfileIfAbsent(PlayerProfile profile) async {
    lastUid = profile.uid;
    return profile;
  }

  @override
  Future<PlayerProfile> updateProfile({
    required String uid,
    required String displayName,
    required String? photoUrl,
  }) async {
    lastUid = uid;
    lastDisplayName = displayName;
    lastPhotoUrl = photoUrl;
    final now = DateTime.now().toUtc();
    return PlayerProfile(
      uid: uid,
      displayName: displayName,
      photoUrl: photoUrl,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<PlayerProgress?> loadProgress(String uid) async {
    lastUid = uid;
    return null;
  }

  @override
  Future<PlayerInventory?> loadInventory(String uid) async {
    lastUid = uid;
    return null;
  }

  @override
  Future<PlayerSettings?> loadSettings(String uid) async {
    lastUid = uid;
    return null;
  }

  @override
  Future<void> saveSettings(String uid, PlayerSettings settings) async {
    lastUid = uid;
    savedSettings = settings;
  }
}
