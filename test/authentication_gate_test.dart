import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/player_lifecycle_coordinator.dart';
import 'package:orbit_dash/data/player/player_repository.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('initializing blocks gameplay and shows loading', (tester) async {
    final service = _FakeIdentityService();
    await tester.pumpWidget(_testApp(service));
    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('CHECKING YOUR ACCOUNT'), findsOneWidget);
  });

  testWidgets('unauthenticated users see Google sign-in without bypass', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
      ),
    );
    await tester.pumpWidget(_testApp(service));
    await tester.pump();

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
    expect(find.textContaining('Guest'), findsNothing);
    expect(find.textContaining('Skip'), findsNothing);
  });

  testWidgets('authenticated users can access gameplay after hydration', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.authenticated,
        identity: PlayerIdentity(id: 'firebase-user-1'),
      ),
    );
    await tester.pumpWidget(_testApp(service));
    await _pumpFrames(tester);

    expect(find.byType(OrbitGamePage), findsOneWidget);
  });

  testWidgets(
    'gameplay stays blocked through profile and player data loading',
    (tester) async {
      final service = _authenticatedService('loading-player');
      final profileLoad = Completer<PlayerProfile?>();
      final progressLoad = Completer<PlayerProgress?>();
      final repository = _FakePlayerRepository(
        uid: 'loading-player',
        profileLoad: profileLoad,
        progressLoad: progressLoad,
      );

      await tester.pumpWidget(
        _testApp(service, repositoryFactory: (_) => repository),
      );
      await tester.pump();
      expect(find.byType(OrbitGamePage), findsNothing);
      expect(find.text('LOADING YOUR PILOT PROFILE'), findsOneWidget);

      profileLoad.complete(_profile('loading-player'));
      await tester.pump();
      expect(find.byType(OrbitGamePage), findsNothing);
      expect(find.text('SYNCING YOUR PLAYER DATA'), findsOneWidget);

      progressLoad.complete(const PlayerProgress(level: 2));
      await _pumpFrames(tester);
      expect(find.byType(OrbitGamePage), findsOneWidget);
    },
  );

  testWidgets('missing profile shows profile creation state before gameplay', (
    tester,
  ) async {
    final service = _authenticatedService('new-player');
    final profileCreation = Completer<PlayerProfile>();
    final repository = _FakePlayerRepository(
      uid: 'new-player',
      missingProfile: true,
      profileCreation: profileCreation,
    );

    await tester.pumpWidget(
      _testApp(service, repositoryFactory: (_) => repository),
    );
    await tester.pump();
    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('SETTING UP YOUR PILOT PROFILE'), findsOneWidget);
    expect(repository.ensureProfileCalls, 1);

    profileCreation.complete(_profile('new-player'));
    await _pumpFrames(tester);
    expect(find.byType(OrbitGamePage), findsOneWidget);
  });

  testWidgets('retryable lifecycle failure retries data load', (tester) async {
    final service = _authenticatedService('retry-player');
    final repository = _FakePlayerRepository(
      uid: 'retry-player',
      profileFailuresRemaining: 1,
    );
    await tester.pumpWidget(
      _testApp(service, repositoryFactory: (_) => repository),
    );
    await _pumpFrames(tester);

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(
      find.text(
        'We could not load your player data. Check your connection and retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);

    await tester.tap(find.text('RETRY'));
    await _pumpFrames(tester);

    expect(repository.loadProfileCalls, 2);
    expect(find.byType(OrbitGamePage), findsOneWidget);
  });

  testWidgets(
    'identity initialization failure uses Google retry, not lifecycle retry',
    (tester) async {
      final service = _authenticatedService('identity-retry')
        ..initializeError = StateError('initialization failed');
      service.onSignIn = () async {
        service.emit(_authenticated('identity-retry'));
        return const PlayerIdentity(id: 'identity-retry');
      };
      final repository = _FakePlayerRepository(uid: 'identity-retry');
      await tester.pumpWidget(
        _testApp(service, repositoryFactory: (_) => repository),
      );
      await _pumpFrames(tester);

      expect(find.byType(OrbitGamePage), findsNothing);
      expect(
        find.text('Sign-in is temporarily unavailable. Please try again.'),
        findsOneWidget,
      );
      expect(service.initializeCalls, 1);

      await tester.tap(find.text('RETRY'));
      await _pumpFrames(tester);

      expect(service.initializeCalls, 1);
      expect(service.signInCount, 1);
      expect(find.byType(OrbitGamePage), findsOneWidget);
    },
  );

  testWidgets('ready gameplay is hidden immediately after an account switch', (
    tester,
  ) async {
    final service = _authenticatedService('player-a');
    final bProfile = Completer<PlayerProfile?>();
    final repositoryA = _FakePlayerRepository(uid: 'player-a');
    final repositoryB = _FakePlayerRepository(
      uid: 'player-b',
      profileLoad: bProfile,
    );
    await tester.pumpWidget(
      _testApp(
        service,
        repositoryFactory: (identity) =>
            identity.state.requireRecoverableIdentity().id == 'player-a'
            ? repositoryA
            : repositoryB,
      ),
    );
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey<String>('player-a')), findsOneWidget);

    service.emit(_authenticated('player-b'));
    await tester.pump();
    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('LOADING YOUR PILOT PROFILE'), findsOneWidget);

    bProfile.complete(_profile('player-b'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey<String>('player-b')), findsOneWidget);
  });

  testWidgets(
    'account switch hides old session until the new player is ready',
    (tester) async {
      final service = _authenticatedService('player-a');
      final aProfile = Completer<PlayerProfile?>();
      final bProfile = Completer<PlayerProfile?>();
      final repositoryA = _FakePlayerRepository(
        uid: 'player-a',
        profileLoad: aProfile,
      );
      final repositoryB = _FakePlayerRepository(
        uid: 'player-b',
        profileLoad: bProfile,
      );
      await tester.pumpWidget(
        _testApp(
          service,
          repositoryFactory: (identity) =>
              identity.state.requireRecoverableIdentity().id == 'player-a'
              ? repositoryA
              : repositoryB,
        ),
      );
      await tester.pump();
      expect(find.byType(OrbitGamePage), findsNothing);

      service.emit(_authenticated('player-b'));
      await tester.pump();
      expect(find.byType(OrbitGamePage), findsNothing);
      expect(find.text('LOADING YOUR PILOT PROFILE'), findsOneWidget);

      bProfile.complete(_profile('player-b'));
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey<String>('player-b')), findsOneWidget);

      aProfile.complete(_profile('player-a', name: 'stale response'));
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey<String>('player-b')), findsOneWidget);
      expect(find.byType(OrbitGamePage), findsOneWidget);
    },
  );

  testWidgets('gate disposes its lifecycle coordinator and listeners', (
    tester,
  ) async {
    final service = _authenticatedService('dispose-player');
    PlayerLifecycleCoordinator? coordinator;
    await tester.pumpWidget(
      _testApp(service, onCoordinator: (created) => coordinator = created),
    );
    await _pumpFrames(tester);
    expect(find.byType(OrbitGamePage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(coordinator!.start, throwsStateError);
    service.emit(_authenticated('another-player'));
    await tester.pump();
  });

  testWidgets('Google chooser cancellation does not unlock gameplay', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
      ),
    );
    await tester.pumpWidget(_testApp(service));
    await tester.pump();
    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await _pumpFrames(tester);

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
    expect(find.textContaining('canceled'), findsOneWidget);
  });

  testWidgets('authentication failure does not unlock gameplay', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unavailable,
        failureCode: PlayerIdentityFailureCode.unavailable,
      ),
    );
    await tester.pumpWidget(_testApp(service));

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(
      find.text('Sign-in is temporarily unavailable. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);
  });

  testWidgets('retry can authenticate and unlock gameplay', (tester) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
      ),
    );
    service.onSignIn = () async {
      service.emit(
        const PlayerIdentitySnapshot(
          status: PlayerIdentityStatus.authenticated,
          identity: PlayerIdentity(id: 'firebase-user-2'),
        ),
      );
      return const PlayerIdentity(id: 'firebase-user-2');
    };
    await tester.pumpWidget(_testApp(service));
    await tester.pump();

    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await _pumpFrames(tester);

    expect(service.signInCount, 1);
    expect(find.byType(OrbitGamePage), findsOneWidget);
  });

  testWidgets('authentication loss returns to the gate', (tester) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.authenticated,
        identity: PlayerIdentity(id: 'firebase-user-3'),
      ),
    );
    await tester.pumpWidget(_testApp(service));
    await tester.pump();
    expect(find.byType(OrbitGamePage), findsOneWidget);

    service.emit(
      const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
        failureCode: PlayerIdentityFailureCode.unauthenticated,
      ),
    );
    await tester.pump();

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
  });

  testWidgets('duplicate authentication taps start only one request', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
      ),
    );
    final pendingSignIn = Completer<PlayerIdentity>();
    service.onSignIn = () => pendingSignIn.future;
    await tester.pumpWidget(_testApp(service));
    await tester.pump();

    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.pump();
    expect(find.text('CHECKING YOUR ACCOUNT'), findsOneWidget);
    expect(service.signInCount, 1);

    pendingSignIn.complete(const PlayerIdentity(id: 'firebase-user-4'));
    service.emit(
      const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.authenticated,
        identity: PlayerIdentity(id: 'firebase-user-4'),
      ),
    );
    await _pumpFrames(tester);
    expect(service.signInCount, 1);
    expect(find.byType(OrbitGamePage), findsOneWidget);
  });
}

