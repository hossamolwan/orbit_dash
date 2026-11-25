import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/authenticated_player_repository.dart';
import 'package:orbit_dash/data/player/create_player_repository.dart';
import 'package:orbit_dash/data/player/player_data_source.dart';
import 'package:orbit_dash/data/player/player_repository.dart';
import 'package:orbit_dash/player_identity.dart';

void main() {
  test('waits for identity initialization before returning the repository', () async {
    final initializeCompleter = Completer<void>();
    final identityService = _FakeIdentityService(initializeCompleter.future);
    final firestore = _TrackingFirestore();
    var repositoryReady = false;

    final repositoryFuture = createPlayerRepository(
      identityService: identityService,
      firestore: firestore,
    ).then((repository) {
      repositoryReady = true;
      return repository;
    });

    await Future<void>.delayed(Duration.zero);
    expect(identityService.initializeCalls, 1);
    expect(repositoryReady, isFalse);

    initializeCompleter.complete();
    final repository = await repositoryFuture;

    expect(repository, isA<AuthenticatedPlayerRepository>());
    expect(repository, isA<PlayerRepository>());
    expect(repositoryReady, isTrue);
    expect(firestore.collectionPaths, isEmpty);

    await expectLater(
      repository.loadProfile(),
      throwsA(isA<PlayerDataAccessException>()),
    );
    expect(firestore.collectionPaths, ['players']);
  });
}

class _FakeIdentityService implements PlayerIdentityService {
  _FakeIdentityService(this.initialization);

  final Future<void> initialization;
  int initializeCalls = 0;

  @override
  PlayerIdentitySnapshot get state => const PlayerIdentitySnapshot(
    status: PlayerIdentityStatus.authenticated,
    identity: PlayerIdentity(id: 'composition-test-uid'),
  );

  @override
  Stream<PlayerIdentitySnapshot> get states => Stream.value(state);

  @override
  Future<void> initialize() {
    initializeCalls++;
    return initialization;
  }

  @override
  Future<PlayerIdentity> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
}

class _TrackingFirestore extends Fake implements FirebaseFirestore {
  final collectionPaths = <String>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    collectionPaths.add(collectionPath);
    throw Exception('Expected fake Firestore access during explicit read.');
  }
}
