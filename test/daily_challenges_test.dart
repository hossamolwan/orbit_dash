import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/daily_challenges.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('daily challenge store', () {
    test(
      'keeps three challenges stable for a date and rotates next date',
      () async {
        var now = DateTime(2026, 10, 17, 23, 58);
        final store = DailyChallengeStore(now: () => now);
        await store.load();
        final firstIds = store.challenges
            .map((challenge) => challenge.definition.id)
            .toList();
        expect(firstIds, hasLength(3));

        now = DateTime(2026, 10, 17, 23, 59);
        await store.load();
        expect(
          store.challenges.map((challenge) => challenge.definition.id),
          firstIds,
        );
        now = DateTime(2026, 10, 18);
        await store.load();
        expect(store.challenges, hasLength(3));
        expect(
          store.challenges.map((challenge) => challenge.definition.id),
          isNot(firstIds),
        );
      },
    );

    test(
      'tracks every supported gameplay event and reloads progress',
      () async {
        var now = DateTime(2026, 10, 17);
        final encountered = <DailyChallengeEvent>{};
        for (var day = 0; day < 4; day++) {
          now = DateTime(2026, 10, 17 + day);
          final store = DailyChallengeStore(now: () => now);
          await store.load();
          for (final challenge in store.challenges) {
            final event = challenge.definition.event;
            encountered.add(event);
            await store.recordEvent(event);
            final restored = DailyChallengeStore(now: () => now);
            await restored.load();
            final progress = restored.challenges.firstWhere(
              (item) => item.definition.id == challenge.definition.id,
            );
            expect(progress.progress, 1);
          }
        }
        expect(encountered, DailyChallengeEvent.values.toSet());
      },
    );

    test('claims a completed reward once, including after reload', () async {
      final store = DailyChallengeStore(now: () => DateTime(2026, 10, 17));
      await store.load();
      final challenge = store.challenges.first;
      await store.recordEvent(
        challenge.definition.event,
        amount: challenge.definition.goal,
      );
      final reward = await store.claimReward(challenge.definition.id);
      expect(reward, challenge.definition.gemReward);
      expect(await store.claimReward(challenge.definition.id), isNull);

      final restored = DailyChallengeStore(now: () => DateTime(2026, 10, 17));
      await restored.load();
      expect(
        restored.challenges
            .firstWhere((item) => item.definition.id == challenge.definition.id)
            .rewardClaimed,
        isTrue,
      );
      expect(await restored.claimReward(challenge.definition.id), isNull);
      expect(restored.bonusGemsGranted, reward);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AchievementStore.totalGemsKey), isNull);
    });

    test(
      'wallet reward grant and challenge claim are idempotent across restart',
      () async {
        DateTime now() => DateTime(2026, 10, 17);
        final challenges = DailyChallengeStore(now: now);
        final wallet = GemWallet();
        await challenges.load();
        await wallet.load();
        final challenge = challenges.challenges.first;
        await challenges.recordEvent(
          challenge.definition.event,
          amount: challenge.definition.goal,
        );
        Future<bool> grant(int reward) async {
          final credited = await wallet.creditDailyRewardOnce(
            dateKey: challenges.dateKey,
            challengeId: challenge.definition.id,
            amount: reward,
          );
          return credited ||
              wallet.hasDailyReward(
                challenges.dateKey,
                challenge.definition.id,
              );
        }

        expect(
          await challenges.claimReward(challenge.definition.id, onGrant: grant),
          challenge.definition.gemReward,
        );
        expect(
          await challenges.claimReward(challenge.definition.id, onGrant: grant),
          isNull,
        );
        final reloadedWallet = GemWallet();
        final reloadedChallenges = DailyChallengeStore(now: now);
        await reloadedWallet.load();
        await reloadedChallenges.load();
        expect(reloadedWallet.balance, challenge.definition.gemReward);
        expect(
          await reloadedChallenges.claimReward(
            challenge.definition.id,
            onGrant: (reward) async {
              final credited = await reloadedWallet.creditDailyRewardOnce(
                dateKey: reloadedChallenges.dateKey,
                challengeId: challenge.definition.id,
                amount: reward,
              );
              return credited ||
                  reloadedWallet.hasDailyReward(
                    reloadedChallenges.dateKey,
                    challenge.definition.id,
                  );
            },
          ),
          isNull,
        );
        expect(reloadedWallet.balance, challenge.definition.gemReward);
      },
    );

    test(
      'retry after wallet save and failed claim save does not pay twice',
      () async {
        DateTime now() => DateTime(2026, 10, 17);
        var failNextClaimSave = true;
        final challengeStore = DailyChallengeStore(
          now: now,
          writeString: (preferences, key, value) async {
            if (key == DailyChallengeStore.stateKey && failNextClaimSave) {
              final data = jsonDecode(value) as Map<String, dynamic>;
              final states = data['challenges'] as Map<String, dynamic>;
              if (states.values.any(
                (item) => (item as Map<String, dynamic>)['claimed'] == true,
              )) {
                failNextClaimSave = false;
                return false;
              }
            }
            return preferences.setString(key, value);
          },
        );
        final wallet = GemWallet();
        await challengeStore.load();
        await wallet.load();
        final challenge = challengeStore.challenges.first;
        await challengeStore.recordEvent(
          challenge.definition.event,
          amount: challenge.definition.goal,
        );
        final date = challengeStore.dateKey;
        Future<bool> grant(GemWallet target, int reward) async {
          final credited = await target.creditDailyRewardOnce(
            dateKey: date,
            challengeId: challenge.definition.id,
            amount: reward,
          );
          return credited ||
              target.hasDailyReward(date, challenge.definition.id);
        }

        await expectLater(
          challengeStore.claimReward(
            challenge.definition.id,
            onGrant: (reward) => grant(wallet, reward),
          ),
          throwsStateError,
        );
        expect(wallet.balance, challenge.definition.gemReward);

        final restoredWallet = GemWallet();
        final restoredChallenges = DailyChallengeStore(now: now);
        await restoredWallet.load();
        await restoredChallenges.load();
        final restoredChallenge = restoredChallenges.challenges.firstWhere(
          (item) => item.definition.id == challenge.definition.id,
        );
        expect(restoredChallenge.rewardClaimed, isFalse);
        expect(
          await restoredChallenges.claimReward(
            challenge.definition.id,
            onGrant: (reward) => grant(restoredWallet, reward),
          ),
          challenge.definition.gemReward,
        );
        expect(restoredWallet.balance, challenge.definition.gemReward);
        expect(
          restoredChallenges.challenges
              .firstWhere(
                (item) => item.definition.id == challenge.definition.id,
              )
              .rewardClaimed,
          isTrue,
        );
      },
    );

    test(
      'invalid daily values fall back without changing unrelated data',
      () async {
        SharedPreferences.setMockInitialValues({
          DailyChallengeStore.stateKey: 42,
          'orbit_dash_unlocked_stage': 4,
          AchievementStore.totalGemsKey: 9,
        });
        final store = DailyChallengeStore(now: () => DateTime(2026, 10, 17));
        await store.load();
        expect(store.challenges, hasLength(3));
        expect(
          store.challenges.every((challenge) => challenge.progress == 0),
          isTrue,
        );
        expect(store.bonusGemsGranted, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('orbit_dash_unlocked_stage'), 4);
        expect(prefs.getInt(AchievementStore.totalGemsKey), 9);
      },
    );
  });
}
