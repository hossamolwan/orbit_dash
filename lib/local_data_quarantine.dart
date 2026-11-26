import 'package:shared_preferences/shared_preferences.dart';

import 'account_scoped_preferences.dart';
import 'local_data_preflight.dart';

/// Preserves the raw invalid wallet value without decoding or rewriting it.
abstract final class LocalDataQuarantine {
  static const walletRawKey = 'orbit_dash_quarantine_wallet_raw_v1';

  /// Returns true when a new value was written. Existing values stay intact.
  static Future<bool> preserveInvalidWallet({
    required SharedPreferences preferences,
    required String playerId,
    Future<bool> Function(SharedPreferences, String, Object)? writeValue,
  }) async {
    final accountKeys = AccountScopedPreferences(playerId);
    final sourceKey = accountKeys.key(GemKeys.state);
    final destinationKey = accountKeys.key(walletRawKey);
    if (!preferences.containsKey(sourceKey)) {
      throw StateError('Invalid wallet value disappeared before quarantine.');
    }
    final rawValue = preferences.get(sourceKey);
    if (!_isSupportedValue(rawValue)) {
      throw StateError('Invalid wallet value cannot be safely quarantined.');
    }
    final raw = rawValue!;
    if (preferences.containsKey(destinationKey)) {
      final existing = preferences.get(destinationKey);
      if (!_sameSupportedValue(existing, raw)) {
        throw StateError(
          'Existing wallet quarantine does not match the source.',
        );
      }
      return false;
    }
    final saved = await (writeValue ?? _writePreferenceValue)(
      preferences,
      destinationKey,
      raw,
    );
    if (!saved) throw StateError('Wallet quarantine was not persisted.');
    return true;
  }

  static bool _isSupportedValue(Object? value) =>
      value is String ||
      value is bool ||
      value is int ||
      value is double ||
      value is List<String>;

  static bool _sameSupportedValue(Object? first, Object? second) {
    if (!_isSupportedValue(first) || !_isSupportedValue(second)) return false;
    if (first is List<String> && second is List<String>) {
      if (first.length != second.length) return false;
      for (var index = 0; index < first.length; index++) {
        if (first[index] != second[index]) return false;
      }
      return true;
    }
    return first.runtimeType == second.runtimeType && first == second;
  }

  static Future<bool> _writePreferenceValue(
    SharedPreferences preferences,
    String key,
    Object value,
  ) => switch (value) {
    String value => preferences.setString(key, value),
    bool value => preferences.setBool(key, value),
    int value => preferences.setInt(key, value),
    double value => preferences.setDouble(key, value),
    List<String> value => preferences.setStringList(key, value),
    _ => Future<bool>.error(
      StateError('Unsupported SharedPreferences value for wallet quarantine.'),
    ),
  };
}
