import 'dart:async';

import '../../player_identity.dart';
import '../../player_models.dart';
import 'create_player_repository.dart';
import 'player_data_result.dart';
import 'player_repository.dart';

typedef PlayerRepositoryFactory = Future<PlayerRepository> Function(
  PlayerIdentityService identityService,
);

enum PlayerLifecyclePhase {
  initializingIdentity,
  unauthenticated,
  loadingProfile,
  creatingProfile,
  loadingPlayerData,
  ready,
  failed,
  disposed,
}

enum PlayerLifecycleStage {
  identityInitialization,
  repositoryCreation,
  profileLoad,
  profileCreation,
  progressLoad,
  inventoryLoad,
  settingsLoad,
}

enum PlayerLifecycleRetryOperation {
  createRepository,
  loadProfile,
  createProfile,
  loadProgress,
  loadInventory,
  loadSettings,
}

class PlayerLifecycleFailure {
  const PlayerLifecycleFailure({
    required this.stage,
    required this.error,
    required this.stackTrace,
    required this.retryOperation,
  });

  final PlayerLifecycleStage stage;
  final Object error;
  final StackTrace stackTrace;
  final PlayerLifecycleRetryOperation? retryOperation;

  bool get isRetryable => retryOperation != null;
}

class PlayerSessionSnapshot {
  const PlayerSessionSnapshot({
    required this.identity,
    required this.profile,
    required this.progress,
    required this.inventory,
    required this.settings,
  });

  final PlayerIdentity identity;
  final PlayerProfile profile;
  final PlayerDataResult<PlayerProgress> progress;
  final PlayerDataResult<PlayerInventory> inventory;
  final PlayerDataResult<PlayerSettings> settings;
}

class PlayerLifecycleState {
  const PlayerLifecycleState._({
    required this.phase,
    this.identity,
    this.session,
    this.failure,
  });

  const PlayerLifecycleState.initializingIdentity()
    : this._(phase: PlayerLifecyclePhase.initializingIdentity);
  const PlayerLifecycleState.unauthenticated()
    : this._(phase: PlayerLifecyclePhase.unauthenticated);
  const PlayerLifecycleState.disposed()
    : this._(phase: PlayerLifecyclePhase.disposed);

  final PlayerLifecyclePhase phase;
  final PlayerIdentity? identity;
  final PlayerSessionSnapshot? session;
  final PlayerLifecycleFailure? failure;
}

/// Owns player-session hydration while leaving identity and storage ownership
/// with their existing layers. A repository is created once per identity
/// snapshot and its results are published only while that session is current.
class PlayerLifecycleCoordinator {
  PlayerLifecycleCoordinator({
    required PlayerIdentityService identityService,
    PlayerRepositoryFactory? repositoryFactory,
  }) : _repositoryFactory =
           repositoryFactory ??
           ((service) => createPlayerRepository(identityService: service)) {
    _identityService = identityService;
  }

  late final PlayerIdentityService _identityService;
  final PlayerRepositoryFactory _repositoryFactory;
  final StreamController<PlayerLifecycleState> _states =
      StreamController<PlayerLifecycleState>.broadcast(sync: true);

  PlayerLifecycleState _state =
      const PlayerLifecycleState.initializingIdentity();
  PlayerLifecycleState get state => _state;
  Stream<PlayerLifecycleState> get states => _states.stream;

  StreamSubscription<PlayerIdentitySnapshot>? _identitySubscription;
  Future<void>? _startOperation;
  Future<void>? _retryOperation;
  _PlayerSession? _session;
  PlayerIdentitySnapshot? _observedSnapshot;
  int _generation = 0;
  bool _disposed = false;

  Future<void> start() {
    _ensureNotDisposed();
    return _startOperation ??= _start();
  }

  Future<void> _start() async {
    _publish(const PlayerLifecycleState.initializingIdentity());
    _identitySubscription = _identityService.states.listen(
      (snapshot) => unawaited(_handleIdentitySnapshot(snapshot)),
      onError: (Object error, StackTrace stackTrace) {
        _invalidateSession();
        _observedSnapshot = null;
        _publishFailure(
          stage: PlayerLifecycleStage.identityInitialization,
          error: error,
          stackTrace: stackTrace,
          retryOperation: null,
        );
      },
    );

    try {
      await _identityService.initialize();
    } catch (error, stackTrace) {
      _invalidateSession();
      _observedSnapshot = null;
      _publishFailure(
        stage: PlayerLifecycleStage.identityInitialization,
        error: error,
        stackTrace: stackTrace,
        retryOperation: null,
      );
      return;
    }

    await _handleIdentitySnapshot(_identityService.state);
  }

