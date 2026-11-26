import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/authenticated_player_repository.dart';
import 'package:orbit_dash/data/player/player_data_result.dart';
import 'package:orbit_dash/data/player/player_data_source.dart';
import 'package:orbit_dash/data/player/player_sync_write.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';
import 'package:orbit_dash/player_sync_contracts.dart';

void main() {
  group('AuthenticatedPlayerRepository sync capability', () {
    test(
      'delegates contract and revision using the authenticated UID',
      () async {
        final source = _SyncSource();
        final repository = AuthenticatedPlayerRepository(
          _Identity('signed-in-player'),
          source,
        );
        final progress = PlayerSyncProgress.defaults();
        final inventory = PlayerSyncInventory.defaults();

        await repository.saveSyncProgress(
          progress: progress,
          expectedRevision: 3,
        );
        await repository.saveSyncInventory(
          inventory: inventory,
          expectedRevision: 8,
        );
        await repository.loadSyncProgress();
        await repository.loadSyncInventory();

        expect(source.calls.map((call) => call.$1), [
          'saveProgress',
          'saveInventory',
          'loadProgress',
          'loadInventory',
        ]);
        expect(
          source.calls.every((call) => call.$2 == 'signed-in-player'),
          isTrue,
        );
        expect(source.progress, progress);
        expect(source.inventory!.toMap(), inventory.toMap());
        expect(source.expectedRevisions, [3, 8]);
      },
    );

    test('construction without authenticated identity prevents access', () {
      final source = _SyncSource();
      expect(
        () => AuthenticatedPlayerRepository(_Identity(null), source),
        throwsA(isA<PlayerIdentityException>()),
      );
      expect(source.calls, isEmpty);
    });

    test('stale write errors propagate without false success', () async {
      final source = _SyncSource()
        ..writeError = const PlayerSyncWriteException(
          PlayerSyncWriteFailure.staleRevision,
        );
      final repository = AuthenticatedPlayerRepository(
        _Identity('player'),
        source,
      );

      await expectLater(
        repository.saveSyncProgress(
          progress: PlayerSyncProgress.defaults(),
          expectedRevision: 0,
        ),
        throwsA(
          isA<PlayerSyncWriteException>().having(
            (error) => error.failure,
            'failure',
            PlayerSyncWriteFailure.staleRevision,
          ),
        ),
      );
    });

    test('legacy read methods remain available', () async {
      final repository = AuthenticatedPlayerRepository(
        _Identity('player'),
        _SyncSource(),
      );
      expect((await repository.loadProgress()).isMissing, isTrue);
      expect((await repository.loadInventory()).isMissing, isTrue);
    });
  });
}

class _Identity implements PlayerIdentityService {
  _Identity(String? uid)
    : state = PlayerIdentitySnapshot(
        status: uid == null
            ? PlayerIdentityStatus.unauthenticated
            : PlayerIdentityStatus.authenticated,
        identity: uid == null ? null : PlayerIdentity(id: uid),
      );

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

class _SyncSource implements PlayerDataSource, PlayerSyncDataSource {
  final calls = <(String, String)>[];
  final expectedRevisions = <int>[];
  PlayerSyncProgress? progress;
  PlayerSyncInventory? inventory;
  PlayerSyncWriteException? writeError;

  @override
  Future<PlayerProfile?> loadProfile(String uid) async => null;

  @override
  Future<PlayerProfile> createProfileIfAbsent(PlayerProfile profile) async =>
      profile;

  @override
  Future<PlayerProfile> updateProfile({
    required String uid,
    required String displayName,
    required String? photoUrl,
  }) => throw UnimplementedError();

  @override
  Future<PlayerDataResult<PlayerProgress>> loadProgress(String uid) async =>
      const PlayerDataResult<PlayerProgress>.missing();

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory(String uid) async =>
      const PlayerDataResult<PlayerInventory>.missing();

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings(String uid) async =>
      const PlayerDataResult<PlayerSettings>.missing();

  @override
  Future<void> saveSettings(String uid, PlayerSettings settings) async {}

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncProgress>> loadSyncProgress(
    String uid,
  ) async {
    calls.add(('loadProgress', uid));
    return const PlayerSyncCloudSnapshot(revision: 2, value: null);
  }

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncInventory>> loadSyncInventory(
    String uid,
  ) async {
    calls.add(('loadInventory', uid));
    return const PlayerSyncCloudSnapshot(revision: 5, value: null);
  }

  @override
  Future<PlayerSyncWriteResult> saveSyncProgress({
    required String uid,
    required PlayerSyncProgress progress,
    required int expectedRevision,
  }) async {
    calls.add(('saveProgress', uid));
    expectedRevisions.add(expectedRevision);
    this.progress = progress;
    if (writeError case final error?) throw error;
    return PlayerSyncWriteResult(
      revision: expectedRevision + 1,
      didWrite: true,
    );
  }

  @override
  Future<PlayerSyncWriteResult> saveSyncInventory({
    required String uid,
    required PlayerSyncInventory inventory,
    required int expectedRevision,
  }) async {
    calls.add(('saveInventory', uid));
    expectedRevisions.add(expectedRevision);
    this.inventory = inventory;
    if (writeError case final error?) throw error;
    return PlayerSyncWriteResult(
      revision: expectedRevision + 1,
      didWrite: true,
    );
  }
}
