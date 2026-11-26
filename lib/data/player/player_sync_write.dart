import '../../player_sync_contracts.dart';

/// Canonical cloud snapshot and optimistic concurrency revision for one domain.
class PlayerSyncCloudSnapshot<T> {
  const PlayerSyncCloudSnapshot({required this.revision, required this.value});

  final int revision;
  final T? value;

  bool get isMissing => value == null;
}

/// Result of an accepted cloud write.
class PlayerSyncWriteResult {
  const PlayerSyncWriteResult({required this.revision, required this.didWrite});

  final int revision;
  final bool didWrite;
}

enum PlayerSyncWriteFailure {
  invalidPayload,
  invalidRevision,
  staleRevision,
  invalidStoredData,
  permissionDenied,
  serviceFailure,
}

/// Backend-neutral write error. Firebase's internal messages are not exposed.
class PlayerSyncWriteException implements Exception {
  const PlayerSyncWriteException(this.failure);

  final PlayerSyncWriteFailure failure;

  @override
  String toString() => 'PlayerSyncWriteException($failure)';
}

/// Optional capability for versioned sync documents.
abstract interface class PlayerSyncDataSource {
  Future<PlayerSyncCloudSnapshot<PlayerSyncProgress>> loadSyncProgress(
    String uid,
  );

  Future<PlayerSyncCloudSnapshot<PlayerSyncInventory>> loadSyncInventory(
    String uid,
  );

  Future<PlayerSyncWriteResult> saveSyncProgress({
    required String uid,
    required PlayerSyncProgress progress,
    required int expectedRevision,
  });

  Future<PlayerSyncWriteResult> saveSyncInventory({
    required String uid,
    required PlayerSyncInventory inventory,
    required int expectedRevision,
  });
}

/// Repository capability for authenticated, revision-checked sync writes.
abstract interface class PlayerSyncRepository {
  Future<PlayerSyncCloudSnapshot<PlayerSyncProgress>> loadSyncProgress();

  Future<PlayerSyncCloudSnapshot<PlayerSyncInventory>> loadSyncInventory();

  Future<PlayerSyncWriteResult> saveSyncProgress({
    required PlayerSyncProgress progress,
    required int expectedRevision,
  });

  Future<PlayerSyncWriteResult> saveSyncInventory({
    required PlayerSyncInventory inventory,
    required int expectedRevision,
  });
}
