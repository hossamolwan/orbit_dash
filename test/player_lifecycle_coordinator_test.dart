import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/player_lifecycle_coordinator.dart';
import 'package:orbit_dash/data/player/player_data_result.dart';
import 'package:orbit_dash/data/player/player_repository.dart';
import 'package:orbit_dash/data/player/player_sync_write.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';
import 'package:orbit_dash/player_sync_contracts.dart';

void main() {
  group('PlayerLifecycleCoordinator', () {
    test(
      'initializes identity and publishes an existing complete session',
      () async {
        final identity = _FakeIdentityService(_authenticated('player-a'));
        final repository = _FakePlayerRepository(
          profile: _profile('player-a'),
          progress: const PlayerProgress(level: 4, xp: 12),
          inventory: PlayerInventory(ownedSkinIds: {'nebula'}),
          settings: const PlayerSettings(musicEnabled: false),
        );
        final harness = _Harness(identity, repository);

        await harness.coordinator.start();

        expect(identity.initializeCalls, 1);
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        final session = harness.coordinator.state.session!;
        expect(session.identity.id, 'player-a');
        expect(session.profile, _profile('player-a'));
        expect(session.progress.isPresent, isTrue);
        expect(
          session.progress.requireValue,
          const PlayerProgress(level: 4, xp: 12),
        );
        expect(session.inventory.isPresent, isTrue);
        expect(session.inventory.requireValue.ownedSkinIds, {'nebula'});
        expect(session.settings.isPresent, isTrue);
        expect(
          session.settings.requireValue,
          const PlayerSettings(musicEnabled: false),
        );
        expect(repository.ensureProfileCalls, 0);
        await harness.dispose();
      },
    );

    test('unauthenticated identity does not construct a repository', () async {
      final identity = _FakeIdentityService(
        const PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.unauthenticated,
        ),
      );
      final harness = _Harness(identity, _FakePlayerRepository());

      await harness.coordinator.start();

      expect(
        harness.coordinator.state.phase,
        PlayerLifecyclePhase.unauthenticated,
      );
      expect(harness.repositoryFactoryCalls, 0);
      await harness.dispose();
    });

    test(
      'uses the profile returned by the create-if-absent contract',
      () async {
        final repository = _FakePlayerRepository(
          createdProfile: _profile('player-a', name: 'Existing server profile'),
        );
        final harness = _Harness(
          _FakeIdentityService(
            _authenticated('player-a', name: 'Seeded Pilot'),
          ),
          repository,
        );
        final phases = <PlayerLifecyclePhase>[];
        final subscription = harness.coordinator.states.listen(
          (state) => phases.add(state.phase),
        );

        await harness.coordinator.start();

        expect(repository.ensureProfileCalls, 1);
        expect(
          harness.coordinator.state.session!.profile.displayName,
          'Existing server profile',
        );
        expect(phases, contains(PlayerLifecyclePhase.creatingProfile));
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        await subscription.cancel();
        await harness.dispose();
      },
    );

    test('snapshot preserves missing optional documents', () async {
      final harness = _Harness(
        _FakeIdentityService(_authenticated('player-a')),
        _FakePlayerRepository(profile: _profile('player-a')),
      );

      await harness.coordinator.start();

      final session = harness.coordinator.state.session!;
      expect(session.progress.isMissing, isTrue);
      expect(session.progress.value, isNull);
      expect(session.inventory.isMissing, isTrue);
      expect(session.inventory.value, isNull);
      expect(session.settings.isMissing, isTrue);
      expect(session.settings.value, isNull);
      await harness.dispose();
    });

    test('snapshot preserves present documents containing defaults', () async {
      final repository = _FakePlayerRepository(
        profile: _profile('player-a'),
        progressResult: const PlayerDataResult<PlayerProgress>.present(
          PlayerProgress(),
        ),
        inventoryResult: PlayerDataResult<PlayerInventory>.present(
          PlayerInventory(),
        ),
        settingsResult: const PlayerDataResult<PlayerSettings>.present(
          PlayerSettings(),
        ),
      );
      final harness = _Harness(
        _FakeIdentityService(_authenticated('player-a')),
        repository,
      );

      await harness.coordinator.start();

      final session = harness.coordinator.state.session!;
      expect(session.progress.isPresent, isTrue);
      expect(session.progress.requireValue, const PlayerProgress());
      expect(session.inventory.isPresent, isTrue);
      expect(session.inventory.requireValue.ownedItemIds, isEmpty);
      expect(session.settings.isPresent, isTrue);
      expect(session.settings.requireValue, const PlayerSettings());
      await harness.dispose();
    });

    test(
      'profile loading failure is exposed and retry repeats profile load',
      () async {
        final repository = _FakePlayerRepository()
          ..profileError = StateError('profile unavailable');
        final harness = _Harness(
          _FakeIdentityService(_authenticated('a')),
          repository,
        );

        await harness.coordinator.start();
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.failed);
        expect(
          harness.coordinator.state.failure!.stage,
          PlayerLifecycleStage.profileLoad,
        );
        expect(harness.coordinator.state.failure!.isRetryable, isTrue);
        expect(harness.coordinator.state.failure!.error, isA<StateError>());

        repository.profileError = null;
        await harness.coordinator.retry();
        expect(repository.loadProfileCalls, 2);
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        await harness.dispose();
      },
    );

    test(
      'profile creation failure retries creation without reloading profile',
      () async {
        final repository = _FakePlayerRepository()
          ..createProfileError = StateError('create failed');
        final harness = _Harness(
          _FakeIdentityService(_authenticated('a')),
          repository,
        );

        await harness.coordinator.start();
        expect(
          harness.coordinator.state.failure!.stage,
          PlayerLifecycleStage.profileCreation,
        );
        repository.createProfileError = null;
        await harness.coordinator.retry();

        expect(repository.loadProfileCalls, 1);
        expect(repository.ensureProfileCalls, 2);
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        await harness.dispose();
      },
    );

    for (final domain in ['progress', 'inventory', 'settings']) {
      test(
        '$domain failure is stage-aware and retry preserves successful loads',
        () async {
          final repository = _FakePlayerRepository(profile: _profile('a'));
          repository.failOnceFor = domain;
          final harness = _Harness(
            _FakeIdentityService(_authenticated('a')),
            repository,
          );

          await harness.coordinator.start();
          expect(harness.coordinator.state.failure!.stage, switch (domain) {
            'progress' => PlayerLifecycleStage.progressLoad,
            'inventory' => PlayerLifecycleStage.inventoryLoad,
            _ => PlayerLifecycleStage.settingsLoad,
          });

          await harness.coordinator.retry();
          expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
          expect(repository.loadProfileCalls, 1);
          expect(repository.ensureProfileCalls, 0);
          if (domain != 'progress') expect(repository.loadProgressCalls, 1);
          if (domain == 'settings') expect(repository.loadInventoryCalls, 1);
          await harness.dispose();
        },
      );
    }

    test('repository construction failure can be retried', () async {
      final repository = _FakePlayerRepository();
      final identity = _FakeIdentityService(_authenticated('a'));
      var fail = true;
      final harness = _Harness.custom(identity, (service) async {
        if (fail) throw StateError('repository unavailable');
        return repository;
      });

      await harness.coordinator.start();
      expect(
        harness.coordinator.state.failure!.stage,
        PlayerLifecycleStage.repositoryCreation,
      );
      fail = false;
      await harness.coordinator.retry();
      expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
      await harness.dispose();
    });

    test('identity initialization failure is not retried through a memoized future', () async {
      final identity = _FakeIdentityService(_authenticated('a'))
        ..initializeError = StateError('identity init failed');
      final harness = _Harness(identity, _FakePlayerRepository());

      await harness.coordinator.start();
      expect(
        harness.coordinator.state.failure!.stage,
        PlayerLifecycleStage.identityInitialization,
      );
      expect(harness.coordinator.state.failure!.isRetryable, isFalse);

      identity.initializeError = null;
      await harness.coordinator.retry();
      expect(identity.initializeCalls, 1);
      expect(harness.coordinator.state.phase, PlayerLifecyclePhase.failed);

      identity.emit(_authenticated('a'));
      await _until(
        harness.coordinator,
        (state) => state.phase == PlayerLifecyclePhase.ready,
      );
      expect(harness.coordinator.state.session!.identity.id, 'a');
      await harness.dispose();
    });

    test(
      'unavailable identity state remains monitored but is not retryable',
      () async {
        final identity = _FakeIdentityService(
          const PlayerIdentitySnapshot(
            status: PlayerIdentityStatus.unavailable,
            failureCode: PlayerIdentityFailureCode.unavailable,
          ),
        );
        final harness = _Harness(identity, _FakePlayerRepository());

        await harness.coordinator.start();
        expect(
          harness.coordinator.state.failure!.stage,
          PlayerLifecycleStage.identityInitialization,
        );
        expect(harness.coordinator.state.failure!.isRetryable, isFalse);
        await harness.coordinator.retry();
        expect(identity.initializeCalls, 1);

        identity.emit(_authenticated('a'));
        await _until(
          harness.coordinator,
          (state) => state.phase == PlayerLifecyclePhase.ready,
        );
        expect(harness.coordinator.state.session!.identity.id, 'a');
        await harness.dispose();
      },
    );

    test(
      'switching accounts invalidates pending results and stale failures',
      () async {
        final firstProfile = Completer<PlayerProfile?>();
        final repositoryA = _FakePlayerRepository()
          ..profileCompleter = firstProfile;
        final repositoryB = _FakePlayerRepository(profile: _profile('b'));
        final identity = _FakeIdentityService(_authenticated('a'));
        final created = <String>[];
        final harness = _Harness.custom(identity, (service) async {
          final uid = service.state.requireRecoverableIdentity().id;
          created.add(uid);
          return uid == 'a' ? repositoryA : repositoryB;
        });

        final initialStart = harness.coordinator.start();
        await repositoryA.profileLoadStarted.future;
        identity.emit(_authenticated('b'));
        await _until(
          harness.coordinator,
          (state) => state.phase == PlayerLifecyclePhase.ready,
        );
        expect(harness.coordinator.state.session!.identity.id, 'b');

        firstProfile.completeError(StateError('stale A failure'));
        await initialStart;
        await Future<void>.delayed(Duration.zero);
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        expect(harness.coordinator.state.session!.identity.id, 'b');
        expect(harness.coordinator.state.failure, isNull);
        expect(created, ['a', 'b']);
        await harness.dispose();
      },
    );

    test(
      'A to B to A creates distinct sessions and rejects the first A result',
      () async {
        final firstAProfile = Completer<PlayerProfile?>();
        final repositories = <String, _FakePlayerRepository>{
          'a1': _FakePlayerRepository()..profileCompleter = firstAProfile,
          'b': _FakePlayerRepository(profile: _profile('b')),
          'a2': _FakePlayerRepository(profile: _profile('a')),
        };
        final identity = _FakeIdentityService(_authenticated('a'));
        var aCount = 0;
        final harness = _Harness.custom(identity, (service) async {
          final uid = service.state.requireRecoverableIdentity().id;
          if (uid == 'a') aCount++;
          return uid == 'a'
              ? repositories[aCount == 1 ? 'a1' : 'a2']!
              : repositories['b']!;
        });

        final firstStart = harness.coordinator.start();
        await repositories['a1']!.profileLoadStarted.future;
        identity.emit(_authenticated('b'));
        await _until(
          harness.coordinator,
          (state) => state.session?.identity.id == 'b',
        );
        identity.emit(_authenticated('a'));
        await _until(
          harness.coordinator,
          (state) =>
              state.phase == PlayerLifecyclePhase.ready &&
              state.session?.identity.id == 'a',
        );
        firstAProfile.complete(_profile('a', name: 'old session'));
        await firstStart;
        await Future<void>.delayed(Duration.zero);

        expect(aCount, 2);
        expect(harness.coordinator.state.session!.profile.displayName, '');
        expect(harness.coordinator.state.phase, PlayerLifecyclePhase.ready);
        await harness.dispose();
      },
    );

    test(
      'concurrent start requests share initialization and hydration',
      () async {
        final identity = _FakeIdentityService(_authenticated('a'));
        final repository = _FakePlayerRepository();
        final harness = _Harness(identity, repository);

        await Future.wait([
          harness.coordinator.start(),
          harness.coordinator.start(),
        ]);

        expect(identity.initializeCalls, 1);
        expect(harness.repositoryFactoryCalls, 1);
        expect(repository.loadProfileCalls, 1);
        await harness.dispose();
      },
    );

    test('disposal prevents later publications and is idempotent', () async {
      final identity = _FakeIdentityService(_authenticated('a'));
      final harness = _Harness(identity, _FakePlayerRepository());
      await harness.coordinator.start();
      final received = <PlayerLifecycleState>[];
      final subscription = harness.coordinator.states.listen(received.add);

      await harness.coordinator.dispose();
      await harness.coordinator.dispose();
      identity.emit(_authenticated('b'));

      expect(harness.coordinator.state.phase, PlayerLifecyclePhase.disposed);
      expect(received, isEmpty);
      await subscription.cancel();
      expect(harness.coordinator.start, throwsStateError);
    });
  });
}

