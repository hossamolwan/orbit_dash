import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent local spendable currency and idempotency ledger.
/// Future real-money grants must be verified by a trusted backend.
class GemWallet {
  GemWallet({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const stateKey = 'orbit_dash_gem_wallet_v1';
  static const maxBalance = 1 << 31;
  static const maxRecentPickupIds = 256;

  final Future<SharedPreferences> Function() _loadPreferences;
  int _balance = 0;
  final Set<String> _recentPickupIds = {};
  final Set<String> _dailyRewardIds = {};
  String? _dailyRewardDate;
  final Map<String, int> _purchases = {};
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  int get balance => _balance;
  bool get isLoaded => _loaded;
  Set<String> get purchasedItemIds => Set.unmodifiable(_purchases.keys);
  bool owns(String itemId) => _purchases.containsKey(itemId);
  bool hasDailyReward(String dateKey, String challengeId) =>
      _dailyRewardDate == dateKey && _dailyRewardIds.contains(challengeId);
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
      _dailyRewardIds.clear();
      _dailyRewardDate = null;
      _purchases.clear();
      await _write(prefs, 0, null, {}, {});
    } else {
      _balance = state.balance;
      _dailyRewardDate = state.dailyRewardDate;
      _dailyRewardIds
        ..clear()
        ..addAll(state.dailyRewardIds);
      _purchases
        ..clear()
        ..addAll(state.purchases);
      if (state.version == 1) {
        await _write(
          prefs,
          _balance,
          _dailyRewardDate,
          _dailyRewardIds,
          _purchases,
        );
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
        await _write(
          prefs,
          nextBalance,
          _dailyRewardDate,
          _dailyRewardIds,
          _purchases,
        );
        _balance = nextBalance;
        _recentPickupIds.add(pickupId);
        if (_recentPickupIds.length > maxRecentPickupIds) {
          _recentPickupIds.remove(_recentPickupIds.first);
        }
        return true;
      });

  /// Persists daily reward idempotency for the current reward date only.
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
    if (_dailyRewardDate != dateKey) {
      _dailyRewardDate = dateKey;
      _dailyRewardIds.clear();
    }
    if (_dailyRewardIds.contains(challengeId)) return false;
    final nextBalance = _balance + amount;
    if (nextBalance > maxBalance) return false;
    final nextRewards = {..._dailyRewardIds, challengeId};
    await _write(prefs, nextBalance, dateKey, nextRewards, _purchases);
    _balance = nextBalance;
    _dailyRewardDate = dateKey;
    _dailyRewardIds
      ..clear()
      ..addAll(nextRewards);
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
        await _write(
          prefs,
          nextBalance,
          _dailyRewardDate,
          _dailyRewardIds,
          nextPurchases,
        );
        _balance = nextBalance;
        _purchases
          ..clear()
          ..addAll(nextPurchases);
        return true;
      });

  Future<void> _ensureLoaded(SharedPreferences prefs) async {
    final state = _decode(_readRaw(prefs));
    if (state == null) {
      await _write(prefs, 0, null, {}, {});
      _balance = 0;
      _dailyRewardDate = null;
      _dailyRewardIds.clear();
      _purchases.clear();
    } else {
      _balance = state.balance;
      _dailyRewardDate = state.dailyRewardDate;
      _dailyRewardIds
        ..clear()
        ..addAll(state.dailyRewardIds);
      _purchases
        ..clear()
        ..addAll(state.purchases);
    }
    _loaded = true;
  }

  String? _readRaw(SharedPreferences prefs) {
    try {
      return prefs.getString(stateKey);
    } on TypeError {
      return null;
    }
  }

  _WalletState? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          (data['version'] != 1 && data['version'] != 2) ||
          data['balance'] is! int ||
          data['purchases'] is! Map<String, dynamic>) {
        return null;
      }
      final balance = data['balance'] as int;
      final version = data['version'] as int;
      final purchaseValues = data['purchases'] as Map<String, dynamic>;
      String? rewardDate;
      Set<String> rewardIds = {};
      if (version == 1) {
        final oldGrants = data['grants'];
        if (oldGrants is! List || oldGrants.any((value) => value is! String)) {
          return null;
        }
        for (final value in oldGrants.cast<String>()) {
          final match = RegExp(r'^daily:(\d{4}-\d{2}-\d{2}):(.+)$')
              .firstMatch(value);
          if (match != null &&
              (rewardDate == null || match[1]!.compareTo(rewardDate) > 0)) {
            rewardDate = match[1];
            rewardIds = {match[2]!};
          } else if (match != null && match[1] == rewardDate) {
            rewardIds.add(match[2]!);
          }
        }
      } else {
        final rawDate = data['dailyRewardDate'];
        final rawIds = data['dailyRewardIds'];
        if ((rawDate != null && (rawDate is! String || !_validDate(rawDate))) ||
            rawIds is! List ||
            rawIds.any((value) => value is! String || value.isEmpty) ||
            (rawDate == null && rawIds.isNotEmpty)) {
          return null;
        }
        rewardDate = rawDate as String?;
        rewardIds = rawIds.cast<String>().toSet();
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
        rewardDate,
        rewardIds,
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
    String? dailyRewardDate,
    Set<String> dailyRewardIds,
    Map<String, int> purchases,
  ) async {
    final ok = await prefs.setString(
      stateKey,
      jsonEncode({
        'version': 2,
        'balance': balance,
        'dailyRewardDate': dailyRewardDate,
        'dailyRewardIds': dailyRewardIds.toList()..sort(),
        'purchases': purchases,
      }),
    );
    if (!ok) throw StateError('Wallet transaction was not persisted.');
  }

  static bool _validDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);

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

class _WalletState {
  const _WalletState(
    this.version,
    this.balance,
    this.dailyRewardDate,
    this.dailyRewardIds,
    this.purchases,
  );
  final int version;
  final int balance;
  final String? dailyRewardDate;
  final Set<String> dailyRewardIds;
  final Map<String, int> purchases;
}
