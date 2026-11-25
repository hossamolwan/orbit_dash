/// Pure Dart models for the player's account data.
///
/// These maps deliberately use only Dart values so they can be adapted to a
/// persistence format without coupling the domain models to a backend SDK.
class PlayerProfile {
  const PlayerProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final String uid;
  final String displayName;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  Map<String, Object?> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  factory PlayerProfile.fromMap(Map<String, Object?> map) => PlayerProfile(
    uid: _string(map['uid']),
    displayName: _string(map['displayName']),
    photoUrl: map['photoUrl'] is String ? map['photoUrl'] as String : null,
    createdAt: _dateTime(map['createdAt']) ?? _epoch,
    updatedAt: _dateTime(map['updatedAt']) ?? _epoch,
    schemaVersion: _integer(map['schemaVersion'], currentSchemaVersion),
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerProfile &&
      uid == other.uid &&
      displayName == other.displayName &&
      photoUrl == other.photoUrl &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
    uid,
    displayName,
    photoUrl,
    createdAt,
    updatedAt,
    schemaVersion,
  );
}

class PlayerProgress {
  const PlayerProgress({
    this.level = 1,
    this.xp = 0,
    this.totalXp = 0,
    this.highScore = 0,
    this.totalRuns = 0,
    this.totalDistance = 0,
  });

  final int level;
  final int xp;
  final int totalXp;
  final int highScore;
  final int totalRuns;
  final double totalDistance;

  Map<String, Object?> toMap() => {
    'level': level,
    'xp': xp,
    'totalXp': totalXp,
    'highScore': highScore,
    'totalRuns': totalRuns,
    'totalDistance': totalDistance,
  };

  factory PlayerProgress.fromMap(Map<String, Object?> map) => PlayerProgress(
    level: _positiveInteger(map['level'], 1),
    xp: _nonNegativeInteger(map['xp'], 0),
    totalXp: _nonNegativeInteger(map['totalXp'], 0),
    highScore: _nonNegativeInteger(map['highScore'], 0),
    totalRuns: _nonNegativeInteger(map['totalRuns'], 0),
    totalDistance: _nonNegativeDecimal(map['totalDistance'], 0),
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerProgress &&
      level == other.level &&
      xp == other.xp &&
      totalXp == other.totalXp &&
      highScore == other.highScore &&
      totalRuns == other.totalRuns &&
      totalDistance == other.totalDistance;

  @override
  int get hashCode =>
      Object.hash(level, xp, totalXp, highScore, totalRuns, totalDistance);
}

class PlayerInventory {
  PlayerInventory({
    Set<String> ownedSkinIds = const {},
    this.equippedSkinId,
    Set<String> ownedItemIds = const {},
  }) : ownedSkinIds = Set.unmodifiable(ownedSkinIds),
       ownedItemIds = Set.unmodifiable(ownedItemIds);

  final Set<String> ownedSkinIds;
  final String? equippedSkinId;
  final Set<String> ownedItemIds;

  Map<String, Object?> toMap() => {
    'ownedSkinIds': ownedSkinIds.toList()..sort(),
    'equippedSkinId': equippedSkinId,
    'ownedItemIds': ownedItemIds.toList()..sort(),
  };

  factory PlayerInventory.fromMap(Map<String, Object?> map) => PlayerInventory(
    ownedSkinIds: _stringSet(map['ownedSkinIds']),
    equippedSkinId: map['equippedSkinId'] is String
        ? map['equippedSkinId'] as String
        : null,
    ownedItemIds: _stringSet(map['ownedItemIds']),
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerInventory &&
      _setEquals(ownedSkinIds, other.ownedSkinIds) &&
      equippedSkinId == other.equippedSkinId &&
      _setEquals(ownedItemIds, other.ownedItemIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ownedSkinIds.toList()..sort()),
    equippedSkinId,
    Object.hashAll(ownedItemIds.toList()..sort()),
  );
}

class PlayerSettings {
  const PlayerSettings({
    this.soundEnabled = true,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    this.language = 'en',
  });

  final bool soundEnabled;
  final bool musicEnabled;
  final bool vibrationEnabled;
  final String language;

  Map<String, Object?> toMap() => {
    'soundEnabled': soundEnabled,
    'musicEnabled': musicEnabled,
    'vibrationEnabled': vibrationEnabled,
    'language': language,
  };

  factory PlayerSettings.fromMap(Map<String, Object?> map) => PlayerSettings(
    soundEnabled: _boolean(map['soundEnabled'], true),
    musicEnabled: _boolean(map['musicEnabled'], true),
    vibrationEnabled: _boolean(map['vibrationEnabled'], true),
    language: _string(map['language'], 'en'),
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerSettings &&
      soundEnabled == other.soundEnabled &&
      musicEnabled == other.musicEnabled &&
      vibrationEnabled == other.vibrationEnabled &&
      language == other.language;

  @override
  int get hashCode =>
      Object.hash(soundEnabled, musicEnabled, vibrationEnabled, language);
}

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int _integer(Object? value, int fallback) => value is int ? value : fallback;

int _positiveInteger(Object? value, int fallback) =>
    value is int && value > 0 ? value : fallback;

int _nonNegativeInteger(Object? value, int fallback) =>
    value is int && value >= 0 ? value : fallback;

double _nonNegativeDecimal(Object? value, double fallback) =>
    value is num && value >= 0 ? value.toDouble() : fallback;

bool _boolean(Object? value, bool fallback) =>
    value is bool ? value : fallback;

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Set<String> _stringSet(Object? value) {
  if (value is! Iterable) return {};
  return value.whereType<String>().toSet();
}

bool _setEquals<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);