class _FakeIdentityService implements PlayerIdentityService {
  _FakeIdentityService({
    this.initialState = const PlayerIdentitySnapshot(
      status: PlayerIdentityStatus.initializing,
    ),
  });

  final StreamController<PlayerIdentitySnapshot> _states =
      StreamController<PlayerIdentitySnapshot>.broadcast(sync: true);
  PlayerIdentitySnapshot initialState;
  Future<PlayerIdentity> Function()? onSignIn;
  Future<void>? _initialization;
  Object? initializeError;
  int initializeCalls = 0;
  int signInCount = 0;

  @override
  PlayerIdentitySnapshot get state => initialState;
  @override
  Stream<PlayerIdentitySnapshot> get states => _states.stream;
  @override
  Future<void> initialize() => _initialization ??= _performInitialization();

  Future<void> _performInitialization() async {
    initializeCalls++;
    if (initializeError case final error?) throw error;
  }

  @override
  Future<PlayerIdentity> signInWithGoogle() async {
    signInCount++;
    final action = onSignIn;
    if (action != null) return action();
    throw const PlayerIdentityException(PlayerIdentityFailureCode.canceled);
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  void emit(PlayerIdentitySnapshot next) {
    initialState = next;
    _states.add(next);
  }
}

Widget _testApp(
  _FakeIdentityService service, {
  _FakePlayerRepository Function(PlayerIdentityService service)?
  repositoryFactory,
  void Function(PlayerLifecycleCoordinator coordinator)? onCoordinator,
}) => OrbitDashApp(
  identityService: service,
  playerLifecycleCoordinatorFactory: (identityService) {
    final coordinator = PlayerLifecycleCoordinator(
      identityService: identityService,
      repositoryFactory: (_) async =>
          repositoryFactory?.call(identityService) ??
          _FakePlayerRepository(
            uid: identityService.state.requireRecoverableIdentity().id,
          ),
    );
    onCoordinator?.call(coordinator);
    return coordinator;
  },
);

_FakeIdentityService _authenticatedService(String uid) =>
    _FakeIdentityService(initialState: _authenticated(uid));

Future<void> _pumpFrames(WidgetTester tester, {int count = 6}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump();
  }
}

