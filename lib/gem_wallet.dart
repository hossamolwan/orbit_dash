import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_scoped_preferences.dart';
import 'local_data_validation.dart';

/// Persistent local spendable currency and idempotency ledger.
/// Future real-money grants must be verified by a trusted backend.
class GemWallet {
  GemWallet({
    String playerId = AccountScopedPreferences.localPlayerId,
    Future<SharedPreferences> Function()? loadPreferences,
    this.writeString,
  }) : _keys = AccountScopedPreferences(playerId),
       _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const stateKey = 'orbit_dash_gem_wallet_v1';
  static const maxBalance = LocalDataValidation.maxPersistedCounter;
  static const maxRecentPickupIds = 256;
  static const maxDailyRewardDates = 30;
  static const maxDailyRewardIdsPerDate = 128;

  final Future<SharedPreferences> Function() _loadPreferences;
  final Future<bool> Function(SharedPreferences, String, String)? writeString;
  final AccountScopedPreferences _keys;
  int _balance = 0;
  final Set<String> _recentPickupIds = {};
  final Map<String, Set<String>> _dailyRewardLedger = {};
  final Map<String, int> _purchases = {};
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  int get balance => _balance;
  bool get isLoaded => _loaded;
  Set<String> get purchasedItemIds => Set.unmodifiable(_purchases.keys);
  bool owns(String itemId) => _purchases.containsKey(itemId);
  bool hasDailyReward(String dateKey, String challengeId) =>
      _dailyRewardLedger[dateKey]?.contains(challengeId) ?? false;
  Future<void> flush() => _tail;

  /// Starts a new short-lived pickup deduplication window.
  void beginPickupSession() => _recentPickupIds.clear();

  Future<void> load() => _serialize(() async {
    final prefs = await _loadPreferences();
    final raw = _readRaw(prefs);
    final state = _decode(raw);
    _recentPickupIds.clear();
    if (state == null) {
      _balance = 0;
      _dailyRewardLedger.clear();
      _purchases.clear();
      await _write(prefs, 0, {}, {});
    } else {
      _balance = state.balance;
      _dailyRewardLedger
        ..clear()
        ..addAll(_copyLedger(state.dailyRewardLedger));
      _purchases
        ..clear()
        ..addAll(state.purchases);
      if (state.version != 3) {
        await _write(prefs, _balance, _dailyRewardLedger, _purchases);
      }
    }
    _loaded = true;
  });

  /// Credits a unique physical pickup once in memory without saving its ID.
  Future<bool> creditPickupOnce(String pickupId, int amount) =>
      _serialize(() async {
        if (pickupId.trim().isEmpty || amount <= 0 || amount > maxBalance) {
          return false;
        }
        final prefs = await _loadPreferences();
        await _ensureLoaded(prefs);
        if (_recentPickupIds.contains(pickupId)) return false;
        final nextBalance = _balance + amount;
        if (nextBalance > maxBalance) return false;
        await _write(prefs, nextBalance, _dailyRewardLedger, _purchases);
        _balance = nextBalance;
        _recentPickupIds.add(pickupId);
        if (_recentPickupIds.length > maxRecentPickupIds) {
          _recentPickupIds.remove(_recentPickupIds.first);
        }
        return true;
      });

  /// Persists daily reward idempotency across a bounded window of dates.
  Future<bool> creditDailyRewardOnce({
    required String dateKey,
    required String challengeId,
    required int amount,
  }) => _serialize(() async {
    if (!_validDate(dateKey) ||
        challengeId.trim().isEmpty ||
        amount <= 0 ||
        amount > maxBalance) {
      return false;
    }
    final prefs = await _loadPreferences();
    await _ensureLoaded(prefs);
    if (hasDailyReward(dateKey, challengeId)) return false;
    if ((_dailyRewardLedger[dateKey]?.length ?? 0) >=
        maxDailyRewardIdsPerDate) {
      return false;
    }
    final nextBalance = _balance + amount;
    if (nextBalance > maxBalance) return false;
    final nextLedger = _copyLedger(_dailyRewardLedger)..remove(dateKey);
    nextLedger[dateKey] = {...?_dailyRewardLedger[dateKey], challengeId};
    while (nextLedger.length > maxDailyRewardDates) {
      nextLedger.remove(nextLedger.keys.first);
    }
    await _write(prefs, nextBalance, nextLedger, _purchases);
    _balance = nextBalance;
    _dailyRewardLedger
      ..clear()
      ..addAll(nextLedger);
    return true;
  });

  /// Payment and ownership share one saved state write.
  Future<bool> purchase({required String itemId, required int price}) =>
      _serialize(() async {
        if (itemId.trim().isEmpty || price <= 0 || price > maxBalance) {
          return false;
        }
        final prefs = await _loadPreferences();
        await _ensureLoaded(prefs);
        if (_purchases.containsKey(itemId) || _balance < price) return false;
        final nextBalance = _balance - price;
        final nextPurchases = {..._purchases, itemId: price};
        await _write(prefs, nextBalance, _dailyRewardLedger, nextPurchases);
        _balance = nextBalance;
        _purchases
          ..clear()
          ..addAll(nextPurchases);
        return true;
      });

