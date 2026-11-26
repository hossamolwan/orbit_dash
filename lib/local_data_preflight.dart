import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_scoped_preferences.dart';
import 'daily_challenges.dart' show isValidDailyChallengeEntry;
import 'local_data_validation.dart';
import 'skins.dart' show ShipSkinId, OrbitSkinId, CoreSkinId, TrailSkinId;

/// Availability of one locally persisted player-data domain.
enum LocalDataPresence { missing, present, invalid }

/// Stable identifiers for the local domains inspected before store loading.
enum LocalDataDomain {
  gemWallet,
  statistics,
  achievements,
  dailyChallenges,
  skin,
  appearance,
  survivalBestScore,
}

/// Safe validation metadata. This deliberately contains no persisted values.
class LocalDataDomainResult {
  LocalDataDomainResult({
    required this.presence,
    required Iterable<String> presentFields,
    required Iterable<String> missingFields,
    this.schemaVersion,
    this.issueCode,
  }) : presentFields = List.unmodifiable(presentFields),
       missingFields = List.unmodifiable(missingFields);

  final LocalDataPresence presence;
  final List<String> presentFields;
  final List<String> missingFields;
  final int? schemaVersion;
  final String? issueCode;
}

/// Separate, read-only report of known unscoped legacy preference keys.
class LegacyLocalDataInventory {
  LegacyLocalDataInventory({
    required this.presence,
    required Map<LocalDataDomain, LocalDataDomainResult> domains,
    required Iterable<String> detectedKeys,
  }) : domains = Map.unmodifiable(domains),
       detectedKeys = List.unmodifiable(detectedKeys);

  final LocalDataPresence presence;
  final Map<LocalDataDomain, LocalDataDomainResult> domains;
  final List<String> detectedKeys;
}

/// Immutable result associated with the UID supplied to the inspection.
class LocalDataInventorySnapshot {
  LocalDataInventorySnapshot({
    required this.playerId,
    required this.isComplete,
    required Map<LocalDataDomain, LocalDataDomainResult> domains,
    required this.legacy,
    this.failureCode,
  }) : domains = Map.unmodifiable(domains);

  final String playerId;
  final bool isComplete;
  final Map<LocalDataDomain, LocalDataDomainResult> domains;
  final LegacyLocalDataInventory legacy;
  final String? failureCode;
}

/// Performs non-mutating validation of local account-scoped player data.
///
/// The caller supplies the already-bound session UID. This service does not
/// read authentication state and does not call any gameplay store.
class LocalDataPreflight {
  LocalDataPreflight({
    required String playerId,
    Future<SharedPreferences> Function()? loadPreferences,
  }) : _keys = AccountScopedPreferences(playerId),
       _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  final AccountScopedPreferences _keys;
  final Future<SharedPreferences> Function() _loadPreferences;

  Future<LocalDataInventorySnapshot> inspect() async {
    final playerId = _keys.playerId;
    late final SharedPreferences preferences;
    try {
      preferences = await _loadPreferences();
    } catch (_) {
      return _failedSnapshot(playerId);
    }

    try {
      final scoped = <LocalDataDomain, LocalDataDomainResult>{};
      final legacy = <LocalDataDomain, LocalDataDomainResult>{};
      final legacyKeys = <String>[];
      for (final spec in _domainSpecs) {
        final scopedValues = {
          for (final field in spec.fields)
            field: preferences.get(_keys.key(field)),
        };
        scoped[spec.domain] = spec.validate(scopedValues);

        final legacyNames = _legacyNames[spec.domain] ?? const <String>[];
        final legacyValues = {
          for (final field in legacyNames) field: preferences.get(field),
        };
        final present = legacyValues.keys
            .where((key) => legacyValues[key] != null)
            .toList(growable: false);
        legacyKeys.addAll(present);
        if (present.isEmpty) {
          legacy[spec.domain] = _result(LocalDataPresence.missing);
        } else {
          final validationValues = Map<String, Object?>.from(legacyValues);
          if (spec.domain == LocalDataDomain.skin &&
              validationValues[SkinKeys.selected] == null) {
            validationValues[SkinKeys.selected] = legacyValues.entries
                .where((entry) => entry.value != null)
                .first
                .value;
          }
          final validation = spec.validate(validationValues);
          legacy[spec.domain] = LocalDataDomainResult(
            presence: validation.presence,
            presentFields: present,
            missingFields: legacyValues.keys
                .where((key) => legacyValues[key] == null)
                .toList(growable: false),
            schemaVersion: spec.domain == LocalDataDomain.skin
                ? (present.contains(SkinKeys.selected) ? 2 : 1)
                : validation.schemaVersion,
            issueCode: validation.issueCode,
          );
        }
      }

      final legacyPresence =
          legacy.values.any(
            (result) => result.presence == LocalDataPresence.invalid,
          )
          ? LocalDataPresence.invalid
          : legacyKeys.isEmpty
          ? LocalDataPresence.missing
          : LocalDataPresence.present;
      return LocalDataInventorySnapshot(
        playerId: playerId,
        isComplete: true,
        domains: scoped,
        legacy: LegacyLocalDataInventory(
          presence: legacyPresence,
          domains: legacy,
          detectedKeys: legacyKeys,
        ),
      );
    } catch (_) {
      return _failedSnapshot(playerId);
    }
  }
}