class _Harness {
  _Harness(this.identity, _FakePlayerRepository repository)
    : repository = repository {
    coordinator = PlayerLifecycleCoordinator(
      identityService: identity,
      repositoryFactory: (_) async {
        repositoryFactoryCalls++;
        return repository;
      },
    );
  }

  _Harness.custom(this.identity, PlayerRepositoryFactory factory)
    : repository = null {
    coordinator = PlayerLifecycleCoordinator(
      identityService: identity,
      repositoryFactory: (service) async {
        repositoryFactoryCalls++;
        return factory(service);
      },
    );
  }

  final _FakeIdentityService identity;
  final _FakePlayerRepository? repository;
  late final PlayerLifecycleCoordinator coordinator;
  int repositoryFactoryCalls = 0;

  Future<void> dispose() async {
    await coordinator.dispose();
    await identity.close();
  }
}

class _FakeIdentityService implements PlayerIdentityService {
  _FakeIdentityService(this.currentState);

  final StreamController<PlayerIdentitySnapshot> _changes =
      StreamController<PlayerIdentitySnapshot>.broadcast(sync: true);
  PlayerIdentitySnapshot currentState;
  Object? initializeError;
  int initializeCalls = 0;

  @override
  PlayerIdentitySnapshot get state => currentState;
  @override
  Stream<PlayerIdentitySnapshot> get states => _changes.stream;
  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (initializeError case final error?) throw error;
  }

  @override
  Future<PlayerIdentity> signInWithGoogle() => throw UnimplementedError();
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  void emit(PlayerIdentitySnapshot snapshot) {
    currentState = snapshot;
    _changes.add(snapshot);
  }

  Future<void> close() => _changes.close();
}

