import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/data/player/firestore_player_data_source.dart';
import 'package:orbit_dash/data/player/player_data_result.dart';
import 'package:orbit_dash/data/player/player_data_source.dart';
import 'package:orbit_dash/player_models.dart';

void main() {
  group('Firestore player document presence mapping', () {
    test('missing progress document stays missing', () {
      final result = playerDataResultFromDocument<PlayerProgress>(
        domain: 'progress',
        exists: false,
        data: null,
        decode: PlayerProgress.fromMap,
      );

      expect(result.presence, PlayerDataPresence.missing);
      expect(result.value, isNull);
    });

    test('present default progress document stays present', () {
      final result = playerDataResultFromDocument<PlayerProgress>(
        domain: 'progress',
        exists: true,
        data: const {},
        decode: PlayerProgress.fromMap,
      );

      expect(result.presence, PlayerDataPresence.present);
      expect(result.requireValue, const PlayerProgress());
    });

    test('missing inventory document stays missing', () {
      final result = playerDataResultFromDocument<PlayerInventory>(
        domain: 'inventory',
        exists: false,
        data: null,
        decode: PlayerInventory.fromMap,
      );

      expect(result.isMissing, isTrue);
      expect(result.value, isNull);
    });

    test('present empty inventory document stays present', () {
      final result = playerDataResultFromDocument<PlayerInventory>(
        domain: 'inventory',
        exists: true,
        data: const {},
        decode: PlayerInventory.fromMap,
      );

      expect(result.isPresent, isTrue);
      expect(result.requireValue.ownedSkinIds, isEmpty);
      expect(result.requireValue.ownedItemIds, isEmpty);
      expect(result.requireValue.equippedSkinId, isNull);
    });

    test('missing settings document stays missing', () {
      final result = playerDataResultFromDocument<PlayerSettings>(
        domain: 'settings',
        exists: false,
        data: null,
        decode: PlayerSettings.fromMap,
      );

      expect(result.isMissing, isTrue);
      expect(result.value, isNull);
    });

    test('present default settings document stays present', () {
      final result = playerDataResultFromDocument<PlayerSettings>(
        domain: 'settings',
        exists: true,
        data: const {},
        decode: PlayerSettings.fromMap,
      );

      expect(result.isPresent, isTrue);
      expect(result.requireValue, const PlayerSettings());
    });

    test('partial present progress keeps existing model defaults', () {
      final result = playerDataResultFromDocument<PlayerProgress>(
        domain: 'progress',
        exists: true,
        data: const {'highScore': 42},
        decode: PlayerProgress.fromMap,
      );

      expect(result.isPresent, isTrue);
      expect(result.requireValue, const PlayerProgress(highScore: 42));
    });

    test('present document without data follows access error policy', () {
      expect(
        () => playerDataResultFromDocument<PlayerSettings>(
          domain: 'settings',
          exists: true,
          data: null,
          decode: PlayerSettings.fromMap,
        ),
        throwsA(isA<PlayerDataAccessException>()),
      );
    });
  });
}
