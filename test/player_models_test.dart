import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/player_models.dart';

void main() {
  group('PlayerProfile', () {
    final createdAt = DateTime.utc(2025, 1, 2, 3, 4);
    final updatedAt = DateTime.utc(2025, 2, 3, 4, 5);

    test('round-trips values including a nullable photo URL', () {
      final profile = PlayerProfile(
        uid: 'uid-1',
        displayName: 'Orbit Pilot',
        photoUrl: null,
        createdAt: createdAt,
        updatedAt: updatedAt,
        schemaVersion: 2,
      );

      expect(PlayerProfile.fromMap(profile.toMap()), profile);
      expect(profile.toMap()['photoUrl'], isNull);
    });

    test('uses safe legacy defaults and rejects malformed values', () {
      final profile = PlayerProfile.fromMap({
        'uid': 42,
        'displayName': null,
        'photoUrl': 12,
        'createdAt': 'not a date',
        'updatedAt': DateTime.utc(2024),
        'schemaVersion': 'old',
      });

      expect(profile.uid, '');
      expect(profile.displayName, '');
      expect(profile.photoUrl, isNull);
      expect(profile.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(profile.updatedAt, DateTime.utc(2024));
      expect(profile.schemaVersion, PlayerProfile.currentSchemaVersion);
      expect(
        PlayerProfile.fromMap({}),
        PlayerProfile(
          uid: '',
          displayName: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    });
  });

  group('PlayerProgress', () {
    test('round-trips values and compares by value', () {
      const progress = PlayerProgress(
        level: 8,
        xp: 24,
        totalXp: 1024,
        highScore: 530,
        totalRuns: 40,
        totalDistance: 1290.5,
      );

      expect(PlayerProgress.fromMap(progress.toMap()), progress);
      expect(progress.hashCode, PlayerProgress.fromMap(progress.toMap()).hashCode);
    });

    test('defaults absent and malformed values safely', () {
      expect(PlayerProgress.fromMap({}), const PlayerProgress());
      expect(
        PlayerProgress.fromMap({
          'level': '2',
          'xp': 4.5,
          'totalXp': 100,
          'highScore': null,
          'totalRuns': -2,
          'totalDistance': 'many',
        }),
        const PlayerProgress(totalXp: 100),
      );
      expect(
        PlayerProgress.fromMap({'totalDistance': 3}).totalDistance,
        3.0,
      );
      expect(
        PlayerProgress.fromMap({
          'level': -1,
          'xp': -5,
          'totalDistance': -0.5,
        }),
        const PlayerProgress(),
      );
    });
  });

  group('PlayerInventory', () {
    test('round-trips unique IDs and compares sets independent of order', () {
      final inventory = PlayerInventory(
        ownedSkinIds: {'ship.solar', 'ship.emerald'},
        equippedSkinId: 'ship.solar',
        ownedItemIds: {'trail.aurora'},
      );

      expect(PlayerInventory.fromMap(inventory.toMap()), inventory);
      expect(
        inventory,
        PlayerInventory(
          ownedSkinIds: {'ship.emerald', 'ship.solar'},
          equippedSkinId: 'ship.solar',
          ownedItemIds: {'trail.aurora'},
        ),
      );
    });

    test('filters malformed IDs, tolerates missing fields and is immutable', () {
      final sourceIds = {'skin.one'};
      final inventory = PlayerInventory(ownedSkinIds: sourceIds);
      sourceIds.add('skin.two');

      expect(inventory.ownedSkinIds, {'skin.one'});
      expect(() => inventory.ownedSkinIds.add('skin.three'), throwsUnsupportedError);
      expect(
        PlayerInventory.fromMap({
          'ownedSkinIds': ['skin.one', null, 4, 'skin.one'],
          'equippedSkinId': false,
          'ownedItemIds': 'not-a-list',
        }),
        PlayerInventory(ownedSkinIds: {'skin.one'}),
      );
      expect(PlayerInventory.fromMap({}), PlayerInventory());
    });
  });

  group('PlayerSettings', () {
    test('round-trips values and compares by value', () {
      const settings = PlayerSettings(
        soundEnabled: false,
        musicEnabled: true,
        vibrationEnabled: false,
        language: 'ar',
      );

      expect(PlayerSettings.fromMap(settings.toMap()), settings);
    });

    test('uses existing audio defaults for absent or malformed preferences', () {
      expect(PlayerSettings.fromMap({}), const PlayerSettings());
      expect(
        PlayerSettings.fromMap({
          'soundEnabled': 'off',
          'musicEnabled': false,
          'vibrationEnabled': 0,
          'language': null,
        }),
        const PlayerSettings(musicEnabled: false),
      );
    });
  });
}
