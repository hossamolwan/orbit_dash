import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class PlayerStatisticsStore {
  PlayerStatisticsStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const runsStartedKey = 'orbit_dash_stats_runs_started_v1';
  static const completedStagesKey = 'orbit_dash_stats_completed_stages_v1';
  static const shieldAbsorptionsKey = 'orbit_dash_stats_shield_absorptions_v1';
  static const lossesKey = 'orbit_dash_stats_losses_v1';

  final Future<SharedPreferences> Function() _loadPreferences;
  final Set<int> _completedStages = {};
  int _runsStarted = 0;
  int _shieldAbsorptions = 0;
  int _losses = 0;
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  int get runsStarted => _runsStarted;
  int get distinctStagesCompleted => _completedStages.length;
  int get shieldAbsorptions => _shieldAbsorptions;
  int get losses => _losses;
  Set<int> get completedStages => Set.unmodifiable(_completedStages);
  bool get isLoaded => _loaded;

  Future<void> flush() => _tail;

  Future<void> load({required int highestUnlockedStage}) =>
      _serialize(() async {
        final preferences = await _loadPreferences();
        _runsStarted = _readCounter(preferences, runsStartedKey);
        _shieldAbsorptions = _readCounter(preferences, shieldAbsorptionsKey);
        _losses = _readCounter(preferences, lossesKey);
        _completedStages
          ..clear()
          ..addAll(_readCompletedStages(preferences));
        // Unlocking stage N only follows completion of stages before N.
        for (var stage = 1; stage < highestUnlockedStage; stage++) {
          if (stage <= 5) _completedStages.add(stage);
        }
        _loaded = true;
        await preferences.setStringList(
          completedStagesKey,
          _completedStages.map((stage) => '$stage').toList()..sort(),
        );
      });

  Future<void> recordRunStarted() =>
      _increment(runsStartedKey, () => _runsStarted++);

  Future<void> recordShieldAbsorption() =>
      _increment(shieldAbsorptionsKey, () => _shieldAbsorptions++);

  Future<void> recordLoss() => _increment(lossesKey, () => _losses++);

  Future<void> recordStageCompleted(int stage) => _serialize(() async {
    if (stage < 1 || stage > 5) return;
    final preferences = await _loadPreferences();
    if (!_loaded) await _loadFrom(preferences);
    if (_completedStages.add(stage)) {
      await preferences.setStringList(
        completedStagesKey,
        _completedStages.map((stage) => '$stage').toList()..sort(),
      );
    }
  });

  Future<void> _increment(String key, void Function() increment) =>
      _serialize(() async {
        final preferences = await _loadPreferences();
        if (!_loaded) await _loadFrom(preferences);
        increment();
        await preferences.setInt(key, switch (key) {
          runsStartedKey => _runsStarted,
          shieldAbsorptionsKey => _shieldAbsorptions,
          _ => _losses,
        });
      });

  Future<void> _loadFrom(SharedPreferences preferences) async {
    _runsStarted = _readCounter(preferences, runsStartedKey);
    _shieldAbsorptions = _readCounter(preferences, shieldAbsorptionsKey);
    _losses = _readCounter(preferences, lossesKey);
    _completedStages
      ..clear()
      ..addAll(_readCompletedStages(preferences));
    _loaded = true;
  }

  int _readCounter(SharedPreferences preferences, String key) {
    try {
      return (preferences.getInt(key) ?? 0).clamp(0, 1 << 31);
    } on TypeError {
      return 0;
    }
  }

  Set<int> _readCompletedStages(SharedPreferences preferences) {
    try {
      return (preferences.getStringList(completedStagesKey) ?? const [])
          .map(int.tryParse)
          .whereType<int>()
          .where((stage) => stage >= 1 && stage <= 5)
          .toSet();
    } on TypeError {
      return {};
    }
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
}
