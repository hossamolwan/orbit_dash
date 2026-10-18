import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DailyChallengeEvent {
  gemCollected,
  runStarted,
  shieldAbsorbed,
  stageCompleted,
}

class DailyChallengeDefinition {
  const DailyChallengeDefinition({
    required this.id,
    required this.description,
    required this.event,
    required this.goal,
    required this.gemReward,
  });

  final String id;
  final String description;
  final DailyChallengeEvent event;
  final int goal;
  final int gemReward;
}

class DailyChallenge {
  const DailyChallenge({
    required this.definition,
    required this.progress,
    required this.rewardClaimed,
  });

  final DailyChallengeDefinition definition;
  final int progress;
  final bool rewardClaimed;
  bool get isComplete => progress >= definition.goal;
}

const dailyChallengePool = <DailyChallengeDefinition>[
  DailyChallengeDefinition(
    id: 'collect_gems',
    description: 'Collect gems during a run.',
    event: DailyChallengeEvent.gemCollected,
    goal: 3,
    gemReward: 5,
  ),
  DailyChallengeDefinition(
    id: 'start_runs',
    description: 'Start stage attempts.',
    event: DailyChallengeEvent.runStarted,
    goal: 2,
    gemReward: 5,
  ),
  DailyChallengeDefinition(
    id: 'absorb_hazards',
    description: 'Absorb hazards with your shield.',
    event: DailyChallengeEvent.shieldAbsorbed,
    goal: 1,
    gemReward: 8,
  ),
  DailyChallengeDefinition(
    id: 'complete_stages',
    description: 'Complete stages.',
    event: DailyChallengeEvent.stageCompleted,
    goal: 1,
    gemReward: 8,
  ),
];

/// Stores one day's challenge progress and a separate ledger of bonus gems.
/// Bonus gems are deliberately separate from physical pickup totals.
class DailyChallengeStore {
  DailyChallengeStore({
    Future<SharedPreferences> Function()? loadPreferences,
    DateTime Function()? now,
    this._writeString,
  }) : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  static const stateKey = 'orbit_dash_daily_challenges_v1';

  final Future<SharedPreferences> Function() _loadPreferences;
  final DateTime Function() _now;
  final Future<bool> Function(SharedPreferences, String, String)? _writeString;
  List<DailyChallenge> _challenges = const [];
  String? _dateKey;
  int _bonusGemsGranted = 0;
  Future<void> _tail = Future<void>.value();

  List<DailyChallenge> get challenges => List.unmodifiable(_challenges);
  int get bonusGemsGranted => _bonusGemsGranted;
  String get dateKey => _dateKey ?? _keyForDate(_now());
  Future<void> flush() => _tail;

  Future<void> load() => _serialize(() async {
    final preferences = await _loadPreferences();
    final today = _keyForDate(_now());
    final saved = _readState(_readRawState(preferences));
    final bonusGems = saved?.bonusGemsGranted ?? 0;
    if (saved == null || saved.dateKey != today) {
      final challenges = _freshChallenges(today);
      await _save(
        preferences,
        dateKey: today,
        challenges: challenges,
        bonusGemsGranted: bonusGems,
      );
      _dateKey = today;
      _challenges = challenges;
    } else {
      _dateKey = today;
      _challenges = saved.challenges;
    }
    _bonusGemsGranted = bonusGems;
  });

  Future<void> recordEvent(DailyChallengeEvent event, {int amount = 1}) =>
      _serialize(() async {
        if (amount <= 0) return;
        final preferences = await _loadPreferences();
        await _ensureToday(preferences);
        var changed = false;
        final updated = _challenges
            .map((challenge) {
              if (challenge.definition.event != event || challenge.isComplete) {
                return challenge;
              }
              changed = true;
              return DailyChallenge(
                definition: challenge.definition,
                progress: (challenge.progress + amount).clamp(
                  0,
                  challenge.definition.goal,
                ),
                rewardClaimed: challenge.rewardClaimed,
              );
            })
            .toList(growable: false);
        if (changed) {
          await _save(
            preferences,
            dateKey: _dateKey!,
            challenges: updated,
            bonusGemsGranted: _bonusGemsGranted,
          );
          _challenges = updated;
        }
      });