  Future<void> _handleIdentitySnapshot(PlayerIdentitySnapshot snapshot) async {
    if (_disposed) return;
    if (_sameSnapshot(_observedSnapshot, snapshot)) {
      final active = _session;
      if (active != null) await active.operation;
      return;
    }
    _observedSnapshot = snapshot;

    if (snapshot.hasRecoverableIdentity) {
      final identity = snapshot.requireRecoverableIdentity();
      final session = _PlayerSession(++_generation, identity);
      _session = session;
      _publish(
        PlayerLifecycleState._(
          phase: PlayerLifecyclePhase.loadingProfile,
          identity: identity,
        ),
      );
      session.operation = _resolveProfile(session);
      await session.operation;
      return;
    }

    _invalidateSession();
    if (snapshot.status == PlayerIdentityStatus.unauthenticated) {
      _publish(const PlayerLifecycleState.unauthenticated());
    } else if (snapshot.status == PlayerIdentityStatus.unavailable) {
      _publishFailure(
        stage: PlayerLifecycleStage.identityInitialization,
        error: const PlayerIdentityException(
          PlayerIdentityFailureCode.unavailable,
        ),
        stackTrace: StackTrace.current,
        retryOperation: null,
      );
    } else {
      _publish(const PlayerLifecycleState.initializingIdentity());
    }
  }

  Future<void> _resolveProfile(_PlayerSession session) async {
    if (!_isCurrent(session)) return;
    _publishSessionPhase(session, PlayerLifecyclePhase.loadingProfile);
    if (session.repository == null) {
      try {
        final repository = await _repositoryFactory(_identityService);
        if (!_isCurrent(session)) return;
        final currentIdentity = _identityService.state
            .requireRecoverableIdentity();
        if (currentIdentity.id != session.identity.id) return;
        session.repository = repository;
      } catch (error, stackTrace) {
        _failSession(
          session,
          PlayerLifecycleStage.repositoryCreation,
          PlayerLifecycleRetryOperation.createRepository,
          error,
          stackTrace,
        );
        return;
      }
    }

    try {
      final profile = await session.repository!.loadProfile();
      if (!_isCurrent(session)) return;
      if (profile != null) {
        _validateProfile(session, profile);
        session.profile = profile;
        await _loadPlayerData(session);
      } else {
        await _createProfile(session);
      }
    } catch (error, stackTrace) {
      _failSession(
        session,
        PlayerLifecycleStage.profileLoad,
        PlayerLifecycleRetryOperation.loadProfile,
        error,
        stackTrace,
      );
    }
  }

  Future<void> _createProfile(_PlayerSession session) async {
    if (!_isCurrent(session)) return;
    _publishSessionPhase(session, PlayerLifecyclePhase.creatingProfile);
    try {
      final profile = await session.repository!.ensureProfile();
      if (!_isCurrent(session)) return;
      _validateProfile(session, profile);
      session.profile = profile;
      await _loadPlayerData(session);
    } catch (error, stackTrace) {
      _failSession(
        session,
        PlayerLifecycleStage.profileCreation,
        PlayerLifecycleRetryOperation.createProfile,
        error,
        stackTrace,
      );
    }
  }

  Future<void> _loadPlayerData(_PlayerSession session) async {
    if (!_isCurrent(session)) return;
    _publishSessionPhase(session, PlayerLifecyclePhase.loadingPlayerData);

    if (!session.progressLoaded) {
      try {
        final result = await session.repository!.loadProgress();
        if (!_isCurrent(session)) return;
        session.progress = result;
        session.progressLoaded = true;
      } catch (error, stackTrace) {
        _failSession(
          session,
          PlayerLifecycleStage.progressLoad,
          PlayerLifecycleRetryOperation.loadProgress,
          error,
          stackTrace,
        );
        return;
      }
    }

    if (!session.inventoryLoaded) {
      try {
        final result = await session.repository!.loadInventory();
        if (!_isCurrent(session)) return;
        session.inventory = result;
        session.inventoryLoaded = true;
      } catch (error, stackTrace) {
        _failSession(
          session,
          PlayerLifecycleStage.inventoryLoad,
          PlayerLifecycleRetryOperation.loadInventory,
          error,
          stackTrace,
        );
        return;
      }
    }

    if (!session.settingsLoaded) {
      try {
        final result = await session.repository!.loadSettings();
        if (!_isCurrent(session)) return;
        session.settings = result;
        session.settingsLoaded = true;
      } catch (error, stackTrace) {
        _failSession(
          session,
          PlayerLifecycleStage.settingsLoad,
          PlayerLifecycleRetryOperation.loadSettings,
          error,
          stackTrace,
        );
        return;
      }
    }

    if (!_isCurrent(session)) return;
    final profile = session.profile;
    if (profile == null) return;
    _publish(
      PlayerLifecycleState._(
        phase: PlayerLifecyclePhase.ready,
        identity: session.identity,
        session: PlayerSessionSnapshot(
          identity: session.identity,
          profile: profile,
          progress: session.progress!,
          inventory: session.inventory!,
          settings: session.settings!,
        ),
      ),
    );
  }