PlayerIdentitySnapshot _authenticated(String uid) => PlayerIdentitySnapshot(
  status: PlayerIdentityStatus.authenticated,
  identity: PlayerIdentity(id: uid),
);

class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository({
    required this.uid,
    this.profileLoad,
    this.progressLoad,
    this.profileCreation,
    this.missingProfile = false,
    this.profileFailuresRemaining = 0,
  });

  final String uid;
  final Completer<PlayerProfile?>? profileLoad;
  final Completer<PlayerProgress?>? progressLoad;
  final Completer<PlayerProfile>? profileCreation;
  final bool missingProfile;
  int profileFailuresRemaining;
  int loadProfileCalls = 0;
  int ensureProfileCalls = 0;

  @override
  Future<PlayerProfile?> loadProfile() async {
    loadProfileCalls++;
    if (profileFailuresRemaining > 0) {
      profileFailuresRemaining--;
      throw StateError('temporary profile read failure');
    }
    if (profileLoad != null) return profileLoad!.future;
    return missingProfile ? null : _profile(uid);
  }

  @override
  Future<PlayerProfile> ensureProfile() async {
    ensureProfileCalls++;
    if (profileCreation != null) return profileCreation!.future;
    return _profile(uid);
  }

  @override
  Future<PlayerProfile> updateProfile({
    required String displayName,
    required String? photoUrl,
  }) => throw UnimplementedError();

  @override
  Future<PlayerProgress?> loadProgress() async {
    if (progressLoad case final completer?) return completer.future;
    return null;
  }

  @override
  Future<PlayerInventory?> loadInventory() async => null;

  @override
  Future<PlayerSettings?> loadSettings() async => null;

  @override
  Future<void> saveSettings(PlayerSettings settings) async =>
      throw UnimplementedError();
}

PlayerProfile _profile(String uid, {String name = 'Pilot'}) {
  final now = DateTime.utc(2026);
  return PlayerProfile(
    uid: uid,
    displayName: name,
    createdAt: now,
    updatedAt: now,
  );
}
