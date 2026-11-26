import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_scoped_preferences.dart';
import 'local_data_validation.dart';

class PlayerStatisticsStore {
  PlayerStatisticsStore({
    String playerId = AccountScopedPreferences.localPlayerId,
    Future<SharedPreferences> Function()? loadPreferences,
    Future<bool> Function(SharedPreferences, String, int)? writeInt,
    Future<bool> Function(SharedPreferences, String, List<String>?)?
    writeStringList,
  }) : _keys = AccountScopedPreferences(playerId),
       _loadPreferences = loadPreferences ?? SharedPreferences.getInstance,
       // Public injection names map to private backing fields.
       // ignore: prefer_initializing_formals
       _writeInt = writeInt,
       // ignore: prefer_initializing_formals
       _writeStringList = writeStringList;

  static const runsStartedKey = 'orbit_dash_stats_runs_started_v1';

  /// Legacy campaign history retained so existing saves remain readable.
  static const completedStagesKey = 'orbit_dash_stats_completed_stages_v1';
  static const shieldAbsorptionsKey = 'orbit_dash_stats_shield_absorptions_v1';
  static const lossesKey = 'orbit_dash_stats_losses_v1';
  static const bestRunKey = 'orbit_dash_stats_best_survival_run_v1';
  static const maxOrbitKey = 'orbit_dash_stats_max_orbit_v1';

  final Future<SharedPreferences> Function() _loadPreferences;
  final AccountScopedPreferences _keys;
  final Future<bool> Function(SharedPreferences, String, int)? _writeInt;
  final Future<bool> Function(SharedPreferences, String, List<String>?)?
  _writeStringList;
  final Set<int> _completedStages = {};
  int _runsStarted = 0;
  int _shieldAbsorptions = 0;
  int _losses = 0;
  int _bestRun = 0;
  int _maxOrbit = 2;
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  int get runsStarted => _runsStarted;
  int get distinctStagesCompleted => _completedStages.length;
  int get shieldAbsorptions => _shieldAbsorptions;
  int get losses => _losses;
  int get bestRun => _bestRun;
  int get maxOrbit => _maxOrbit;
  Set<int> get completedStages => Set.unmodifiable(_completedStages);
  bool get isLoaded => _loaded;

  Future<void> flush() => _tail;

  /// Loads Survival statistics and retains the saved campaign history.
  /// [highestUnlockedStage] remains optional for legacy callers only.
  Future<void> load({int? highestUnlockedStage}) => _serialize(() async {
    final preferences = await _loadPreferences();
    final runsStarted = _readCounter(preferences, runsStartedKey);
    final shieldAbsorptions = _readCounter(preferences, shieldAbsorptionsKey);
    final losses = _readCounter(preferences, lossesKey);
    final bestRun = _readCounter(preferences, bestRunKey);
    final maxOrbit = _readCounter(preferences, maxOrbitKey);
    final completedStages = _readCompletedStages(preferences);
    // Unlocking stage N only follows completion of stages before N.
    for (var stage = 1; stage < (highestUnlockedStage ?? 1); stage++) {
      if (stage <= 5) completedStages.add(stage);
    }
    await _saveCompletedStages(preferences, completedStages);
    _runsStarted = runsStarted;
    _shieldAbsorptions = shieldAbsorptions;
    _losses = losses;
    _bestRun = bestRun;
    _maxOrbit = maxOrbit;
    _completedStages
      ..clear()
      ..addAll(completedStages);
    _loaded = true;
  });

  Future<void> recordRunStarted() => _increment(runsStartedKey);

  Future<void> recordShieldAbsorption() => _increment(shieldAbsorptionsKey);

  Future<void> recordLoss() => _increment(lossesKey);

