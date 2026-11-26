// Test-only doubles for sealed Firestore SDK values are backed by Fake.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/firestore_player_data_source.dart';
import 'package:orbit_dash/data/player/player_sync_write.dart';
import 'package:orbit_dash/player_sync_contracts.dart';

void main() {
  group('Firestore sync writes', () {
    test(
      'progress uses a revisioned merge and preserves legacy fields',
      () async {
        final firestore = _MemoryFirestore()
          ..documents['players/p1/progress/data'] = {
            'legacyLevel': 7,
            'settingsLikeField': 'kept',
          };
        final source = FirestorePlayerDataSource(firestore: firestore);

        final result = await source.saveSyncProgress(
          uid: 'p1',
          progress: PlayerSyncProgress.defaults(),
          expectedRevision: 0,
        );

        expect(result.revision, 1);
        expect(firestore.lastWrittenPath, 'players/p1/progress/data');
        expect(firestore.lastMerge, isTrue);
        final stored = firestore.documents['players/p1/progress/data']!;
        expect(stored['legacyLevel'], 7);
        expect(stored['settingsLikeField'], 'kept');
        expect(stored['sync'], {
          'revision': 1,
          'payload': PlayerSyncProgress.defaults().toMap(),
        });
        expect(firestore.documents.keys, ['players/p1/progress/data']);
      },
    );

    test(
      'stale progress revision is rejected without changing the document',
      () async {
        final firestore = _MemoryFirestore();
        final source = FirestorePlayerDataSource(firestore: firestore);
        await source.saveSyncProgress(
          uid: 'p1',
          progress: PlayerSyncProgress.defaults(),
          expectedRevision: 0,
        );
        final before = _deepCopy(firestore.documents);

        await expectLater(
          source.saveSyncProgress(
            uid: 'p1',
            progress: PlayerSyncProgress.defaults(),
            expectedRevision: 0,
          ),
          throwsA(
            isA<PlayerSyncWriteException>().having(
              (error) => error.failure,
              'failure',
              PlayerSyncWriteFailure.staleRevision,
            ),
          ),
        );
        expect(firestore.documents, before);
      },
    );

    test(
      'identical payload is a successful no-op at the current revision',
      () async {
        final firestore = _MemoryFirestore();
        final source = FirestorePlayerDataSource(firestore: firestore);
        final payload = PlayerSyncProgress.defaults();
        await source.saveSyncProgress(
          uid: 'p1',
          progress: payload,
          expectedRevision: 0,
        );
        final writesBefore = firestore.writeCount;

        final result = await source.saveSyncProgress(
          uid: 'p1',
          progress: payload,
          expectedRevision: 1,
        );

        expect(result.revision, 1);
        expect(result.didWrite, isFalse);
        expect(firestore.writeCount, writesBefore);
      },
    );

    test(
      'negative expected revision is rejected before cloud access',
      () async {
        final firestore = _MemoryFirestore();
        final source = FirestorePlayerDataSource(firestore: firestore);

        await expectLater(
          source.saveSyncInventory(
            uid: 'p1',
            inventory: PlayerSyncInventory.defaults(),
            expectedRevision: -1,
          ),
          throwsA(
            isA<PlayerSyncWriteException>().having(
              (error) => error.failure,
              'failure',
              PlayerSyncWriteFailure.invalidRevision,
            ),
          ),
        );
        expect(firestore.transactionCount, 0);
      },
    );

    test('inventory has an independent document and revision', () async {
      final firestore = _MemoryFirestore()
        ..documents['players/p1'] = {'uid': 'p1', 'displayName': 'Pilot'}
        ..documents['players/p1/settings/data'] = {'musicEnabled': false};
      final beforeOtherDomains = {
        'players/p1': _copyMap(firestore.documents['players/p1']!),
        'players/p1/settings/data': _copyMap(
          firestore.documents['players/p1/settings/data']!,
        ),
      };
      final source = FirestorePlayerDataSource(firestore: firestore);
      await source.saveSyncProgress(
        uid: 'p1',
        progress: PlayerSyncProgress.defaults(),
        expectedRevision: 0,
      );
      final inventory = PlayerSyncInventory.defaults();
      final result = await source.saveSyncInventory(
        uid: 'p1',
        inventory: inventory,
        expectedRevision: 0,
      );

      expect(result.revision, 1);
      expect(firestore.documents.keys.toSet(), {
        'players/p1',
        'players/p1/settings/data',
        'players/p1/progress/data',
        'players/p1/inventory/data',
      });
      expect(firestore.documents['players/p1/inventory/data']!['sync'], {
        'revision': 1,
        'payload': inventory.toMap(),
      });
      expect(
        firestore.documents['players/p1/progress/data']!['sync']['revision'],
        1,
      );
      expect(
        firestore.documents['players/p1'],
        beforeOtherDomains['players/p1'],
      );
      expect(
        firestore.documents['players/p1/settings/data'],
        beforeOtherDomains['players/p1/settings/data'],
      );
    });

    test(
      'loads canonical payload and revision; absent sync starts at zero',
      () async {
        final firestore = _MemoryFirestore()
          ..documents['players/p1/progress/data'] = {'oldField': true}
          ..documents['players/p1/inventory/data'] = {
            'sync': {
              'revision': 4,
              'payload': PlayerSyncInventory.defaults().toMap(),
            },
          };
        final source = FirestorePlayerDataSource(firestore: firestore);

        final progress = await source.loadSyncProgress('p1');
        final inventory = await source.loadSyncInventory('p1');

        expect(progress.isMissing, isTrue);
        expect(progress.revision, 0);
        expect(inventory.revision, 4);
        expect(
          inventory.value!.toMap(),
          PlayerSyncInventory.defaults().toMap(),
        );
      },
    );

    test('malformed stored envelope is rejected and not overwritten', () async {
      final firestore = _MemoryFirestore()
        ..documents['players/p1/progress/data'] = {
          'sync': {
            'revision': 1,
            'payload': {'schemaVersion': 99},
          },
        };
      final before = _deepCopy(firestore.documents);
      final source = FirestorePlayerDataSource(firestore: firestore);

      await expectLater(
        source.saveSyncProgress(
          uid: 'p1',
          progress: PlayerSyncProgress.defaults(),
          expectedRevision: 1,
        ),
        throwsA(
          isA<PlayerSyncWriteException>().having(
            (error) => error.failure,
            'failure',
            PlayerSyncWriteFailure.invalidStoredData,
          ),
        ),
      );
      expect(firestore.documents, before);
    });
  });
}