LocalDataInventorySnapshot _failedSnapshot(String playerId) =>
    LocalDataInventorySnapshot(
      playerId: playerId,
      isComplete: false,
      domains: {
        for (final domain in LocalDataDomain.values)
          domain: _result(LocalDataPresence.invalid, issue: 'readFailed'),
      },
      legacy: LegacyLocalDataInventory(
        presence: LocalDataPresence.invalid,
        domains: {
          for (final domain in LocalDataDomain.values)
            domain: _result(LocalDataPresence.invalid, issue: 'readFailed'),
        },
        detectedKeys: const [],
      ),
      failureCode: 'preferencesUnavailable',
    );

class _DomainSpec {
  const _DomainSpec(this.domain, this.fields, this.validate);
  final LocalDataDomain domain;
  final List<String> fields;
  final LocalDataDomainResult Function(Map<String, Object?> values) validate;
}

final _domainSpecs = <_DomainSpec>[
  _DomainSpec(LocalDataDomain.gemWallet, [GemKeys.state], _wallet),
  _DomainSpec(LocalDataDomain.statistics, StatsKeys.all, _statistics),
  _DomainSpec(LocalDataDomain.achievements, AchievementKeys.all, _achievements),
  _DomainSpec(LocalDataDomain.dailyChallenges, [DailyKeys.state], _daily),
  _DomainSpec(LocalDataDomain.skin, [SkinKeys.selected], _skin),
  _DomainSpec(LocalDataDomain.appearance, AppearanceKeys.all, _appearance),
  _DomainSpec(LocalDataDomain.survivalBestScore, [
    SurvivalKeys.best,
  ], _bestScore),
];

/// Public key constants let the audit and tests refer to the persisted schema
/// without constructing or loading a side-effecting gameplay store.
abstract final class GemKeys {
  static const state = 'orbit_dash_gem_wallet_v1';
}

abstract final class StatsKeys {
  static const runsStarted = 'orbit_dash_stats_runs_started_v1';
  static const completedStages = 'orbit_dash_stats_completed_stages_v1';
  static const shieldAbsorptions = 'orbit_dash_stats_shield_absorptions_v1';
  static const losses = 'orbit_dash_stats_losses_v1';
  static const bestRun = 'orbit_dash_stats_best_survival_run_v1';
  static const maxOrbit = 'orbit_dash_stats_max_orbit_v1';
  static const all = [
    runsStarted,
    completedStages,
    shieldAbsorptions,
    losses,
    bestRun,
    maxOrbit,
  ];
}

abstract final class AchievementKeys {
  static const totalGems = 'orbit_dash_total_gems';
  static const firstSteps = 'orbit_dash_achievement_first_steps';
  static const gemCollector = 'orbit_dash_achievement_gem_collector';
  static const savedByShield = 'orbit_dash_achievement_saved_by_shield';
  static const orbitExplorer = 'orbit_dash_achievement_orbit_explorer';
  static const orbitalMaster = 'orbit_dash_achievement_orbital_master';
  static const survivalOrbit3 = 'orbit_dash_achievement_survival_orbit_3';
  static const survivalOrbit4 = 'orbit_dash_achievement_survival_orbit_4';
  static const survivalOrbit5 = 'orbit_dash_achievement_survival_orbit_5';
  static const survivalRun10 = 'orbit_dash_achievement_survival_run_10';
  static const survivalRun25 = 'orbit_dash_achievement_survival_run_25';
  static const all = [
    totalGems,
    firstSteps,
    gemCollector,
    savedByShield,
    orbitExplorer,
    orbitalMaster,
    survivalOrbit3,
    survivalOrbit4,
    survivalOrbit5,
    survivalRun10,
    survivalRun25,
  ];
}