  Future<void> _ensureLoaded(SharedPreferences prefs) async {
    final state = _decode(_readRaw(prefs));
    if (state == null) {
      await _write(prefs, 0, {}, {});
      _balance = 0;
      _dailyRewardLedger.clear();
      _purchases.clear();
    } else {
      _balance = state.balance;
      _dailyRewardLedger
        ..clear()
        ..addAll(_copyLedger(state.dailyRewardLedger));
      _purchases
        ..clear()
        ..addAll(state.purchases);
    }
    _loaded = true;
  }

  String? _readRaw(SharedPreferences prefs) {
    try {
      return prefs.getString(_keys.key(stateKey));
    } on TypeError {
      return null;
    }
  }

  _WalletState? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          (data['version'] != 1 &&
              data['version'] != 2 &&
              data['version'] != 3) ||
          data['balance'] is! int ||
          data['purchases'] is! Map<String, dynamic>) {
        return null;
      }
      final balance = data['balance'] as int;
      final version = data['version'] as int;
      final purchaseValues = data['purchases'] as Map<String, dynamic>;
      final rewardLedger = <String, Set<String>>{};
      if (version == 1) {
        final oldGrants = data['grants'];
        if (oldGrants is! List || oldGrants.any((value) => value is! String)) {
          return null;
        }
        for (final value in oldGrants.cast<String>()) {
          final match = RegExp(r'^daily:(\d{4}-\d{2}-\d{2}):(.+)$')
              .firstMatch(value);
          if (match != null &&
              !LocalDataValidation.isValidCalendarDate(match[1]!)) {
            return null;
          }
          if (match != null && !rewardLedger.containsKey(match[1])) {
            rewardLedger[match[1]!] = {match[2]!};
          } else if (match != null) {
            rewardLedger
                .putIfAbsent(match[1]!, () => <String>{})
                .add(match[2]!);
          }
        }
        for (final date in rewardLedger.keys.toList()) {
          rewardLedger[date] = rewardLedger[date]!
              .take(maxDailyRewardIdsPerDate)
              .toSet();
        }
        final retainedDates = rewardLedger.keys.toList()..sort();
        while (retainedDates.length > maxDailyRewardDates) {
          rewardLedger.remove(retainedDates.removeAt(0));
        }
      } else {
        if (version == 2) {
          final rawDate = data['dailyRewardDate'];
          final rawIds = data['dailyRewardIds'];
          if ((rawDate != null &&
                  (rawDate is! String || !_validDate(rawDate))) ||
              rawIds is! List ||
              rawIds.any((value) => value is! String || value.isEmpty) ||
              rawIds.length > maxDailyRewardIdsPerDate ||
              (rawDate == null && rawIds.isNotEmpty) ||
              (rawIds.cast<String>().toSet().length != rawIds.length)) {
            return null;
          }
          if (rawDate is String && rawIds.isNotEmpty) {
            rewardLedger[rawDate] = rawIds.cast<String>().toSet();
          }
        } else {
          final rawLedger = data['dailyRewardLedger'];
          if (rawLedger is! List || rawLedger.length > maxDailyRewardDates) {
            return null;
          }
          for (final item in rawLedger) {
            if (item is! Map<String, dynamic> ||
                item['date'] is! String ||
                !_validDate(item['date'] as String) ||
                item['ids'] is! List) {
              return null;
            }
            final date = item['date'] as String;
            final ids = item['ids'] as List;
            if (rewardLedger.containsKey(date) ||
                ids.length > maxDailyRewardIdsPerDate ||
                ids.any((id) => id is! String || id.isEmpty) ||
                ids.cast<String>().toSet().length != ids.length) {
              return null;
            }
            rewardLedger[date] = ids.cast<String>().toSet();
          }
        }
      }
      if (balance < 0 ||
          balance > maxBalance ||
          purchaseValues.entries.any(
            (e) => e.key.isEmpty || e.value is! int || (e.value as int) < 0,
          )) {
        return null;
      }
      return _WalletState(
        version,
        balance,
        rewardLedger,
        purchaseValues.map((k, v) => MapEntry(k, v as int)),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _write(
    SharedPreferences prefs,
    int balance,
    Map<String, Set<String>> dailyRewardLedger,
    Map<String, int> purchases,
  ) async {
    final key = _keys.key(stateKey);
    final value = jsonEncode({
      'version': 3,
      'balance': balance,
      'dailyRewardLedger': dailyRewardLedger.entries
          .map(
            (entry) => {'date': entry.key, 'ids': entry.value.toList()..sort()},
          )
          .toList(),
      'purchases': purchases,
    });
    final ok =
        await (writeString?.call(prefs, key, value) ??
            prefs.setString(key, value));
    if (!ok) throw StateError('Wallet transaction was not persisted.');
  }

  static bool _validDate(String value) =>
      LocalDataValidation.isValidCalendarDate(value);

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

Map<String, Set<String>> _copyLedger(Map<String, Set<String>> source) => {
  for (final entry in source.entries) entry.key: Set<String>.of(entry.value),
};

class _WalletState {
  const _WalletState(
    this.version,
    this.balance,
    this.dailyRewardLedger,
    this.purchases,
  );
  final int version;
  final int balance;
  final Map<String, Set<String>> dailyRewardLedger;
  final Map<String, int> purchases;
}