Map<String, Map<String, dynamic>> _deepCopy(
  Map<String, Map<String, dynamic>> source,
) => {for (final entry in source.entries) entry.key: _copyMap(entry.value)};

Map<String, dynamic> _copyMap(Map<String, dynamic> source) => {
  for (final entry in source.entries)
    entry.key: entry.value is Map
        ? _copyMap(Map<String, dynamic>.from(entry.value as Map))
        : entry.value,
};

class _MemoryFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  String? lastWrittenPath;
  bool? lastMerge;
  int transactionCount = 0;
  int writeCount = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _MemoryCollectionReference(this, collectionPath);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    transactionCount++;
    return transactionHandler(_MemoryTransaction(this));
  }
}

class _MemoryCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _MemoryCollectionReference(this.firestore, this.path);

  @override
  final _MemoryFirestore firestore;
  @override
  final String path;

  @override
  String get id => path.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _MemoryDocumentReference(firestore, '${this.path}/${path ?? ''}');
}

class _MemoryDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _MemoryDocumentReference(this.firestore, this.path);

  @override
  final _MemoryFirestore firestore;
  @override
  final String path;

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _MemoryCollectionReference(firestore, '$path/$collectionPath');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _MemoryDocumentSnapshot(this, firestore.documents[path]);
}

class _MemoryDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _MemoryDocumentSnapshot(this.reference, this._value);

  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? _value;

  @override
  String get id => reference.id;

  @override
  bool get exists => _value != null;

  @override
  Map<String, dynamic>? data() => _value;
}

class _MemoryTransaction extends Fake implements Transaction {
  _MemoryTransaction(this.firestore);

  final _MemoryFirestore firestore;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async => _MemoryDocumentSnapshot(
    documentReference as DocumentReference<Map<String, dynamic>>,
    firestore.documents[documentReference.path],
  ) as DocumentSnapshot<T>;

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    firestore.writeCount++;
    final path = documentReference.path;
    firestore.lastWrittenPath = path;
    firestore.lastMerge = options?.merge;
    final incoming = Map<String, dynamic>.from(data as Map);
    if (options?.merge == true && firestore.documents[path] != null) {
      firestore.documents[path] = _merge(firestore.documents[path]!, incoming);
    } else {
      firestore.documents[path] = incoming;
    }
    return this;
  }
}

Map<String, dynamic> _merge(
  Map<String, dynamic> original,
  Map<String, dynamic> update,
) {
  final result = _copyMap(original);
  for (final entry in update.entries) {
    final existing = result[entry.key];
    final next = entry.value;
    result[entry.key] = existing is Map && next is Map
        ? _merge(
            Map<String, dynamic>.from(existing),
            Map<String, dynamic>.from(next),
          )
        : next;
  }
  return result;
}
