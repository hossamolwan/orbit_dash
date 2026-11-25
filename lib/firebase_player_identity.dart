import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:orbit_dash/firebase_options.dart';

import 'player_identity.dart';

class FirebasePlayerIdentityProvider implements PlayerIdentityProvider {
  FirebasePlayerIdentityProvider(this._auth, this._googleSignIn);

  final FirebaseAuth _auth;
  final GoogleSignInGateway _googleSignIn;

  @override
  PlayerIdentity? get currentIdentity => _mapUser(_auth.currentUser);

  @override
  Stream<PlayerIdentity?> get identityChanges =>
      _auth.authStateChanges().map(_mapUser);

  @override
  Future<PlayerIdentity> signInWithGoogle() async {
    try {
      final idToken = await _googleSignIn.authenticate();
      if (idToken == null || idToken.isEmpty) {
        throw const PlayerIdentityException(
          PlayerIdentityFailureCode.unavailable,
        );
      }
      final user = (await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      )).user;
      if (user == null) {
        throw const PlayerIdentityException(
          PlayerIdentityFailureCode.unavailable,
        );
      }
      return _identity(user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<String?> getIdToken({required bool forceRefresh}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static PlayerIdentity? _mapUser(User? user) =>
      user == null || user.isAnonymous ? null : _identity(user);

  static PlayerIdentity _identity(User user) => PlayerIdentity(
    id: user.uid,
    displayName: user.displayName,
    photoUrl: user.photoURL,
  );

  static PlayerIdentityException _mapAuthError(FirebaseAuthException error) {
    final code = switch (error.code) {
      'network-request-failed' ||
      'operation-not-allowed' ||
      'too-many-requests' => PlayerIdentityFailureCode.unavailable,
      _ => PlayerIdentityFailureCode.unknown,
    };
    return PlayerIdentityException(code);
  }
}

abstract interface class GoogleSignInGateway {
  Future<String?> authenticate();
}

class GoogleSignInPluginGateway implements GoogleSignInGateway {
  GoogleSignInPluginGateway(this._googleSignIn);
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  @override
  Future<String?> authenticate() async {
    try {
      await (_initialization ??= _googleSignIn.initialize());
      final account = await _googleSignIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const PlayerIdentityException(PlayerIdentityFailureCode.canceled);
      }
      throw const PlayerIdentityException(
        PlayerIdentityFailureCode.unavailable,
      );
    }
  }
}

typedef FirebaseInitializer = Future<void> Function(FirebaseOptions? options);
typedef FirebaseIdentityProviderFactory = PlayerIdentityProvider Function();

Future<void>? _firebaseInitialization;

Future<void> _initializeFirebase(FirebaseOptions options) {
  if (Firebase.apps.isNotEmpty) return Future<void>.value();
  return _firebaseInitialization ??= Firebase.initializeApp(options: options)
      .catchError((Object error) {
        _firebaseInitialization = null;
        throw error;
      });
}

/// Creates an identity service without making Firebase configuration mandatory
/// for local development or gameplay startup.
Future<PlayerIdentityService> createFirebasePlayerIdentityService({
  FirebaseOptions? options,
  FirebaseInitializer? initializeFirebase,
  FirebaseIdentityProviderFactory? providerFactory,
}) async {
  try {
    final firebaseOptions = options ?? DefaultFirebaseOptions.currentPlatform;
    if (initializeFirebase != null) {
      await initializeFirebase(firebaseOptions);
    } else {
      await _initializeFirebase(firebaseOptions);
    }
    final provider =
        providerFactory?.call() ??
        FirebasePlayerIdentityProvider(
          FirebaseAuth.instance,
          GoogleSignInPluginGateway(GoogleSignIn.instance),
        );
    return PlayerIdentityRepository(provider);
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Firebase identity is unavailable: $error');
    }
    return const UnavailablePlayerIdentityService();
  }
}
