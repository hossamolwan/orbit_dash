import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/firebase_options.dart';
import 'package:orbit_dash/firebase_player_identity.dart';
import 'package:orbit_dash/player_identity.dart';

void main() {
  group('PlayerIdentityRepository', () {
    test('signs in with Google and preserves Firebase UID', () async {
      final provider = _FakeIdentityProvider();
      final service = PlayerIdentityRepository(provider);
      await service.initialize();
      expect(provider.googleSignInCount, 1);
      expect(service.state.status, PlayerIdentityStatus.authenticated);
      expect(service.state.identity?.id, 'firebase-uid-42');
      expect(service.state.hasRecoverableIdentity, isTrue);
      expect(await service.getIdToken(), 'token-for-firebase-uid-42');
      await service.dispose();
    });

    test('reuses an existing authenticated session', () async {
      final provider = _FakeIdentityProvider(
        currentIdentity: const PlayerIdentity(id: 'existing-uid'),
      );
      final service = PlayerIdentityRepository(provider);
      await service.initialize();
      expect(provider.googleSignInCount, 0);
      expect(service.state.requireRecoverableIdentity().id, 'existing-uid');
      await service.dispose();
    });

    test('cancellation leaves a retryable unauthenticated state', () async {
      final provider = _FakeIdentityProvider(
        signInError: const PlayerIdentityException(
          PlayerIdentityFailureCode.canceled,
        ),
      );
      final service = PlayerIdentityRepository(provider);
      await service.initialize();
      expect(service.state.status, PlayerIdentityStatus.unauthenticated);
      expect(service.state.failureCode, PlayerIdentityFailureCode.canceled);
      expect(service.state.identity, isNull);
      await service.dispose();
    });

    test('Google sign-in failure maps to unavailable', () async {
      final provider = _FakeIdentityProvider(
        signInError: const PlayerIdentityException(
          PlayerIdentityFailureCode.unavailable,
        ),
      );
      final service = PlayerIdentityRepository(provider);
      await service.initialize();
      expect(service.state.status, PlayerIdentityStatus.unavailable);
      expect(service.state.failureCode, PlayerIdentityFailureCode.unavailable);
      await service.dispose();
    });

    test('duplicate sign-in requests share one operation', () async {
      final provider = _FakeIdentityProvider(signInDelay: true);
      final service = PlayerIdentityRepository(provider);
      final first = service.signInWithGoogle();
      final second = service.signInWithGoogle();
      expect(await first, await second);
      expect(provider.googleSignInCount, 1);
      await service.dispose();
    });
  });

  test(
    'Firebase bootstrap passes generated options before creating provider',
    () async {
      var initialized = false;
      final service = await createFirebasePlayerIdentityService(
        initializeFirebase: (options) async {
          expect(options, DefaultFirebaseOptions.currentPlatform);
          await Future<void>.delayed(Duration.zero);
          initialized = true;
        },
        providerFactory: () {
          expect(initialized, isTrue);
          return _FakeIdentityProvider();
        },
      );
      expect(service.state.status, PlayerIdentityStatus.initializing);
    },
  );

  test('Firebase initialization failure degrades safely', () async {
    final service = await createFirebasePlayerIdentityService(
      initializeFirebase: (_) => throw StateError('Firebase unavailable'),
    );
    expect(service.state.status, PlayerIdentityStatus.unavailable);
    await service.initialize();
    expect(service.state.identity, isNull);
  });
}

class _FakeIdentityProvider implements PlayerIdentityProvider {
  _FakeIdentityProvider({
    this.currentIdentity,
    this.signInError,
    this.signInDelay = false,
  });
  final StreamController<PlayerIdentity?> _changes =
      StreamController<PlayerIdentity?>.broadcast(sync: true);
  @override
  PlayerIdentity? currentIdentity;
  final PlayerIdentityException? signInError;
  final bool signInDelay;
  int googleSignInCount = 0;

  @override
  Stream<PlayerIdentity?> get identityChanges => _changes.stream;
  @override
  Future<PlayerIdentity> signInWithGoogle() async {
    googleSignInCount++;
    if (signInDelay) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (signInError != null) throw signInError!;
    currentIdentity = const PlayerIdentity(id: 'firebase-uid-42');
    _changes.add(currentIdentity);
    return currentIdentity!;
  }

  @override
  Future<String?> getIdToken({required bool forceRefresh}) async =>
      'token-for-${currentIdentity?.id}';
}