  /// Returns the gem grant for a successful first claim, or null otherwise.
  Future<int?> claimReward(
    String challengeId, {
    Future<bool> Function(int reward)? onGrant,
  }) => _serialize(() async {
    final preferences = await _loadPreferences();
    await _ensureToday(preferences);
    final index = _challenges.indexWhere(
      (challenge) => challenge.definition.id == challengeId,
    );
    if (index < 0) return null;
    final challenge = _challenges[index];
    if (!challenge.isComplete || challenge.rewardClaimed) return null;

    final reward = challenge.definition.gemReward;
    // Grant first using an idempotent wallet transaction. If persisting the
    // claim then fails, a retry sees the same wallet transaction and is safe.
    if (onGrant != null && !await onGrant(reward)) return null;
    final updated = [..._challenges];
    updated[index] = DailyChallenge(
      definition: challenge.definition,
      progress: challenge.progress,
      rewardClaimed: true,
    );
    final updatedBonusGems = (_bonusGemsGranted + reward).clamp(0, 1 << 31);
    await _save(
      preferences,
      dateKey: _dateKey!,
      challenges: updated,
      bonusGemsGranted: updatedBonusGems,
    );
    _challenges = updated;
    _bonusGemsGranted = updatedBonusGems;
    return reward;
  });

  Future<void> _ensureToday(SharedPreferences preferences) async {
    final today = _keyForDate(_now());
    if (_dateKey == today) return;
    final saved = _readState(_readRawState(preferences));
    final bonusGems = saved?.bonusGemsGranted ?? _bonusGemsGranted;
    if (saved != null && saved.dateKey == today) {
      _dateKey = today;
      _challenges = saved.challenges;
      _bonusGemsGranted = bonusGems;
      return;
    }
    final challenges = _freshChallenges(today);
    await _save(
      preferences,
      dateKey: today,
      challenges: challenges,
      bonusGemsGranted: bonusGems,
    );
    _dateKey = today;
    _challenges = challenges;
    _bonusGemsGranted = bonusGems;
  }

  List<DailyChallenge> _freshChallenges(String date) {
    final offset = _dayOrdinal(date) % dailyChallengePool.length;
    return List.generate(3, (index) {
      final definition =
          dailyChallengePool[(offset + index) % dailyChallengePool.length];
      return DailyChallenge(
        definition: definition,
        progress: 0,
        rewardClaimed: false,
      );
    }, growable: false);
  }

  Future<void> _save(
    SharedPreferences preferences, {
    required String dateKey,
    required List<DailyChallenge> challenges,
    required int bonusGemsGranted,
  }) async {
    final value = jsonEncode({
      'date': dateKey,
      'bonusGems': bonusGemsGranted,
      'challenges': {
        for (final challenge in challenges)
          challenge.definition.id: {
            'progress': challenge.progress,
            'claimed': challenge.rewardClaimed,
          },
      },
    });
    final saved =
        await (_writeString?.call(preferences, stateKey, value) ??
            preferences.setString(stateKey, value));
    if (!saved) throw StateError('Daily challenge save was not confirmed.');
  }

  _SavedDailyState? _readState(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['date'] is! String ||
          (decoded['bonusGems'] != null && decoded['bonusGems'] is! int) ||
          decoded['challenges'] is! Map<String, dynamic>) {
        return null;
      }
      final date = decoded['date'] as String;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;
      final bonusGems = decoded['bonusGems'] as int? ?? 0;
      if (bonusGems < 0) return null;
      final values = decoded['challenges'] as Map<String, dynamic>;
      final selected = _freshChallenges(date);
      final result = <DailyChallenge>[];
      for (final challenge in selected) {
        final saved = values[challenge.definition.id];
        if (saved is! Map<String, dynamic> ||
            saved['progress'] is! int ||
            saved['claimed'] is! bool) {
          return null;
        }
        final progress = saved['progress'] as int;
        if (progress < 0 || progress > challenge.definition.goal) return null;
        final claimed = saved['claimed'] as bool;
        if (claimed && progress < challenge.definition.goal) return null;
        result.add(
          DailyChallenge(
            definition: challenge.definition,
            progress: progress,
            rewardClaimed: claimed,
          ),
        );
      }
      return _SavedDailyState(date, result, bonusGems);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String? _readRawState(SharedPreferences preferences) {
    try {
      return preferences.getString(stateKey);
    } on TypeError {
      return null;
    }
  }

  String _keyForDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  int _dayOrdinal(String date) {
    final parts = date.split('-').map(int.parse).toList(growable: false);
    return DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
    ).difference(DateTime.utc(1970, 1, 1)).inDays;
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

class _SavedDailyState {
  const _SavedDailyState(this.dateKey, this.challenges, this.bonusGemsGranted);

  final String dateKey;
  final List<DailyChallenge> challenges;
  final int bonusGemsGranted;
}
