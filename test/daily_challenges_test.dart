import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/daily_challenges.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('daily challenge store', () {
    test('keeps three challenges stable for a date and rotates next date', () async {
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
    });

    test('tracks every supported gameplay event and reloads progress', () async {
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
    });

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

      final restored = DailyChallengeStore(
        now: () => DateTime(2026, 10, 17),
      );
      await restored.load();
      expect(
        restored.challenges
            .firstWhere((item) => item.definition.id == challenge.definition.id)
            .rewardClaimed,
        isTrue,
      );
      expect(
        await restored.claimReward(challenge.definition.id),
        isNull,
      );
      expect(restored.bonusGemsGranted, reward);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AchievementStore.totalGemsKey), isNull);
    });

    test('invalid daily values fall back without changing unrelated data', () async {
      SharedPreferences.setMockInitialValues({
        DailyChallengeStore.stateKey: 42,
        'orbit_dash_unlocked_stage': 4,
        AchievementStore.totalGemsKey: 9,
      });
      final store = DailyChallengeStore(now: () => DateTime(2026, 10, 17));
      await store.load();
      expect(store.challenges, hasLength(3));
      expect(store.challenges.every((challenge) => challenge.progress == 0), isTrue);
      expect(store.bonusGemsGranted, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('orbit_dash_unlocked_stage'), 4);
      expect(prefs.getInt(AchievementStore.totalGemsKey), 9);
    });
  });
}
