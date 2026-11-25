import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/authenticated_player_repository.dart';
import 'package:orbit_dash/data/player/player_data_source.dart';
import 'package:orbit_dash/data/player/player_data_result.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';

void main() {
  group('AuthenticatedPlayerRepository', () {
    test('scopes reads and writes to the authenticated identity', () async {
      final source = _FakePlayerDataSource();
      final identityService = _FakeIdentityService(
        const PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.authenticated,
          identity: PlayerIdentity(
            id: 'authenticated-uid',
            displayName: 'Pilot',
            photoUrl: 'https://example.test/pilot.png',
          ),
        ),
      );
      final repository = AuthenticatedPlayerRepository(identityService, source);

      await repository.loadProfile();
      expect(source.lastUid, 'authenticated-uid');

      final created = await repository.ensureProfile();
      expect(created.uid, 'authenticated-uid');
      expect(created.displayName, 'Pilot');
      expect(created.photoUrl, 'https://example.test/pilot.png');
      expect(created.createdAt.isUtc, isTrue);
      expect(created.updatedAt, created.createdAt);

      await repository.updateProfile(displayName: 'New Pilot', photoUrl: null);
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

    test(
      'rejects construction without a recoverable identity before data access',
      () {
        final source = _FakePlayerDataSource();
        expect(
          () => AuthenticatedPlayerRepository(
            _FakeIdentityService(
              const PlayerIdentitySnapshot(
                status: PlayerIdentityStatus.unauthenticated,
              ),
            ),
            source,
          ),
          throwsA(isA<PlayerIdentityException>()),
        );
        expect(source.lastUid, isNull);
      },
    );

    test(
      'repository remains bound to its creation identity after account switch',
      () async {
        final source = _FakePlayerDataSource();
        final identityService = _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'player-a', displayName: 'A'),
          ),
        );
        final repository = AuthenticatedPlayerRepository(
          identityService,
          source,
        );

        identityService.currentState = const PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.authenticated,
          identity: PlayerIdentity(id: 'player-b', displayName: 'B'),
        );
        await repository.loadProgress();
        expect(source.lastUid, 'player-a');
        final profile = await repository.ensureProfile();
        expect(profile.uid, 'player-a');
        expect(profile.displayName, 'A');
      },
    );

    test('profile seed preserves explicitly nullable photo URL', () async {
      final source = _FakePlayerDataSource();
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'uid', displayName: 'Pilot'),
          ),
        ),
        source,
      );

      final profile = await repository.ensureProfile();
      expect(profile.photoUrl, isNull);
      expect(source.createdProfile?.photoUrl, isNull);
    });

    test('preserves backend-neutral data access failures', () async {
      final source = _FakePlayerDataSource()
        ..profileError = const PlayerDataAccessException(
          'temporarily unavailable',
        );
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

    test(
      'preserves missing domain documents as explicit missing results',
      () async {
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
        expect((await repository.loadProgress()).isMissing, isTrue);
        expect((await repository.loadInventory()).isMissing, isTrue);
        expect((await repository.loadSettings()).isMissing, isTrue);
      },
    );

    test('preserves present domain documents with default values', () async {
      final source = _FakePlayerDataSource()
        ..progressResult = const PlayerDataResult<PlayerProgress>.present(
          PlayerProgress(),
        )
        ..inventoryResult = PlayerDataResult<PlayerInventory>.present(
          PlayerInventory(),
        )
        ..settingsResult = const PlayerDataResult<PlayerSettings>.present(
          PlayerSettings(),
        );
      final repository = AuthenticatedPlayerRepository(
        _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.authenticated,
            identity: PlayerIdentity(id: 'uid'),
          ),
        ),
        source,
      );

      final progress = await repository.loadProgress();
      final inventory = await repository.loadInventory();
      final settings = await repository.loadSettings();

      expect(progress.isPresent, isTrue);
      expect(progress.requireValue, const PlayerProgress());
      expect(inventory.isPresent, isTrue);
      expect(inventory.requireValue.ownedSkinIds, isEmpty);
      expect(inventory.requireValue.ownedItemIds, isEmpty);
      expect(settings.isPresent, isTrue);
      expect(settings.requireValue, const PlayerSettings());
      expect(source.lastUid, 'uid');
    });
  });
}

class _FakeIdentityService implements PlayerIdentityService {
  _FakeIdentityService(this.currentState);

  PlayerIdentitySnapshot currentState;

  @override
  PlayerIdentitySnapshot get state => currentState;

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
  PlayerProfile? createdProfile;
  PlayerDataAccessException? profileError;
  PlayerDataResult<PlayerProgress> progressResult =
      const PlayerDataResult<PlayerProgress>.missing();
  PlayerDataResult<PlayerInventory> inventoryResult =
      const PlayerDataResult<PlayerInventory>.missing();
  PlayerDataResult<PlayerSettings> settingsResult =
      const PlayerDataResult<PlayerSettings>.missing();

  @override
  Future<PlayerProfile?> loadProfile(String uid) async {
    lastUid = uid;
    if (profileError case final error?) throw error;
    return null;
  }

  @override
  Future<PlayerProfile> createProfileIfAbsent(PlayerProfile profile) async {
    lastUid = profile.uid;
    createdProfile = profile;
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
  Future<PlayerDataResult<PlayerProgress>> loadProgress(String uid) async {
    lastUid = uid;
    return progressResult;
  }

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory(String uid) async {
    lastUid = uid;
    return inventoryResult;
  }

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings(String uid) async {
    lastUid = uid;
    return settingsResult;
  }

  @override
  Future<void> saveSettings(String uid, PlayerSettings settings) async {
    lastUid = uid;
    savedSettings = settings;
  }
}
