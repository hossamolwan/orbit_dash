import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum AchievementId {
  firstSteps,
  gemCollector,
  savedByShield,
  orbitExplorer,
  orbitalMaster,
}

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.gemGoal,
  });

  final AchievementId id;
  final String title;
  final String description;
  final int? gemGoal;
}

const List<AchievementDefinition> achievementDefinitions = [
  AchievementDefinition(
    id: AchievementId.firstSteps,
    title: 'First Steps',
    description: 'Collect 10 gems in total.',
    gemGoal: 10,
  ),
  AchievementDefinition(
    id: AchievementId.gemCollector,
    title: 'Gem Collector',
    description: 'Collect 50 gems in total.',
    gemGoal: 50,
  ),
  AchievementDefinition(
    id: AchievementId.savedByShield,
    title: 'Saved by the Shield',
    description: 'Absorb an asteroid collision with your shield.',
  ),
  AchievementDefinition(
    id: AchievementId.orbitExplorer,
    title: 'Orbit Explorer',
    description: 'Unlock Stage 4.',
  ),
  AchievementDefinition(
    id: AchievementId.orbitalMaster,
    title: 'Orbital Master',
    description: 'Complete Stage 5 successfully.',
  ),
];

class AchievementStore {
  AchievementStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const totalGemsKey = 'orbit_dash_total_gems';

  static const Map<AchievementId, String> _keys = {
    AchievementId.firstSteps: 'orbit_dash_achievement_first_steps',
    AchievementId.gemCollector: 'orbit_dash_achievement_gem_collector',
    AchievementId.savedByShield: 'orbit_dash_achievement_saved_by_shield',
    AchievementId.orbitExplorer: 'orbit_dash_achievement_orbit_explorer',
    AchievementId.orbitalMaster: 'orbit_dash_achievement_orbital_master',
  };

  static String preferenceKeyFor(AchievementId id) => _keys[id]!;

  int _totalGems = 0;
  final Future<SharedPreferences> Function() _loadPreferences;
  final Set<AchievementId> _unlocked = {};
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  int get totalGems => _totalGems;
  bool get isLoaded => _loaded;
  bool isUnlocked(AchievementId id) => _unlocked.contains(id);

  Future<void> load() => _serialize(() async {
    final preferences = await _loadPreferences();
    await _loadFrom(preferences);
  });

  Future<List<AchievementId>> recordGem() => _serialize(() async {
    final preferences = await _loadPreferences();
    if (!_loaded) await _loadFrom(preferences);
    _totalGems++;
    await preferences.setInt(totalGemsKey, _totalGems);

    final newlyUnlocked = <AchievementId>[];
    if (_totalGems >= 10) {
      await _unlock(AchievementId.firstSteps, preferences, newlyUnlocked);
    }
    if (_totalGems >= 50) {
      await _unlock(AchievementId.gemCollector, preferences, newlyUnlocked);
    }
    return newlyUnlocked;
  });

  Future<List<AchievementId>> unlock(AchievementId id) => _serialize(() async {
    final preferences = await _loadPreferences();
    if (!_loaded) await _loadFrom(preferences);
    final newlyUnlocked = <AchievementId>[];
    await _unlock(id, preferences, newlyUnlocked);
    return newlyUnlocked;
  });

  Future<void> flush() => _tail;

  Future<void> _loadFrom(SharedPreferences preferences) async {
    _totalGems = _readInt(preferences, totalGemsKey).clamp(0, 1 << 31);
    _unlocked
      ..clear()
      ..addAll(
        AchievementId.values.where((id) => _readBool(preferences, _keys[id]!)),
      );
    _loaded = true;

    // Repair a partial save if the gem total was persisted before its badge.
    final ignoredUnlocks = <AchievementId>[];
    if (_totalGems >= 10) {
      await _unlock(AchievementId.firstSteps, preferences, ignoredUnlocks);
    }
    if (_totalGems >= 50) {
      await _unlock(AchievementId.gemCollector, preferences, ignoredUnlocks);
    }
  }

  Future<void> _unlock(
    AchievementId id,
    SharedPreferences preferences,
    List<AchievementId> newlyUnlocked,
  ) async {
    if (_unlocked.contains(id)) return;
    _unlocked.add(id);
    newlyUnlocked.add(id);
    await preferences.setBool(_keys[id]!, true);
  }

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  int _readInt(SharedPreferences preferences, String key) {
    try {
      return preferences.getInt(key) ?? 0;
    } on TypeError {
      return 0;
    }
  }

  bool _readBool(SharedPreferences preferences, String key) {
    try {
      return preferences.getBool(key) ?? false;
    } on TypeError {
      return false;
    }
  }
}
