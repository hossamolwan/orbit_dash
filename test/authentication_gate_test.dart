import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/player_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('initializing blocks gameplay and shows loading', (tester) async {
    final service = _FakeIdentityService();
    await tester.pumpWidget(OrbitDashApp(identityService: service));
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
    await tester.pumpWidget(OrbitDashApp(identityService: service));
    await tester.pump();

    expect(find.byType(OrbitGamePage), findsNothing);
    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
    expect(find.textContaining('Guest'), findsNothing);
    expect(find.textContaining('Skip'), findsNothing);
  });

  testWidgets('authenticated users can access gameplay', (tester) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.authenticated,
        identity: PlayerIdentity(id: 'firebase-user-1'),
      ),
    );
    await tester.pumpWidget(OrbitDashApp(identityService: service));
    await tester.pump();

    expect(find.byType(OrbitGamePage), findsOneWidget);
  });

  testWidgets('Google chooser cancellation does not unlock gameplay', (
    tester,
  ) async {
    final service = _FakeIdentityService(
      initialState: const PlayerIdentitySnapshot(
        status: PlayerIdentityStatus.unauthenticated,
      ),
    );
    await tester.pumpWidget(OrbitDashApp(identityService: service));
    await tester.pump();
    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(OrbitDashApp(identityService: service));

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
    await tester.pumpWidget(OrbitDashApp(identityService: service));
    await tester.pump();

    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(OrbitDashApp(identityService: service));
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
    await tester.pumpWidget(OrbitDashApp(identityService: service));
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
    await tester.pumpAndSettle();
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
  int signInCount = 0;

  @override
  PlayerIdentitySnapshot get state => initialState;
  @override
  Stream<PlayerIdentitySnapshot> get states => _states.stream;
  @override
  Future<void> initialize() async {}
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
