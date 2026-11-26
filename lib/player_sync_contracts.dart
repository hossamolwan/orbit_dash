import 'package:orbit_dash/skins.dart';

import 'local_data_validation.dart';

/// A decoded sync document keeps absence distinct from a valid default value
/// and from data that must not be merged.
enum PlayerSyncDataStatus { missing, valid, invalid }

class PlayerSyncValidationIssue {
  const PlayerSyncValidationIssue(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

class PlayerSyncDecodeResult<T> {
  PlayerSyncDecodeResult._(this.status, this.value, this.issues);

  factory PlayerSyncDecodeResult.missing() =>
      PlayerSyncDecodeResult._(PlayerSyncDataStatus.missing, null, const []);

  factory PlayerSyncDecodeResult.valid(T value) =>
      PlayerSyncDecodeResult._(PlayerSyncDataStatus.valid, value, const []);

  factory PlayerSyncDecodeResult.invalid(
    Iterable<PlayerSyncValidationIssue> issues,
  ) => PlayerSyncDecodeResult._(
    PlayerSyncDataStatus.invalid,
    null,
    List.unmodifiable(issues),
  );

  final PlayerSyncDataStatus status;
  final T? value;
  final List<PlayerSyncValidationIssue> issues;
}

class PlayerSyncValidationException implements Exception {
  PlayerSyncValidationException(Iterable<PlayerSyncValidationIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<PlayerSyncValidationIssue> issues;

  @override
  String toString() =>
      'PlayerSyncValidationException: ${issues.join('; ')}';
}

/// Canonical subset of current Survival statistics intended for future sync.
/// XP, distance, campaign state, achievements, and daily challenges are
/// deliberately outside this v1 contract.
class PlayerSyncProgress {
  PlayerSyncProgress({
    required this.highScore,
    required this.runsStarted,
    required this.losses,
    required this.shieldAbsorptions,
    required this.maxOrbit,
  }) {
    final issues = _progressIssues({
      'schemaVersion': schemaVersion,
      'highScore': highScore,
      'runsStarted': runsStarted,
      'losses': losses,
      'shieldAbsorptions': shieldAbsorptions,
      'maxOrbit': maxOrbit,
    });
    if (issues.isNotEmpty) throw PlayerSyncValidationException(issues);
  }

  static const schemaVersion = 1;

  /// Best Survival score, projected from the maximum of the two existing
  /// local representations to avoid syncing a lower duplicate value.
  final int highScore;

  /// Number of Survival runs started; this is not a completed-run count.
  final int runsStarted;

  /// Number of runs ending in a collision.
  final int losses;

  /// Number of shield-absorbed collisions.
  final int shieldAbsorptions;

  /// Highest orbit count reached, in the current supported range 2 through 5.
  final int maxOrbit;

  /// Explicit defaults for a new player. A missing cloud document remains
  /// represented by [PlayerSyncDecodeResult.missing], not by these defaults.
  factory PlayerSyncProgress.defaults() => PlayerSyncProgress(
    highScore: 0,
    runsStarted: 0,
    losses: 0,
    shieldAbsorptions: 0,
    maxOrbit: 2,
  );

  Map<String, Object?> toMap() => {
    'schemaVersion': schemaVersion,
    'highScore': highScore,
    'runsStarted': runsStarted,
    'losses': losses,
    'shieldAbsorptions': shieldAbsorptions,
    'maxOrbit': maxOrbit,
  };

  static PlayerSyncDecodeResult<PlayerSyncProgress> decode({
    required bool exists,
    Object? data,
  }) {
    if (!exists) {
      return data == null
          ? PlayerSyncDecodeResult.missing()
          : PlayerSyncDecodeResult.invalid([
              const PlayerSyncValidationIssue(
                r'$document',
                'Data was supplied for a missing document.',
              ),
            ]);
    }
    final map = _stringKeyedMap(data);
    if (map == null) {
      return PlayerSyncDecodeResult.invalid([
        const PlayerSyncValidationIssue(r'$', 'Expected an object.'),
      ]);
    }
    final issues = _progressIssues(map);
    if (issues.isNotEmpty) return PlayerSyncDecodeResult.invalid(issues);
    return PlayerSyncDecodeResult.valid(
      PlayerSyncProgress(
        highScore: map['highScore'] as int,
        runsStarted: map['runsStarted'] as int,
        losses: map['losses'] as int,
        shieldAbsorptions: map['shieldAbsorptions'] as int,
        maxOrbit: map['maxOrbit'] as int,
      ),
    );
  }
}

enum CosmeticSlot { ship, orbit, core, trail }

/// The four independently equipped cosmetic slots.
class PlayerSyncEquippedCosmetics {
  const PlayerSyncEquippedCosmetics({
    required this.ship,
    required this.orbit,
    required this.core,
    required this.trail,
  });

  final String ship;
  final String orbit;
  final String core;
  final String trail;

  Map<String, String> toMap() => {
    CosmeticSlot.ship.name: ship,
    CosmeticSlot.orbit.name: orbit,
    CosmeticSlot.core.name: core,
    CosmeticSlot.trail.name: trail,
  };

  String forSlot(CosmeticSlot slot) => switch (slot) {
    CosmeticSlot.ship => ship,
    CosmeticSlot.orbit => orbit,
    CosmeticSlot.core => core,
    CosmeticSlot.trail => trail,
  };
}

/// Canonical cosmetic inventory. Default cosmetics are included in ownership
/// as baseline items, so every equipped ID must be present in [ownedItemIds].
class PlayerSyncInventory {
  PlayerSyncInventory({
    required Set<String> ownedItemIds,
    required this.equipped,
  }) : ownedItemIds = Set.unmodifiable(ownedItemIds) {
    final issues = _inventoryIssues(this.ownedItemIds, equipped);
    if (issues.isNotEmpty) throw PlayerSyncValidationException(issues);
  }

  static const schemaVersion = 1;

  static final defaultItemIds = Set<String>.unmodifiable({
    'ship.defaultSkin',
    OrbitSkinId.defaultOrbit.itemId,
    CoreSkinId.defaultCore.itemId,
    'trail.${TrailSkinId.classic.name}',
  });

  static final Map<String, CosmeticSlot> catalogSlots =
      Map.unmodifiable({
        for (final item in shipSkins) item.itemId: CosmeticSlot.ship,
        for (final item in orbitSkins) item.itemId: CosmeticSlot.orbit,
        for (final item in coreSkins) item.itemId: CosmeticSlot.core,
        for (final item in trailSkins) item.itemId: CosmeticSlot.trail,
      });

  final Set<String> ownedItemIds;
  final PlayerSyncEquippedCosmetics equipped;

  factory PlayerSyncInventory.defaults() => PlayerSyncInventory(
    ownedItemIds: defaultItemIds,
    equipped: PlayerSyncEquippedCosmetics(
      ship: 'ship.defaultSkin',
      orbit: OrbitSkinId.defaultOrbit.itemId,
      core: CoreSkinId.defaultCore.itemId,
      trail: 'trail.${TrailSkinId.classic.name}',
    ),
  );

  Map<String, Object?> toMap() => {
    'schemaVersion': schemaVersion,
    'ownedItemIds': ownedItemIds.toList()..sort(),
    'equipped': equipped.toMap(),
  };

  static PlayerSyncDecodeResult<PlayerSyncInventory> decode({
    required bool exists,
    Object? data,
  }) {
    if (!exists) {
      return data == null
          ? PlayerSyncDecodeResult.missing()
          : PlayerSyncDecodeResult.invalid([
              const PlayerSyncValidationIssue(
                r'$document',
                'Data was supplied for a missing document.',
              ),
            ]);
    }
    final map = _stringKeyedMap(data);
    if (map == null) {
      return PlayerSyncDecodeResult.invalid([
        const PlayerSyncValidationIssue(r'$', 'Expected an object.'),
      ]);
    }

    final issues = <PlayerSyncValidationIssue>[];
    _validateSchemaVersion(map, issues);
    _validateAllowedFields(
      map,
      const {'schemaVersion', 'ownedItemIds', 'equipped'},
      r'$',
      issues,
    );
    final rawOwned = map['ownedItemIds'];
    final owned = <String>{};
    if (rawOwned is! List) {
      issues.add(
        const PlayerSyncValidationIssue(
          'ownedItemIds',
          'Expected a list of canonical item IDs.',
        ),
      );
    } else {
      for (var index = 0; index < rawOwned.length; index++) {
        final item = rawOwned[index];
        if (item is! String || item.trim().isEmpty) {
          issues.add(
            PlayerSyncValidationIssue(
              'ownedItemIds[$index]',
              'Expected a non-empty string item ID.',
            ),
          );
        } else if (!owned.add(item)) {
          issues.add(
            PlayerSyncValidationIssue(
              'ownedItemIds[$index]',
              'Duplicate item ID "$item".',
            ),
          );
        }
      }
    }

    final rawEquipped = _stringKeyedMap(map['equipped']);
    PlayerSyncEquippedCosmetics? equipped;
    if (rawEquipped == null) {
      issues.add(
        const PlayerSyncValidationIssue('equipped', 'Expected an object.'),
      );
    } else {
      _validateAllowedFields(
        rawEquipped,
        CosmeticSlot.values.map((slot) => slot.name).toSet(),
        'equipped',
        issues,
      );
      final values = <String, String>{};
      for (final slot in CosmeticSlot.values) {
        final value = rawEquipped[slot.name];
        if (value is! String || value.trim().isEmpty) {
          issues.add(
            PlayerSyncValidationIssue(
              'equipped.${slot.name}',
              'Expected a non-empty canonical item ID.',
            ),
          );
        } else {
          values[slot.name] = value;
        }
      }
      for (final key in rawEquipped.keys) {
        if (!CosmeticSlot.values.any((slot) => slot.name == key)) {
          issues.add(
            PlayerSyncValidationIssue(
              'equipped.$key',
              'Unknown cosmetic slot.',
            ),
          );
        }
      }
      if (values.length == CosmeticSlot.values.length) {
        equipped = PlayerSyncEquippedCosmetics(
          ship: values[CosmeticSlot.ship.name]!,
          orbit: values[CosmeticSlot.orbit.name]!,
          core: values[CosmeticSlot.core.name]!,
          trail: values[CosmeticSlot.trail.name]!,
        );
      }
    }

    if (rawOwned is List) {
      issues.addAll(_ownedItemIssues(owned));
    }
    if (equipped != null && rawOwned is List) {
      issues.addAll(_equippedItemIssues(owned, equipped));
    }
    if (issues.isNotEmpty || equipped == null) {
      return PlayerSyncDecodeResult.invalid(issues);
    }
    return PlayerSyncDecodeResult.valid(
      PlayerSyncInventory(ownedItemIds: owned, equipped: equipped),
    );
  }
}

List<PlayerSyncValidationIssue> _progressIssues(Map<String, Object?> map) {
  final issues = <PlayerSyncValidationIssue>[];
  _validateSchemaVersion(map, issues);
  _validateAllowedFields(
    map,
    const {
      'schemaVersion',
      'highScore',
      'runsStarted',
      'losses',
      'shieldAbsorptions',
      'maxOrbit',
    },
    r'$',
    issues,
  );
  for (final field in [
    'highScore',
    'runsStarted',
    'losses',
    'shieldAbsorptions',
  ]) {
    final value = map[field];
    if (value is! int || value < 0 || value > LocalDataValidation.maxPersistedCounter) {
      issues.add(
        PlayerSyncValidationIssue(
          field,
          'Expected an integer from 0 to ${LocalDataValidation.maxPersistedCounter}.',
        ),
      );
    }
  }
  final orbit = map['maxOrbit'];
  if (orbit is! int || orbit < 2 || orbit > 5) {
    issues.add(
      const PlayerSyncValidationIssue(
        'maxOrbit',
        'Expected an integer from 2 to 5.',
      ),
    );
  }
  return issues;
}

void _validateSchemaVersion(
  Map<String, Object?> map,
  List<PlayerSyncValidationIssue> issues,
) {
  final version = map['schemaVersion'];
  if (version is! int || version != 1) {
    issues.add(
      const PlayerSyncValidationIssue(
        'schemaVersion',
        'Expected supported schema version 1.',
      ),
    );
  }
}

void _validateAllowedFields(
  Map<String, Object?> map,
  Set<String> allowed,
  String path,
  List<PlayerSyncValidationIssue> issues,
) {
  for (final field in map.keys) {
    if (!allowed.contains(field)) {
      issues.add(
        PlayerSyncValidationIssue(
          path == r'$' ? field : '$path.$field',
          'Field is not part of sync schema version 1.',
        ),
      );
    }
  }
}

List<PlayerSyncValidationIssue> _inventoryIssues(
  Set<String> owned,
  PlayerSyncEquippedCosmetics equipped,
) => [..._ownedItemIssues(owned), ..._equippedItemIssues(owned, equipped)];

List<PlayerSyncValidationIssue> _ownedItemIssues(Set<String> owned) {
  final issues = <PlayerSyncValidationIssue>[];
  for (final id in PlayerSyncInventory.defaultItemIds) {
    if (!owned.contains(id)) {
      issues.add(
        PlayerSyncValidationIssue(
          'ownedItemIds',
          'Baseline default item "$id" must be owned.',
        ),
      );
    }
  }
  for (final id in owned) {
    if (!PlayerSyncInventory.catalogSlots.containsKey(id)) {
      issues.add(
        PlayerSyncValidationIssue(
          'ownedItemIds',
          'Unknown cosmetic item ID "$id".',
        ),
      );
    }
  }
  return issues;
}

List<PlayerSyncValidationIssue> _equippedItemIssues(
  Set<String> owned,
  PlayerSyncEquippedCosmetics equipped,
) {
  final issues = <PlayerSyncValidationIssue>[];
  for (final slot in CosmeticSlot.values) {
    final id = equipped.forSlot(slot);
    final actualSlot = PlayerSyncInventory.catalogSlots[id];
    if (actualSlot == null) {
      issues.add(
        PlayerSyncValidationIssue(
          'equipped.${slot.name}',
          'Unknown cosmetic item ID "$id".',
        ),
      );
    } else if (actualSlot != slot) {
      issues.add(
        PlayerSyncValidationIssue(
          'equipped.${slot.name}',
          'Item "$id" belongs to ${actualSlot.name}, not ${slot.name}.',
        ),
      );
    }
    if (!owned.contains(id)) {
      issues.add(
        PlayerSyncValidationIssue(
          'equipped.${slot.name}',
          'Equipped item "$id" is not owned.',
        ),
      );
    }
  }
  return issues;
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