abstract final class DailyKeys {
  static const state = 'orbit_dash_daily_challenges_v1';
}

abstract final class SkinKeys {
  static const selected = 'orbit_dash_selected_skin_v2';
}

abstract final class AppearanceKeys {
  static const orbit = 'orbit_dash_selected_orbit_v1';
  static const core = 'orbit_dash_selected_core_v1';
  static const trail = 'orbit_dash_selected_trail_v1';
  static const all = [orbit, core, trail];
}

abstract final class SurvivalKeys {
  static const best = 'orbit_dash_survival_best';
}

final Map<LocalDataDomain, List<String>> _legacyNames = {
  LocalDataDomain.gemWallet: [GemKeys.state],
  LocalDataDomain.statistics: [...StatsKeys.all, 'orbit_dash_unlocked_stage'],
  LocalDataDomain.achievements: AchievementKeys.all,
  LocalDataDomain.dailyChallenges: [DailyKeys.state],
  LocalDataDomain.skin: [
    SkinKeys.selected,
    'orbit_dash_selected_skin_v1',
    'orbit_dash_selected_skin',
  ],
  LocalDataDomain.appearance: AppearanceKeys.all,
  LocalDataDomain.survivalBestScore: [SurvivalKeys.best, 'orbit_dash_best'],
};

LocalDataDomainResult _result(
  LocalDataPresence presence, {
  Iterable<String> present = const [],
  Iterable<String> missing = const [],
  int? version,
  String? issue,
}) => LocalDataDomainResult(
  presence: presence,
  presentFields: present,
  missingFields: missing,
  schemaVersion: version,
  issueCode: issue,
);

List<String> _present(Map<String, Object?> values) =>
    values.keys.where((key) => values[key] != null).toList(growable: false);

LocalDataDomainResult _keysResult(
  Map<String, Object?> values, {
  required bool Function(String key, Object value) valid,
  int? version,
}) {
  final found = _present(values);
  if (found.isEmpty) return _result(LocalDataPresence.missing);
  final invalid = found.any((key) => !valid(key, values[key]!));
  return _result(
    invalid ? LocalDataPresence.invalid : LocalDataPresence.present,
    present: found,
    missing: values.keys.where((key) => values[key] == null),
    version: version,
    issue: invalid ? 'invalidField' : null,
  );
}

LocalDataDomainResult _wallet(Map<String, Object?> values) {
  final key = GemKeys.state;
  final raw = values[key];
  if (raw == null) {
    return _result(LocalDataPresence.missing);
  }
  if (raw is! String) {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'wrongType',
    );
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        issue: 'invalidShape',
      );
    }
    final version = decoded['version'];
    if (version is! int || (version != 1 && version != 2)) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        version: version is int ? version : null,
        issue: 'unsupportedVersion',
      );
    }
    final balance = decoded['balance'];
    final purchases = decoded['purchases'];
    if (balance is! int ||
        balance < 0 ||
        balance > LocalDataValidation.maxPersistedCounter ||
        purchases is! Map<String, dynamic>) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        version: version,
        issue: 'invalidField',
      );
    }
    if (purchases.entries.any(
      (e) => e.key.isEmpty || e.value is! int || (e.value as int) < 0,
    )) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        version: version,
        issue: 'invalidPurchases',
      );
    }
    if (version == 1) {
      final grants = decoded['grants'];
      if (grants is! List || grants.any((value) => value is! String)) {
        return _result(
          LocalDataPresence.invalid,
          present: [key],
          version: version,
          issue: 'invalidLegacyGrants',
        );
      }
      final invalidDailyGrant = grants.cast<String>().any((grant) {
        final match = RegExp(r'^daily:(\d{4}-\d{2}-\d{2}):(.+)$')
            .firstMatch(grant);
        return match != null &&
            !LocalDataValidation.isValidCalendarDate(match[1]!);
      });
      if (invalidDailyGrant) {
        return _result(
          LocalDataPresence.invalid,
          present: [key],
          version: version,
          issue: 'invalidLegacyGrants',
        );
      }
    } else {
      final date = decoded['dailyRewardDate'];
      final ids = decoded['dailyRewardIds'];
      if ((date != null &&
              (date is! String ||
                  !LocalDataValidation.isValidCalendarDate(date))) ||
          ids is! List ||
          ids.any((value) => value is! String || value.isEmpty) ||
          (date == null && ids.isNotEmpty)) {
        return _result(
          LocalDataPresence.invalid,
          present: [key],
          version: version,
          issue: 'invalidRewardLedger',
        );
      }
    }
    return _result(LocalDataPresence.present, present: [key], version: version);
  } on FormatException {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'invalidJson',
    );
  } on TypeError {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'invalidShape',
    );
  }
}