  /// Retries only the operation recorded in the current failure.
  Future<void> retry() {
    _ensureNotDisposed();
    if (_retryOperation != null) return _retryOperation!;
    final failure = _state.failure;
    if (failure == null || !failure.isRetryable) return Future<void>.value();
    final operation = _retryFailure(failure);
    _retryOperation = operation.whenComplete(() => _retryOperation = null);
    return _retryOperation!;
  }

  Future<void> _retryFailure(PlayerLifecycleFailure failure) async {
    final session = _session;
    if (session == null || !_isCurrent(session)) return;
    switch (failure.retryOperation) {
      case PlayerLifecycleRetryOperation.createRepository:
        session.operation = _resolveProfile(session);
      case PlayerLifecycleRetryOperation.loadProfile:
        session.operation = _resolveProfile(session);
      case PlayerLifecycleRetryOperation.createProfile:
        session.operation = _createProfile(session);
      case PlayerLifecycleRetryOperation.loadProgress ||
          PlayerLifecycleRetryOperation.loadInventory ||
          PlayerLifecycleRetryOperation.loadSettings:
        session.operation = _loadPlayerData(session);
      case null:
        return;
    }
    await session.operation;
  }

  void _validateProfile(_PlayerSession session, PlayerProfile profile) {
    if (profile.uid != session.identity.id) {
      throw StateError('Loaded profile identity does not match the session.');
    }
  }

  void _publishSessionPhase(
    _PlayerSession session,
    PlayerLifecyclePhase phase,
  ) {
    if (!_isCurrent(session)) return;
    _publish(PlayerLifecycleState._(phase: phase, identity: session.identity));
  }

  void _failSession(
    _PlayerSession session,
    PlayerLifecycleStage stage,
    PlayerLifecycleRetryOperation retryOperation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_isCurrent(session)) return;
    _publishFailure(
      stage: stage,
      error: error,
      stackTrace: stackTrace,
      retryOperation: retryOperation,
      identity: session.identity,
    );
  }

  void _publishFailure({
    required PlayerLifecycleStage stage,
    required Object error,
    required StackTrace stackTrace,
    required PlayerLifecycleRetryOperation? retryOperation,
    PlayerIdentity? identity,
  }) {
    _publish(
      PlayerLifecycleState._(
        phase: PlayerLifecyclePhase.failed,
        identity: identity,
        failure: PlayerLifecycleFailure(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
          retryOperation: retryOperation,
        ),
      ),
    );
  }

  bool _isCurrent(_PlayerSession session) =>
      !_disposed &&
      identical(_session, session) &&
      session.generation == _generation &&
      _sameIdentity(_identityService.state.identity, session.identity);

  bool _sameIdentity(PlayerIdentity? first, PlayerIdentity? second) =>
      first?.id == second?.id &&
      first?.displayName == second?.displayName &&
      first?.photoUrl == second?.photoUrl;

  bool _sameSnapshot(
    PlayerIdentitySnapshot? first,
    PlayerIdentitySnapshot second,
  ) {
    if (first == null || first.status != second.status) return false;
    final firstIdentity = first.identity;
    final secondIdentity = second.identity;
    return _sameIdentity(firstIdentity, secondIdentity) &&
        first.failureCode == second.failureCode;
  }

  void _invalidateSession() {
    _generation++;
    _session = null;
  }

  void _publish(PlayerLifecycleState state) {
    if (_disposed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _invalidateSession();
    await _identitySubscription?.cancel();
    _state = const PlayerLifecycleState.disposed();
    await _states.close();
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('PlayerLifecycleCoordinator is disposed.');
  }
}

class _PlayerSession {
  _PlayerSession(this.generation, this.identity);

  final int generation;
  final PlayerIdentity identity;
  PlayerRepository? repository;
  PlayerProfile? profile;
  PlayerDataResult<PlayerProgress>? progress;
  PlayerDataResult<PlayerInventory>? inventory;
  PlayerDataResult<PlayerSettings>? settings;
  bool progressLoaded = false;
  bool inventoryLoaded = false;
  bool settingsLoaded = false;
  Future<void> operation = Future<void>.value();
}