  Future<void> recordSurvivalRun(int score, int maxOrbit) =>
      _serialize(() async {
        final preferences = await _loadPreferences();
        if (!_loaded) await _loadFrom(preferences);
        final candidateBest = score > _bestRun ? score : _bestRun;
        final candidateOrbit = maxOrbit > _maxOrbit
            ? maxOrbit.clamp(2, 5)
            : _maxOrbit;
        // SharedPreferences has no transaction spanning these two keys. Keep
        // memory unchanged unless both writes succeed; retries remain monotonic
        // by incorporating any already-persisted higher value.
        final persistedBest = _readCounter(preferences, bestRunKey);
        final persistedOrbit = _readCounter(preferences, maxOrbitKey);
        final best = persistedBest > candidateBest
            ? persistedBest
            : candidateBest;
        final orbit = persistedOrbit > candidateOrbit
            ? persistedOrbit
            : candidateOrbit;
        await _setInt(preferences, bestRunKey, best);
        await _setInt(preferences, maxOrbitKey, orbit);
        _bestRun = best;
        _maxOrbit = orbit;
      });

  /// Writes legacy campaign history without affecting Survival progression.
  Future<void> recordStageCompleted(int stage) => _serialize(() async {
    if (stage < 1 || stage > 5) return;
    final preferences = await _loadPreferences();
    if (!_loaded) await _loadFrom(preferences);
    if (_completedStages.contains(stage)) return;
    final candidate = {..._completedStages, stage};
    await _saveCompletedStages(preferences, candidate);
    _completedStages
      ..clear()
      ..addAll(candidate);
  });

  Future<void> _increment(String key) => _serialize(() async {
    final preferences = await _loadPreferences();
    if (!_loaded) await _loadFrom(preferences);
    final value = switch (key) {
      runsStartedKey => _runsStarted,
      shieldAbsorptionsKey => _shieldAbsorptions,
      _ => _losses,
    };
    final next = value + 1;
    await _setInt(preferences, key, next);
    switch (key) {
      case runsStartedKey:
        _runsStarted = next;
      case shieldAbsorptionsKey:
        _shieldAbsorptions = next;
      default:
        _losses = next;
    }
  });

  Future<void> _setInt(
    SharedPreferences preferences,
    String key,
    int value,
  ) async {
    final saved =
        await (_writeInt?.call(preferences, _keys.key(key), value) ??
            preferences.setInt(_keys.key(key), value));
    if (!saved) throw StateError('Statistics save was not confirmed.');
  }

  Future<void> _saveCompletedStages(
    SharedPreferences preferences,
    Set<int> stages,
  ) async {
    final saved =
        await (_writeStringList?.call(
              preferences,
              _keys.key(completedStagesKey),
              stages.map((stage) => '$stage').toList()..sort(),
            ) ??
            preferences.setStringList(
              _keys.key(completedStagesKey),
              stages.map((stage) => '$stage').toList()..sort(),
            ));
    if (!saved) throw StateError('Statistics save was not confirmed.');
  }

  Future<void> _loadFrom(SharedPreferences preferences) async {
    final runsStarted = _readCounter(preferences, runsStartedKey);
    final shieldAbsorptions = _readCounter(preferences, shieldAbsorptionsKey);
    final losses = _readCounter(preferences, lossesKey);
    final bestRun = _readCounter(preferences, bestRunKey);
    final maxOrbit = _readCounter(preferences, maxOrbitKey);
    final completedStages = _readCompletedStages(preferences);
    _runsStarted = runsStarted;
    _shieldAbsorptions = shieldAbsorptions;
    _losses = losses;
    _bestRun = bestRun;
    _maxOrbit = maxOrbit;
    _completedStages
      ..clear()
      ..addAll(completedStages);
    _loaded = true;
  }

  int _readCounter(SharedPreferences preferences, String key) {
    final value = preferences.get(_keys.key(key));
    if (value == null) return key == maxOrbitKey ? 2 : 0;
    if (key == maxOrbitKey) {
      if (!LocalDataValidation.isValidMaxOrbit(value)) {
        throw StateError('Stored max orbit is invalid.');
      }
    } else if (!LocalDataValidation.isValidCounter(value)) {
      throw StateError('Stored statistics counter is invalid.');
    }
    return value as int;
  }

  Set<int> _readCompletedStages(SharedPreferences preferences) {
    final value = preferences.get(_keys.key(completedStagesKey));
    if (value == null) return {};
    final stages = LocalDataValidation.parseCompletedStages(value);
    if (stages == null) {
      throw StateError('Stored completed stages are invalid.');
    }
    return stages;
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