LocalDataDomainResult _statistics(Map<String, Object?> values) => _keysResult(
  values,
  version: 1,
  valid: (key, value) {
    if (key == StatsKeys.completedStages) {
      return LocalDataValidation.parseCompletedStages(value) != null;
    }
    if (key == 'orbit_dash_unlocked_stage') {
      return value is int && value >= 1 && value <= 6;
    }
    if (key == StatsKeys.maxOrbit) {
      return LocalDataValidation.isValidMaxOrbit(value);
    }
    return LocalDataValidation.isValidCounter(value);
  },
);

LocalDataDomainResult _achievements(Map<String, Object?> values) => _keysResult(
  values,
  valid: (key, value) => key == AchievementKeys.totalGems
      ? value is int && value >= 0 && value <= (1 << 31)
      : value is bool,
);

LocalDataDomainResult _daily(Map<String, Object?> values) {
  final key = DailyKeys.state;
  final raw = values[key];
  if (raw == null) {
    return _result(LocalDataPresence.missing);
  }
  if (raw is! String) {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'wrongType',
    );
  }
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['date'] is! String ||
        (data['bonusGems'] != null && data['bonusGems'] is! int) ||
        data['challenges'] is! Map<String, dynamic>) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        issue: 'invalidShape',
      );
    }
    final date = data['date'] as String;
    final bonus = data['bonusGems'] as int? ?? 0;
    final challenges = data['challenges'] as Map<String, dynamic>;
    if (!LocalDataValidation.isValidCalendarDate(date) ||
        bonus < 0 ||
        bonus > LocalDataValidation.maxPersistedCounter) {
      return _result(
        LocalDataPresence.invalid,
        present: [key],
        issue: 'invalidField',
      );
    }
    for (final entry in challenges.entries) {
      if (!isValidDailyChallengeEntry(entry.key, entry.value)) {
        return _result(
          LocalDataPresence.invalid,
          present: [key],
          issue: 'invalidChallenge',
        );
      }
    }
    return _result(LocalDataPresence.present, present: [key], version: 1);
  } on FormatException {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'invalidJson',
    );
  } on TypeError {
    return _result(
      LocalDataPresence.invalid,
      present: [key],
      issue: 'invalidShape',
    );
  }
}

LocalDataDomainResult _skin(Map<String, Object?> values) => _keysResult(
  values,
  version: 2,
  valid: (key, value) =>
      value is String && ShipSkinId.values.any((id) => id.name == value),
);

LocalDataDomainResult _appearance(Map<String, Object?> values) => _keysResult(
  values,
  version: 1,
  valid: (key, value) {
    if (value is! String) {
      return false;
    }
    if (key == AppearanceKeys.orbit) {
      return OrbitSkinId.values.any((id) => id.name == value);
    }
    if (key == AppearanceKeys.core) {
      return CoreSkinId.values.any((id) => id.name == value);
    }
    if (key == AppearanceKeys.trail) {
      return TrailSkinId.values.any((id) => id.name == value);
    }
    return false;
  },
);

LocalDataDomainResult _bestScore(Map<String, Object?> values) => _keysResult(
  values,
  valid: (key, value) => value is int && value >= 0 && value <= (1 << 31),
);
