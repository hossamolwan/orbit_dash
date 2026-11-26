import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/data/player/player_lifecycle_coordinator.dart';
import 'package:orbit_dash/data/player/player_data_result.dart';
import 'package:orbit_dash/data/player/player_repository.dart';
import 'package:orbit_dash/data/player/player_sync_write.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:orbit_dash/player_models.dart';
import 'package:orbit_dash/player_sync_contracts.dart';
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
    final service = _authenticatedService('firebase-user-1');
    final repository = _FakePlayerRepository(uid: 'firebase-user-1');
    await tester.pumpWidget(
      _testApp(service, repositoryFactory: (_) => repository),
    );
    await _pumpFrames(tester);

    expect(find.byType(OrbitGamePage), findsOneWidget);
    final game = tester.widget<OrbitGamePage>(find.byType(OrbitGamePage));
    expect(game.session?.identity.id, 'firebase-user-1');
    expect(game.session?.profile.uid, 'firebase-user-1');
    expect(repository.loadProfileCalls, 1);
  });

  testWidgets('gameplay stays blocked when the loaded profile UID mismatches', (
    tester,
  ) async {
    final service = _authenticatedService('authenticated-player');
    await tester.pumpWidget(
      _testApp(
        service,
        repositoryFactory: (_) =>
            _FakePlayerRepository(uid: 'different-player'),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(
      find.textContaining('We could not load your player data'),
      findsOneWidget,
    );
  });

  testWidgets('gameplay stores bind to the supplied session UID', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    final date = DateTime.utc(2025);
    final session = PlayerSessionSnapshot(
      identity: const PlayerIdentity(id: 'session-player'),
      profile: PlayerProfile(
        uid: 'session-player',
        displayName: 'Pilot',
        createdAt: date,
        updatedAt: date,
      ),
      progress: const PlayerDataResult<PlayerProgress>.present(
        PlayerProgress(),
      ),
      inventory: PlayerDataResult<PlayerInventory>.present(PlayerInventory()),
      settings: const PlayerDataResult<PlayerSettings>.present(
        PlayerSettings(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(
          session: session,
          audioController: _TestAudioController(),
          testDriver: driver,
        ),
      ),
    );
    await tester.pump();

    expect(driver.playerId, 'session-player');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        AccountScopedPreferences.keyFor('session-player', GemWallet.stateKey),
      ),
      isNotNull,
    );
    expect(
      preferences.getString(
        AccountScopedPreferences.localKey(GemWallet.stateKey),
      ),
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
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
    expect(
      tester
          .widget<OrbitGamePage>(find.byType(OrbitGamePage))
          .session
          ?.identity
          .id,
      'player-a',
    );

    service.emit(_authenticated('player-b'));
    await tester.pump();
    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('LOADING YOUR PILOT PROFILE'), findsOneWidget);

    bProfile.complete(_profile('player-b'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey<String>('player-b')), findsOneWidget);
    expect(
      tester
          .widget<OrbitGamePage>(find.byType(OrbitGamePage))
          .session
          ?.identity
          .id,
      'player-b',
    );
  });

  testWidgets('gameplay stores use the authenticated UID namespace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.keyFor('player-a', GemWallet.stateKey): '{"version":2,"balance":23,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
      AccountScopedPreferences.keyFor('player-b', GemWallet.stateKey): '{"version":2,"balance":91,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
    });
    final service = _authenticatedService('player-a');
    await tester.pumpWidget(_testApp(service));
    await _pumpFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('main-menu-gem-balance')))
          .data,
      '23 G',
    );

    service.emit(_authenticated('player-b'));
    await _pumpFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('main-menu-gem-balance')))
          .data,
      '91 G',
    );
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
    await tester.pump();
    expect(coordinator!.start, throwsStateError);
    expect(service.disposeCalls, 0);
    expect(service.hasListeners, isFalse);
    service.emit(_authenticated('another-player'));
    await tester.pump();
  });

  testWidgets('gate disposes a factory-created service exactly once', (
    tester,
  ) async {
    final service = _FakeIdentityService();
    await tester.pumpWidget(
      OrbitDashApp(identityServiceFactory: () async => service),
    );
    await _pumpFrames(tester);
    expect(service.hasListeners, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
    expect(service.disposeCalls, 1);
    expect(service.hasListeners, isFalse);
  });

  testWidgets(
    'factory service completing after disposal is disposed unattached',
    (tester) async {
      final serviceCreation = Completer<PlayerIdentityService>();
      final service = _FakeIdentityService();
      var coordinatorCreations = 0;
      await tester.pumpWidget(
        OrbitDashApp(
          identityServiceFactory: () => serviceCreation.future,
          playerLifecycleCoordinatorFactory: (identityService) {
            coordinatorCreations++;
            return PlayerLifecycleCoordinator(identityService: identityService);
          },
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      serviceCreation.complete(service);
      await tester.pump();

      expect(service.disposeCalls, 1);
      expect(service.hasListeners, isFalse);
      expect(coordinatorCreations, 0);
    },
  );

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

  testWidgets('late authentication update recovers after sign-in timeout', (
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 46));
    expect(
      find.text('Sign-in took too long. Check your connection and retry.'),
      findsOneWidget,
    );

    service.emit(_authenticated('late-authenticated-player'));
    await _pumpFrames(tester);
    pendingSignIn.completeError(
      const PlayerIdentityException(PlayerIdentityFailureCode.unavailable),
    );
    await tester.pump();

    expect(find.byType(OrbitGamePage), findsOneWidget);
    expect(
      find.text('Sign-in took too long. Check your connection and retry.'),
      findsNothing,
    );
    expect(service.signInCount, 1);
  });

  testWidgets('a timeout cannot replace a newer authenticated stream update', (
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
    await tester.pump();

    service.emit(_authenticated('authenticated-before-timeout'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 46));

    expect(service.signInCount, 1);
    expect(
      find.text('Sign-in took too long. Check your connection and retry.'),
      findsNothing,
    );
    expect(find.byType(OrbitGamePage), findsOneWidget);

    pendingSignIn.complete(
      const PlayerIdentity(id: 'authenticated-before-timeout'),
    );
    await tester.pump();
  });

  testWidgets(
    'late initialization completion starts no lifecycle work after disposal',
    (tester) async {
      final initializeGate = Completer<void>();
      final service = _FakeIdentityService()..initializeGate = initializeGate;
      var repositoryCreations = 0;
      await tester.pumpWidget(
        _testApp(
          service,
          repositoryFactory: (_) {
            repositoryCreations++;
            return _FakePlayerRepository(uid: 'late-initialization');
          },
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      service.emit(_authenticated('late-initialization'));
      initializeGate.complete();
      await tester.pump();
      await tester.pump();

      expect(repositoryCreations, 0);
      expect(service.disposeCalls, 0);
    },
  );
}

class _FakeIdentityService
    implements PlayerIdentityService, DisposablePlayerIdentityService {
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
  Completer<void>? initializeGate;
  Object? initializeError;
  int initializeCalls = 0;
  int signInCount = 0;
  int disposeCalls = 0;
  bool get hasListeners => _states.hasListener;

  @override
  PlayerIdentitySnapshot get state => initialState;
  @override
  Stream<PlayerIdentitySnapshot> get states => _states.stream;
  @override
  Future<void> initialize() => _initialization ??= _performInitialization();

  Future<void> _performInitialization() async {
    initializeCalls++;
    await initializeGate?.future;
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

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _states.close();
  }
}

class _TestAudioController extends GameAudioController {
  @override
  bool get musicEnabled => true;

  @override
  bool get effectsEnabled => true;

  @override
  Future<void> initialize() async {}

  @override
  void setGameState(AudioRunState state) {}

  @override
  void setAppActive(bool active) {}

  @override
  Future<void> setMusicEnabled(bool enabled) async {}

  @override
  Future<void> setEffectsEnabled(bool enabled) async {}

  @override
  void playEffect(GameSoundEffect effect) {}

  @override
  Future<void> shutdown() async {}
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
  Future<PlayerDataResult<PlayerProgress>> loadProgress() async {
    if (progressLoad case final completer?) {
      final result = await completer.future;
      return result == null
          ? const PlayerDataResult<PlayerProgress>.missing()
          : PlayerDataResult<PlayerProgress>.present(result);
    }
    return const PlayerDataResult<PlayerProgress>.missing();
  }

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory() async =>
      const PlayerDataResult<PlayerInventory>.missing();

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings() async =>
      const PlayerDataResult<PlayerSettings>.missing();

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
