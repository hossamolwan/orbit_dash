import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../player_models.dart';
import '../../player_sync_contracts.dart';
import 'player_data_source.dart';
import 'player_data_result.dart';
import 'player_sync_write.dart';

/// Firestore implementation of the player data storage boundary.
///
/// Profiles live at `players/{uid}`. Progress, inventory, and settings live in
/// their own `data` documents under the corresponding subcollections.
class FirestorePlayerDataSource implements PlayerDataSource {
  static const _maxFirestoreRevision = 0x7fffffffffffffff;

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

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncProgress>> loadSyncProgress(
    String uid,
  ) => _loadSyncDomain(uid, 'progress', PlayerSyncProgress.decode);

  @override
  Future<PlayerSyncCloudSnapshot<PlayerSyncInventory>> loadSyncInventory(
    String uid,
  ) => _loadSyncDomain(uid, 'inventory', PlayerSyncInventory.decode);

  Future<PlayerSyncCloudSnapshot<T>> _loadSyncDomain<T>(
    String uid,
    String domain,
    PlayerSyncDecodeResult<T> Function({required bool exists, Object? data})
    decode,
  ) => _guard('load $domain sync data', () async {
    final snapshot = await _domainDocument(uid, domain).get();
    if (!snapshot.exists) {
      return PlayerSyncCloudSnapshot<T>(revision: 0, value: null);
    }
    final documentData = snapshot.data();
    if (!(documentData?.containsKey('sync') ?? false)) {
      return PlayerSyncCloudSnapshot<T>(revision: 0, value: null);
    }
    final stored = documentData!['sync'];
    final envelope = _stringKeyedMap(stored);
    if (envelope == null ||
        envelope.keys.toSet().difference(const {
          'revision',
          'payload',
        }).isNotEmpty ||
        envelope['revision'] is! int ||
        (envelope['revision'] as int) < 1 ||
        envelope['payload'] is! Map) {
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.invalidStoredData,
      );
    }
    final result = decode(exists: true, data: envelope['payload']);
    if (result.status != PlayerSyncDataStatus.valid) {
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.invalidStoredData,
      );
    }
    return PlayerSyncCloudSnapshot<T>(
      revision: envelope['revision'] as int,
      value: result.value,
    );
  });

  @override
  Future<PlayerSyncWriteResult> saveSyncProgress({
    required String uid,
    required PlayerSyncProgress progress,
    required int expectedRevision,
  }) => _saveSyncDomain(
    uid: uid,
    domain: 'progress',
    payload: progress.toMap(),
    decode: PlayerSyncProgress.decode,
    expectedRevision: expectedRevision,
  );

  @override
  Future<PlayerSyncWriteResult> saveSyncInventory({
    required String uid,
    required PlayerSyncInventory inventory,
    required int expectedRevision,
  }) => _saveSyncDomain(
    uid: uid,
    domain: 'inventory',
    payload: inventory.toMap(),
    decode: PlayerSyncInventory.decode,
    expectedRevision: expectedRevision,
  );

  Future<PlayerSyncWriteResult> _saveSyncDomain<T>({
    required String uid,
    required String domain,
    required Map<String, Object?> payload,
    required PlayerSyncDecodeResult<T> Function({
      required bool exists,
      Object? data,
    })
    decode,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 0 || expectedRevision >= _maxFirestoreRevision) {
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.invalidRevision,
      );
    }
    final validation = decode(exists: true, data: payload);
    if (validation.status != PlayerSyncDataStatus.valid) {
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.invalidPayload,
      );
    }
    try {
      return await _firestore.runTransaction((transaction) async {
        final reference = _domainDocument(uid, domain);
        final snapshot = await transaction.get(reference);
        final documentData = snapshot.data();
        final hasSyncEnvelope = documentData?.containsKey('sync') ?? false;
        final stored = documentData?['sync'];
        var currentRevision = 0;
        if (hasSyncEnvelope) {
          final envelope = _stringKeyedMap(stored);
          if (envelope == null ||
              envelope.keys.toSet().difference(const {
                'revision',
                'payload',
              }).isNotEmpty ||
              envelope['revision'] is! int ||
              (envelope['revision'] as int) < 1 ||
              envelope['payload'] is! Map ||
              decode(exists: true, data: envelope['payload']).status !=
                  PlayerSyncDataStatus.valid) {
            throw const PlayerSyncWriteException(
              PlayerSyncWriteFailure.invalidStoredData,
            );
          }
          currentRevision = envelope['revision'] as int;
        }
        if (currentRevision != expectedRevision) {
          throw const PlayerSyncWriteException(
            PlayerSyncWriteFailure.staleRevision,
          );
        }
        final existingEnvelope = _stringKeyedMap(stored);
        if (existingEnvelope != null &&
            _deepEquals(existingEnvelope['payload'], payload)) {
          return PlayerSyncWriteResult(
            revision: currentRevision,
            didWrite: false,
          );
        }
        final nextRevision = currentRevision + 1;
        transaction.set(reference, {
          'sync': {'revision': nextRevision, 'payload': payload},
        }, SetOptions(merge: true));
        return PlayerSyncWriteResult(revision: nextRevision, didWrite: true);
      });
    } on PlayerSyncWriteException {
      rethrow;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const PlayerSyncWriteException(
          PlayerSyncWriteFailure.permissionDenied,
        );
      }
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.serviceFailure,
      );
    } on Exception {
      throw const PlayerSyncWriteException(
        PlayerSyncWriteFailure.serviceFailure,
      );
    }
  }

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
    } on PlayerSyncWriteException {
      rethrow;
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

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

bool _deepEquals(Object? first, Object? second) {
  if (first is Map && second is Map) {
    if (first.length != second.length ||
        !first.keys.toSet().containsAll(second.keys)) {
      return false;
    }
    for (final key in first.keys) {
      if (!_deepEquals(first[key], second[key])) return false;
    }
    return true;
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_deepEquals(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
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
