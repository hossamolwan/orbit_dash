import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../player_models.dart';
import 'player_data_source.dart';
import 'player_data_result.dart';

/// Firestore implementation of the player data storage boundary.
///
/// Profiles live at `players/{uid}`. Progress, inventory, and settings live in
/// their own `data` documents under the corresponding subcollections.
class FirestorePlayerDataSource implements PlayerDataSource {
  FirestorePlayerDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _playerDocument(String uid) =>
      _firestore.collection('players').doc(uid);

  DocumentReference<Map<String, dynamic>> _domainDocument(
    String uid,
    String domain,
  ) => _playerDocument(uid).collection(domain).doc('data');

  @override
  Future<PlayerProfile?> loadProfile(String uid) =>
      _guard('load profile', () async {
        final snapshot = await _playerDocument(uid).get();
        final data = snapshot.data();
        return data == null ? null : _profileFromFirestore(uid, data);
      });

  @override
  Future<PlayerProfile> createProfileIfAbsent(PlayerProfile profile) {
    if (profile.uid.isEmpty) {
      throw const PlayerDataAccessException(
        'Cannot create a player profile without a UID.',
      );
    }
    final reference = _playerDocument(profile.uid);
    return _guard(
      'create profile if absent',
      () => _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        final existingData = snapshot.data();
        if (existingData != null) {
          return _profileFromFirestore(profile.uid, existingData);
        }
        transaction.set(reference, _profileToFirestore(profile));
        return profile;
      }),
    );
  }

  @override
  Future<PlayerProfile> updateProfile({
    required String uid,
    required String displayName,
    required String? photoUrl,
  }) => _guard(
    'update profile',
    () => _firestore.runTransaction((transaction) async {
      final reference = _playerDocument(uid);
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null) {
        throw const PlayerDataAccessException(
          'Cannot update a profile that does not exist.',
        );
      }
      final current = _profileFromFirestore(uid, data);
      final updatedAt = Timestamp.now();
      transaction.update(reference, {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'updatedAt': updatedAt,
      });
      return PlayerProfile(
        uid: current.uid,
        displayName: displayName,
        photoUrl: photoUrl,
        createdAt: current.createdAt,
        updatedAt: updatedAt.toDate(),
        schemaVersion: current.schemaVersion,
      );
    }),
  );

  @override
  Future<PlayerDataResult<PlayerProgress>> loadProgress(String uid) =>
      _loadModel(uid, 'progress', PlayerProgress.fromMap);

  @override
  Future<PlayerDataResult<PlayerInventory>> loadInventory(String uid) =>
      _loadModel(uid, 'inventory', PlayerInventory.fromMap);

  @override
  Future<PlayerDataResult<PlayerSettings>> loadSettings(String uid) =>
      _loadModel(uid, 'settings', PlayerSettings.fromMap);

  Future<PlayerDataResult<T>> _loadModel<T>(
    String uid,
    String domain,
    T Function(Map<String, Object?>) decode,
  ) => _guard('load $domain', () async {
    final snapshot = await _domainDocument(uid, domain).get();
    return playerDataResultFromDocument<T>(
      domain: domain,
      exists: snapshot.exists,
      data: snapshot.data(),
      decode: decode,
    );
  });

  @override
  Future<void> saveSettings(String uid, PlayerSettings settings) => _guard(
    'save settings',
    () => _domainDocument(
      uid,
      'settings',
    ).set(settings.toMap(), SetOptions(merge: true)),
  );

  Map<String, Object?> _profileToFirestore(PlayerProfile profile) => {
    ...profile.toMap(),
    'createdAt': Timestamp.fromDate(profile.createdAt),
    'updatedAt': Timestamp.fromDate(profile.updatedAt),
  };

  PlayerProfile _profileFromFirestore(
    String documentUid,
    Map<String, dynamic> data,
  ) {
    final storedUid = data['uid'];
    if (storedUid is! String || storedUid.isEmpty) {
      throw const PlayerDataAccessException(
        'Profile document is missing a valid UID.',
      );
    }
    if (storedUid != documentUid) {
      throw const PlayerDataAccessException(
        'Profile UID does not match its document ID.',
      );
    }

    final modelData = Map<String, Object?>.from(data)
      ..['createdAt'] = _modelTimestamp(data['createdAt'])
      ..['updatedAt'] = _modelTimestamp(data['updatedAt']);
    return PlayerProfile.fromMap(modelData);
  }

  Object? _modelTimestamp(Object? value) =>
      value is Timestamp ? value.toDate() : value;

  Future<T> _guard<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on PlayerDataAccessException {
      rethrow;
    } on FirebaseException catch (error) {
      throw PlayerDataAccessException(
        '$operation failed (Firestore ${error.code}).',
      );
    } on TypeError {
      throw PlayerDataAccessException(
        '$operation failed because stored data has an invalid shape.',
      );
    } on FormatException {
      throw PlayerDataAccessException(
        '$operation failed because stored data could not be decoded.',
      );
    } on Exception catch (error) {
      throw PlayerDataAccessException(
        '$operation failed (${error.runtimeType}).',
      );
    }
  }
}

/// Maps Firestore's document-existence metadata separately from decoded model
/// contents so an empty/default-valued document remains present.
@visibleForTesting
PlayerDataResult<T> playerDataResultFromDocument<T>({
  required String domain,
  required bool exists,
  required Map<String, dynamic>? data,
  required T Function(Map<String, Object?>) decode,
}) {
  if (!exists) return PlayerDataResult<T>.missing();
  if (data == null) {
    throw PlayerDataAccessException(
      'load $domain failed because the existing document has no data.',
    );
  }
  return PlayerDataResult<T>.present(decode(Map<String, Object?>.from(data)));
}