class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository({
    this.profile,
    this.createdProfile,
    this.progress,
    this.inventory,
    this.settings,
    this.progressResult,
    this.inventoryResult,
    this.settingsResult,
  });

  PlayerProfile? profile;
  final PlayerProfile? createdProfile;
  PlayerProgress? progress;
  PlayerInventory? inventory;
  PlayerSettings? settings;
  final PlayerDataResult<PlayerProgress>? progressResult;
  final PlayerDataResult<PlayerInventory>? inventoryResult;
  final PlayerDataResult<PlayerSettings>? settingsResult;
  Completer<PlayerProfile?>? profileCompleter;
  final Completer<void> profileLoadStarted = Completer<void>();
  Object? profileError;
  Object? createProfileError;
  String? failOnceFor;
  final Map<String, int> domainCalls = {};
  int loadProfileCalls = 0;
  int ensureProfileCalls = 0;

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncProgress>> loadSyncProgress() =>
      throw UnimplementedError();

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncInventory>> loadSyncInventory() =>
      throw UnimplementedError();

  @override
  Future<PlayerSyncWriteResult> saveSyncProgress({
    required PlayerSyncProgress progress,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<PlayerSyncWriteResult> saveSyncInventory({
    required PlayerSyncInventory inventory,
    required int expectedRevision,
  }) => throw UnimplementedError();

  int get loadProgressCalls => domainCalls['progress'] ?? 0;
  int get loadInventoryCalls => domainCalls['inventory'] ?? 0;
  int get loadSettingsCalls => domainCalls['settings'] ?? 0;

  @override
  Future<PlayerProfile?> loadProfile() async {
    loadProfileCalls++;
    if (!profileLoadStarted.isCompleted) profileLoadStarted.complete();
    if (profileCompleter case final completer?) return completer.future;
    if (profileError case final error?) throw error;
    return profile;
  }

  @override
  Future<PlayerProfile> ensureProfile() async {
    ensureProfileCalls++;
    if (createProfileError case final error?) throw error;
    return createdProfile ?? _profile('a');
  }

  @override
  Future<PlayerProfile> updateProfile({
    required String displayName,
    required String? photoUrl,
  }) => throw UnimplementedError();

  @override
  Future<PlayerDataResult<PlayerProgress>> loadProgress() async {
    await _countAndMaybeFail('progress');
    return progressResult ??
        (progress == null
            ? const PlayerDataResult<PlayerProgress>.missing()
            : PlayerDataResult<PlayerProgress>.present(progress!));
  }

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory() async {
    await _countAndMaybeFail('inventory');
    return inventoryResult ??
        (inventory == null
            ? const PlayerDataResult<PlayerInventory>.missing()
            : PlayerDataResult<PlayerInventory>.present(inventory!));
  }

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings() async {
    await _countAndMaybeFail('settings');
    return settingsResult ??
        (settings == null
            ? const PlayerDataResult<PlayerSettings>.missing()
            : PlayerDataResult<PlayerSettings>.present(settings!));
  }

  @override
  Future<void> saveSettings(PlayerSettings settings) =>
      throw UnimplementedError();

  Future<void> _countAndMaybeFail(String domain) async {
    domainCalls[domain] = (domainCalls[domain] ?? 0) + 1;
    if (failOnceFor == domain) {
      failOnceFor = null;
      throw StateError('$domain failed');
    }
  }
}

Future<void> _until(
  PlayerLifecycleCoordinator coordinator,
  bool Function(PlayerLifecycleState state) predicate,
) async {
  if (predicate(coordinator.state)) return;
  final completer = Completer<void>();
  final subscription = coordinator.states.listen((state) {
    if (!completer.isCompleted && predicate(state)) completer.complete();
  });
  if (predicate(coordinator.state) && !completer.isCompleted) {
    completer.complete();
  }
  try {
    await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    await subscription.cancel();
  }
}

PlayerIdentitySnapshot _authenticated(String uid, {String? name}) =>
    PlayerIdentitySnapshot(
      status: PlayerIdentityStatus.authenticated,
      identity: PlayerIdentity(id: uid, displayName: name),
    );

PlayerProfile _profile(String uid, {String name = ''}) {
  final date = DateTime.utc(2025);
  return PlayerProfile(
    uid: uid,
    displayName: name,
    createdAt: date,
    updatedAt: date,
  );
}
