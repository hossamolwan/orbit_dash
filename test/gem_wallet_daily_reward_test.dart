import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/local_data_preflight.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('same date duplicate and distinct challenge IDs are handled', () async {
    final wallet = GemWallet();
    await wallet.load();
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      isTrue,
    );
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      isFalse,
    );
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'b',
        amount: 7,
      ),
      isTrue,
    );
    expect(wallet.balance, 12);
  });

  test('retains date identities across newer claims and replay', () async {
    final wallet = GemWallet();
    await wallet.load();
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      isTrue,
    );
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-02',
        challengeId: 'a',
        amount: 5,
      ),
      isTrue,
    );
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      isFalse,
    );
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'b',
        amount: 5,
      ),
      isTrue,
    );
    expect(wallet.balance, 15);
  });

  test(
    'prunes least recently updated dates at the deterministic limit',
    () async {
      final wallet = GemWallet();
      await wallet.load();
      for (var day = 1; day <= GemWallet.maxDailyRewardDates; day++) {
        final date = '2026-01-${day.toString().padLeft(2, '0')}';
        expect(
          await wallet.creditDailyRewardOnce(
            dateKey: date,
            challengeId: 'c',
            amount: 1,
          ),
          isTrue,
        );
      }
      // Touch the oldest date; it moves to the newest end of the retention window.
      expect(
        await wallet.creditDailyRewardOnce(
          dateKey: '2026-01-01',
          challengeId: 'd',
          amount: 1,
        ),
        isTrue,
      );
      expect(
        await wallet.creditDailyRewardOnce(
          dateKey: '2026-02-01',
          challengeId: 'c',
          amount: 1,
        ),
        isTrue,
      );
      expect(wallet.hasDailyReward('2026-01-01', 'c'), isTrue);
      expect(wallet.hasDailyReward('2026-01-02', 'c'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      final state = jsonDecode(
        prefs.getString(AccountScopedPreferences.localKey(GemWallet.stateKey))!,
      ) as Map<String, dynamic>;
      expect(
        (state['dailyRewardLedger'] as List),
        hasLength(GemWallet.maxDailyRewardDates),
      );
    },
  );

  test('migrates v2 data and rejects malformed v3 ledger safely', () async {
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.localKey(GemWallet.stateKey): jsonEncode({
        'version': 2,
        'balance': 8,
        'dailyRewardDate': '2026-10-01',
        'dailyRewardIds': ['a'],
        'purchases': <String, int>{},
      }),
    });
    final migrated = GemWallet();
    await migrated.load();
    expect(migrated.hasDailyReward('2026-10-01', 'a'), isTrue);

    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.localKey(GemWallet.stateKey): jsonEncode({
        'version': 3,
        'balance': 99,
        'dailyRewardLedger': [
          {
            'date': '2026-02-30',
            'ids': ['x'],
          },
        ],
        'purchases': <String, int>{},
      }),
    });
    final malformed = GemWallet();
    await malformed.load();
    expect(malformed.balance, 0);
    expect(malformed.hasDailyReward('2026-02-30', 'x'), isFalse);
  });

  test('wallet rejects legacy V1 invalid daily dates like preflight', () async {
    final malformed = jsonEncode({
      'version': 1,
      'balance': 12,
      'grants': ['daily:2026-02-30:collect_gems'],
      'purchases': <String, int>{},
    });
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.localKey(GemWallet.stateKey): malformed,
    });

    final preflight = await LocalDataPreflight(playerId: 'local').inspect();
    expect(
      preflight.domains[LocalDataDomain.gemWallet]!.presence,
      LocalDataPresence.invalid,
    );
    final wallet = GemWallet();
    await wallet.load();
    expect(wallet.balance, 0);
    expect(wallet.hasDailyReward('2026-02-30', 'collect_gems'), isFalse);
  });

  test(
    'V3 ledger preserves update order and both validators reject duplicates',
    () async {
      final key = AccountScopedPreferences.localKey(GemWallet.stateKey);
      final updateOrdered = jsonEncode({
        'version': 3,
        'balance': 10,
        // The older date was updated most recently, so it belongs last.
        'dailyRewardLedger': [
          {
            'date': '2026-10-02',
            'ids': ['a'],
          },
          {
            'date': '2026-10-01',
            'ids': ['a', 'b'],
          },
        ],
        'purchases': <String, int>{},
      });
      SharedPreferences.setMockInitialValues({key: updateOrdered});
      final wallet = GemWallet();
      await wallet.load();
      expect(wallet.balance, 10);
      expect(wallet.hasDailyReward('2026-10-01', 'b'), isTrue);
      var snapshot = await LocalDataPreflight(playerId: 'local').inspect();
      expect(
        snapshot.domains[LocalDataDomain.gemWallet]!.presence,
        LocalDataPresence.present,
      );

      final duplicateDates = jsonEncode({
        'version': 3,
        'balance': 10,
        'dailyRewardLedger': [
          {
            'date': '2026-10-02',
            'ids': ['a'],
          },
          {
            'date': '2026-10-02',
            'ids': ['b'],
          },
        ],
        'purchases': <String, int>{},
      });
      SharedPreferences.setMockInitialValues({key: duplicateDates});
      snapshot = await LocalDataPreflight(playerId: 'local').inspect();
      expect(
        snapshot.domains[LocalDataDomain.gemWallet]!.presence,
        LocalDataPresence.invalid,
      );
      final malformed = GemWallet();
      await malformed.load();
      expect(malformed.balance, 0);
      expect(malformed.hasDailyReward('2026-10-02', 'a'), isFalse);
    },
  );

  test('failed wallet write leaves reward retryable', () async {
    final prefs = await SharedPreferences.getInstance();
    var fail = false;
    final wallet = GemWallet(
      writeString: (preferences, key, value) async {
        if (fail) {
          fail = false;
          return false;
        }
        return preferences.setString(key, value);
      },
    );
    await wallet.load();
    fail = true;
    await expectLater(
      wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      throwsStateError,
    );
    expect(wallet.balance, 0);
    expect(wallet.hasDailyReward('2026-10-01', 'a'), isFalse);
    expect(
      await wallet.creditDailyRewardOnce(
        dateKey: '2026-10-01',
        challengeId: 'a',
        amount: 5,
      ),
      isTrue,
    );
    expect(wallet.balance, 5);
    expect(
      prefs.getString(AccountScopedPreferences.localKey(GemWallet.stateKey)),
      isNotNull,
    );
  });
}
