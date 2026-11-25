import 'dart:async';

enum PlayerIdentityStatus {
  initializing,
  authenticated,
  unauthenticated,
  unavailable,
}

enum PlayerIdentityFailureCode {
  unavailable,
  unauthenticated,
  canceled,
  unknown,
}

class PlayerIdentity {
  const PlayerIdentity({
    required this.id,
    this.displayName,
    this.photoUrl,
  });
  final String id;
  final String? displayName;
  final String? photoUrl;
}

class PlayerIdentitySnapshot {
  const PlayerIdentitySnapshot({
    required this.status,
    this.identity,
    this.failureCode,
  });
  final PlayerIdentityStatus status;
  final PlayerIdentity? identity;
  final PlayerIdentityFailureCode? failureCode;
  bool get isAuthenticated =>
      status == PlayerIdentityStatus.authenticated && identity != null;
  bool get hasRecoverableIdentity => isAuthenticated && identity!.id.isNotEmpty;

  PlayerIdentity requireRecoverableIdentity() {
    if (!hasRecoverableIdentity) {
      throw const PlayerIdentityException(
        PlayerIdentityFailureCode.unauthenticated,
      );
    }
    return identity!;
  }
}

class PlayerIdentityException implements Exception {
  const PlayerIdentityException(this.code);
  final PlayerIdentityFailureCode code;
  @override
  String toString() => 'PlayerIdentityException($code)';
}

/// Provider boundary used by gameplay and authenticated API clients.
abstract interface class PlayerIdentityProvider {
  PlayerIdentity? get currentIdentity;
  Stream<PlayerIdentity?> get identityChanges;
  Future<PlayerIdentity> signInWithGoogle();
  Future<String?> getIdToken({required bool forceRefresh});
}

abstract interface class PlayerIdentityService {
  PlayerIdentitySnapshot get state;
  Stream<PlayerIdentitySnapshot> get states;
  Future<void> initialize();
  Future<PlayerIdentity> signInWithGoogle();
  Future<String?> getIdToken({bool forceRefresh = false});
}

class PlayerIdentityRepository implements PlayerIdentityService {
  PlayerIdentityRepository(this._provider);
  final PlayerIdentityProvider _provider;
  final StreamController<PlayerIdentitySnapshot> _states =
      StreamController<PlayerIdentitySnapshot>.broadcast(sync: true);
  PlayerIdentitySnapshot _state = const PlayerIdentitySnapshot(
    status: PlayerIdentityStatus.initializing,
  );
  StreamSubscription<PlayerIdentity?>? _subscription;
  Future<void>? _initialization;
  Future<PlayerIdentity>? _signInOperation;

  @override
  PlayerIdentitySnapshot get state => _state;
  @override
  Stream<PlayerIdentitySnapshot> get states => _states.stream;
  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _subscription = _provider.identityChanges.listen(
        _onIdentityChanged,
        onError: (Object _) => _setUnavailable(),
      );
      final existingIdentity = _provider.currentIdentity;
      if (existingIdentity != null) {
        _setAuthenticated(existingIdentity);
      } else {
        try {
          await signInWithGoogle();
        } on PlayerIdentityException catch (error) {
          _setSignInFailure(error.code);
        }
      }
    } catch (_) {
      _setUnavailable();
    }
  }

  @override
  Future<PlayerIdentity> signInWithGoogle() {
    final existing = _provider.currentIdentity;
    if (existing != null) {
      _setAuthenticated(existing);
      return Future.value(existing);
    }
    return _signInOperation ??= _performGoogleSignIn().whenComplete(
      () => _signInOperation = null,
    );
  }

  Future<PlayerIdentity> _performGoogleSignIn() async {
    try {
      final identity = await _provider.signInWithGoogle();
      if (identity.id.isEmpty) {
        throw const PlayerIdentityException(
          PlayerIdentityFailureCode.unavailable,
        );
      }
      _setAuthenticated(identity);
      return identity;
    } on PlayerIdentityException catch (error) {
      _setSignInFailure(error.code);
      rethrow;
    } catch (_) {
      _setUnavailable();
      throw const PlayerIdentityException(PlayerIdentityFailureCode.unknown);
    }
  }

  void _onIdentityChanged(PlayerIdentity? identity) {
    if (identity != null) {
      if (identity.id.isNotEmpty) {
        _setAuthenticated(identity);
      } else {
        _setUnavailable();
      }
    } else if (_state.isAuthenticated) {
      _set(
        const PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.unauthenticated,
          failureCode: PlayerIdentityFailureCode.unauthenticated,
        ),
      );
    }
  }

  void _setAuthenticated(PlayerIdentity identity) => _set(
    PlayerIdentitySnapshot(
      status: PlayerIdentityStatus.authenticated,
      identity: identity,
    ),
  );

  void _setUnavailable() => _set(
    const PlayerIdentitySnapshot(
      status: PlayerIdentityStatus.unavailable,
      failureCode: PlayerIdentityFailureCode.unavailable,
    ),
  );
  void _setSignInFailure(PlayerIdentityFailureCode code) {
    if (code == PlayerIdentityFailureCode.unavailable) {
      _setUnavailable();
    } else {
      _set(
        PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.unauthenticated,
          failureCode: code,
        ),
      );
    }
  }

  void _set(PlayerIdentitySnapshot state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!state.isAuthenticated) return null;
    try {
      return await _provider.getIdToken(forceRefresh: forceRefresh);
    } on PlayerIdentityException {
      rethrow;
    } catch (_) {
      throw const PlayerIdentityException(
        PlayerIdentityFailureCode.unavailable,
      );
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _states.close();
  }
}

class UnavailablePlayerIdentityService implements PlayerIdentityService {
  const UnavailablePlayerIdentityService();
  @override
  PlayerIdentitySnapshot get state => const PlayerIdentitySnapshot(
    status: PlayerIdentityStatus.unavailable,
    failureCode: PlayerIdentityFailureCode.unavailable,
  );
  @override
  Stream<PlayerIdentitySnapshot> get states => Stream.value(state);
  @override
  Future<void> initialize() async {}
  @override
  Future<PlayerIdentity> signInWithGoogle() => Future.error(
    const PlayerIdentityException(PlayerIdentityFailureCode.unavailable),
  );
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
}
