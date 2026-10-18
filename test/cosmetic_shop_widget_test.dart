import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shop lists standard cosmetics before premium in every tab', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: _ShopAudio(), testDriver: driver),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();

    List<String> orderedOptionKeys<T>(
      Iterable<T> skins,
      String Function(T) id,
      CosmeticRarity Function(T) rarity,
      String prefix,
    ) => [
      ...skins
          .where((skin) => rarity(skin) == CosmeticRarity.standard)
          .map((skin) => '$prefix-option-${id(skin)}'),
      ...skins
          .where((skin) => rarity(skin) == CosmeticRarity.premium)
          .map((skin) => '$prefix-option-${id(skin)}'),
    ];

    Future<void> expectCategoryOrder(
      String category,
      String prefix,
      List<String> expected,
    ) async {
      final tab = find.byKey(ValueKey('cosmetic-tab-$category'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      final actual = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .map((button) => button.key)
          .whereType<ValueKey<String>>()
          .map((key) => key.value)
          .where((key) => key.startsWith('$prefix-option-'))
          .toList();
      expect(actual, expected, reason: '$category tab item order');
    }

    await expectCategoryOrder(
      'ship',
      'skin',
      orderedOptionKeys(
        shipSkins,
        (skin) => skin.id.name,
        (skin) => skin.rarity,
        'skin',
      ),
    );
    await expectCategoryOrder(
      'orbit',
      'orbit',
      orderedOptionKeys(
        orbitSkins,
        (skin) => skin.id.name,
        (skin) => skin.rarity,
        'orbit',
      ),
    );
    await expectCategoryOrder(
      'core',
      'core',
      orderedOptionKeys(
        coreSkins,
        (skin) => skin.id.name,
        (skin) => skin.rarity,
        'core',
      ),
    );
    await expectCategoryOrder(
      'trail',
      'trail',
      orderedOptionKeys(
        trailSkins,
        (skin) => skin.id.name,
        (skin) => skin.rarity,
        'trail',
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shop buys and equips orbit and core cosmetics', (tester) async {
    SharedPreferences.setMockInitialValues({
      GemWallet.stateKey: '{"version":2,"balance":300,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: _ShopAudio(), testDriver: driver),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();

    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();
    expect(find.text('SHIP'), findsOneWidget);
    expect(find.text('ORBIT'), findsOneWidget);
    expect(find.text('CORE'), findsOneWidget);
    expect(find.text('TRAIL'), findsOneWidget);
    expect(find.text('SHIP SKINS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('orbit-option-defaultOrbit')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('core-option-defaultCore')), findsNothing);

    final orbitTab = find.byKey(const ValueKey('cosmetic-tab-orbit'));
    await tester.ensureVisible(orbitTab);
    await tester.tap(orbitTab);
    await tester.pumpAndSettle();
    expect(find.text('ORBIT SKINS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('orbit-option-defaultOrbit')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('skin-option-defaultSkin')), findsNothing);
    expect(find.byKey(const ValueKey('core-option-defaultCore')), findsNothing);

    final aurora = find.byKey(const ValueKey('orbit-option-aurora'));
    await tester.ensureVisible(aurora);
    await tester.tap(aurora);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 240);
    expect(driver.selectedOrbit, OrbitSkinId.defaultOrbit);
    await tester.ensureVisible(aurora);
    await tester.tap(aurora);
    await tester.pumpAndSettle();
    expect(driver.selectedOrbit, OrbitSkinId.aurora);

    final shipTab = find.byKey(const ValueKey('cosmetic-tab-ship'));
    await tester.ensureVisible(shipTab);
    await tester.tap(shipTab);
    await tester.pumpAndSettle();
    expect(driver.selectedSkin, ShipSkinId.defaultSkin);
    expect(driver.selectedOrbit, OrbitSkinId.aurora);
    expect(driver.walletBalance, 240);
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsNothing);

    final coreTab = find.byKey(const ValueKey('cosmetic-tab-core'));
    await tester.ensureVisible(coreTab);
    await tester.tap(coreTab);
    await tester.pumpAndSettle();
    expect(find.text('CORE SKINS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('core-option-defaultCore')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsNothing);

    final crimson = find.byKey(const ValueKey('core-option-crimson'));
    await tester.ensureVisible(crimson);
    await tester.tap(crimson);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 165);
    expect(driver.selectedCore, CoreSkinId.defaultCore);
    await tester.ensureVisible(crimson);
    await tester.tap(crimson);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 165);
    expect(driver.selectedCore, CoreSkinId.crimson);
    expect(
      find.byKey(const ValueKey('orbit-style-aurora-crimson')),
      findsOneWidget,
    );
    await driver.flushProgress();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(AppearanceStore.selectedOrbitKey), 'aurora');
    expect(preferences.getString(AppearanceStore.selectedCoreKey), 'crimson');
    final restoredWallet = GemWallet();
    await restoredWallet.load();
    expect(restoredWallet.balance, 165);
    expect(restoredWallet.owns('orbit.aurora'), isTrue);
    expect(restoredWallet.owns('core.crimson'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trail purchases, equips and persists independently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      GemWallet.stateKey: '{"version":2,"balance":450,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{"ship.emerald":40,"orbit.aurora":60,"core.crimson":75}}',
      SkinStore.selectedSkinKey: 'emerald',
      AppearanceStore.selectedOrbitKey: 'aurora',
      AppearanceStore.selectedCoreKey: 'crimson',
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: _ShopAudio(), testDriver: driver),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();
    final trailTab = find.byKey(const ValueKey('cosmetic-tab-trail'));
    await tester.ensureVisible(trailTab);
    await tester.tap(trailTab);
    await tester.pumpAndSettle();
    expect(find.text('TRAIL SKINS'), findsOneWidget);
    expect(driver.selectedTrail, TrailSkinId.classic);
    for (final skin in trailSkins) {
      expect(
        find.byKey(ValueKey('preview-trail-${skin.id.name}')),
        findsOneWidget,
      );
    }

    final aurora = find.byKey(const ValueKey('trail-option-aurora'));
    await tester.tap(aurora);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 350);
    expect(driver.selectedTrail, TrailSkinId.classic);
    await tester.tap(aurora);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 350);
    expect(driver.selectedTrail, TrailSkinId.aurora);
    expect(driver.selectedSkin, ShipSkinId.emerald);
    expect(driver.selectedOrbit, OrbitSkinId.aurora);
    expect(driver.selectedCore, CoreSkinId.crimson);

    final solar = find.byKey(const ValueKey('trail-option-solar'));
    await tester.tap(solar);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 0);
    expect(driver.selectedTrail, TrailSkinId.aurora);
    await tester.tap(solar);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 0);
    expect(driver.selectedTrail, TrailSkinId.solar);
    expect(driver.selectedSkin, ShipSkinId.emerald);
    expect(driver.selectedOrbit, OrbitSkinId.aurora);
    expect(driver.selectedCore, CoreSkinId.crimson);

    await driver.flushProgress();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(AppearanceStore.selectedTrailKey), 'solar');
    expect(preferences.getString(SkinStore.selectedSkinKey), 'emerald');
    expect(preferences.getString(AppearanceStore.selectedOrbitKey), 'aurora');
    expect(preferences.getString(AppearanceStore.selectedCoreKey), 'crimson');
    final restoredWallet = GemWallet();
    await restoredWallet.load();
    final restoredAppearances = AppearanceStore();
    await restoredAppearances.load(
      ownedItemIds: restoredWallet.purchasedItemIds,
    );
    expect(restoredWallet.owns('trail.aurora'), isTrue);
    expect(restoredWallet.owns('trail.solar'), isTrue);
    expect(restoredAppearances.selectedTrail, TrailSkinId.solar);
    expect(restoredWallet.balance, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('previews isolate candidate IDs without changing shop state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      GemWallet.stateKey: '{"version":2,"balance":0,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{"ship.emerald":25,"orbit.aurora":40,"core.crimson":50}}',
      SkinStore.selectedSkinKey: 'emerald',
      AppearanceStore.selectedOrbitKey: 'aurora',
      AppearanceStore.selectedCoreKey: 'crimson',
    });
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: _ShopAudio(), testDriver: driver),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final walletStateBefore = preferences.getString(GemWallet.stateKey);
    final shipSelectionBefore = preferences.getString(
      SkinStore.selectedSkinKey,
    );
    final orbitSelectionBefore = preferences.getString(
      AppearanceStore.selectedOrbitKey,
    );
    final coreSelectionBefore = preferences.getString(
      AppearanceStore.selectedCoreKey,
    );
    final originalWallet = GemWallet();
    await originalWallet.load();
    final ownedBefore = originalWallet.purchasedItemIds;

    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-ship-supernova')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-ship-supernova')));
    await tester.pumpAndSettle();
    _expectPreviewScene(
      tester,
      'ship=supernova; orbit=aurora; core=crimson; trail=classic',
    );
    expect(find.text('Supernova'), findsWidgets);
    final metadata = tester.widget<Text>(
      find.byKey(const ValueKey('cosmetic-preview-category-rarity')),
    );
    expect(metadata.data, contains('SHIP'));
    expect(metadata.data, contains('PREMIUM'));
    expect(find.textContaining('PREVIEW ONLY'), findsNothing);
    expect(find.textContaining('does not purchase or equip'), findsOneWidget);
    expect(driver.walletBalance, 0);
    expect(driver.selectedSkin, ShipSkinId.emerald);
    await _expectWalletOwnership(ownedBefore);
    expect(preferences.getString(GemWallet.stateKey), walletStateBefore);
    expect(
      preferences.getString(SkinStore.selectedSkinKey),
      shipSelectionBefore,
    );
    expect(
      preferences.getString(AppearanceStore.selectedOrbitKey),
      orbitSelectionBefore,
    );
    expect(
      preferences.getString(AppearanceStore.selectedCoreKey),
      coreSelectionBefore,
    );
    await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('SHIP SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-option-supernova')), findsOneWidget);

    final orbitTab = find.byKey(const ValueKey('cosmetic-tab-orbit'));
    await tester.ensureVisible(orbitTab);
    await tester.tap(orbitTab);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-orbit-solar')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-orbit-solar')));
    await tester.pumpAndSettle();
    _expectPreviewScene(
      tester,
      'ship=emerald; orbit=solar; core=crimson; trail=classic',
    );
    expect(driver.walletBalance, 0);
    expect(driver.selectedOrbit, OrbitSkinId.aurora);
    await _expectWalletOwnership(ownedBefore);
    await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('ORBIT SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-option-solar')), findsOneWidget);

    final coreTab = find.byKey(const ValueKey('cosmetic-tab-core'));
    await tester.ensureVisible(coreTab);
    await tester.tap(coreTab);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-core-glacier')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-core-glacier')));
    await tester.pumpAndSettle();
    _expectPreviewScene(
      tester,
      'ship=emerald; orbit=aurora; core=glacier; trail=classic',
    );
    expect(driver.walletBalance, 0);
    expect(driver.selectedCore, CoreSkinId.crimson);
    await _expectWalletOwnership(ownedBefore);
    await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('CORE SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('core-option-glacier')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('cosmetic-tab-trail')),
    );
    await tester.tap(find.byKey(const ValueKey('cosmetic-tab-trail')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-trail-solar')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-trail-solar')));
    await tester.pumpAndSettle();
    _expectPreviewScene(
      tester,
      'ship=emerald; orbit=aurora; core=crimson; trail=solar',
    );
    expect(driver.walletBalance, 0);
    expect(driver.selectedTrail, TrailSkinId.classic);
    await _expectWalletOwnership(ownedBefore);
    await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('TRAIL SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-option-solar')), findsOneWidget);
    await driver.flushProgress();
    expect(preferences.getString(GemWallet.stateKey), walletStateBefore);
    expect(
      preferences.getString(SkinStore.selectedSkinKey),
      shipSelectionBefore,
    );
    expect(
      preferences.getString(AppearanceStore.selectedOrbitKey),
      orbitSelectionBefore,
    );
    expect(
      preferences.getString(AppearanceStore.selectedCoreKey),
      coreSelectionBefore,
    );
    expect(
      preferences.getString(AppearanceStore.selectedTrailKey),
      TrailSkinId.classic.name,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all catalog skins are discoverable and previewable', (
    tester,
  ) async {
    final driver = OrbitGameTestDriver();
    await tester.pumpWidget(
      MaterialApp(
        home: OrbitGamePage(audioController: _ShopAudio(), testDriver: driver),
      ),
    );
    await tester.pumpAndSettle();
    await driver.flushProgress();
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final walletBefore = preferences.getString(GemWallet.stateKey);
    final wallet = GemWallet();
    await wallet.load();
    final ownershipBefore = wallet.purchasedItemIds;

    Future<void> previewCategory(
      String category,
      String candidateField,
      Iterable<String> ids,
    ) async {
      final tab = find.byKey(ValueKey('cosmetic-tab-$category'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.text('${category.toUpperCase()} SKINS'), findsOneWidget);
      for (final id in ids) {
        final preview = find.byKey(ValueKey('preview-$category-$id'));
        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        final scene = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('cosmetic-preview-scene')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(scene.properties.label, contains('$candidateField=$id'));
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
        await tester.pumpAndSettle();
        expect(find.text('${category.toUpperCase()} SKINS'), findsOneWidget);
      }
    }

    await previewCategory(
      'ship',
      'ship',
      shipSkins.map((skin) => skin.id.name),
    );
    await previewCategory(
      'orbit',
      'orbit',
      orbitSkins.map((skin) => skin.id.name),
    );
    await previewCategory(
      'core',
      'core',
      coreSkins.map((skin) => skin.id.name),
    );
    await previewCategory(
      'trail',
      'trail',
      trailSkins.map((skin) => skin.id.name),
    );
    await driver.flushProgress();
    expect(preferences.getString(GemWallet.stateKey), walletBefore);
    final restored = GemWallet();
    await restored.load();
    expect(restored.purchasedItemIds, ownershipBefore);
    expect(driver.selectedSkin, ShipSkinId.defaultSkin);
    expect(driver.selectedOrbit, OrbitSkinId.defaultOrbit);
    expect(driver.selectedCore, CoreSkinId.defaultCore);
    expect(driver.selectedTrail, TrailSkinId.classic);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cosmetic shop remains usable on narrow screens', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: OrbitGamePage(audioController: _ShopAudio())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cosmetic shop'));
    await tester.pumpAndSettle();
    expect(find.text('COSMETIC SHOP'), findsOneWidget);
    expect(find.byKey(const ValueKey('cosmetic-tab-ship')), findsOneWidget);
    expect(find.text('SHIP SKINS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('orbit-option-defaultOrbit')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('core-option-defaultCore')), findsNothing);
    expect(tester.takeException(), isNull);
    final tabs = find.byKey(const ValueKey('cosmetic-category-tabs-scroll'));
    final trailTab = find.byKey(const ValueKey('cosmetic-tab-trail'));
    expect(
      tester.getRect(trailTab).right,
      greaterThan(tester.getRect(tabs).right),
    );
    await tester.ensureVisible(trailTab);
    await tester.tap(trailTab);
    await tester.pumpAndSettle();
    expect(find.text('TRAIL SKINS'), findsOneWidget);
    final orbitTab = find.byKey(const ValueKey('cosmetic-tab-orbit'));
    await tester.ensureVisible(orbitTab);
    await tester.tap(orbitTab);
    await tester.pumpAndSettle();
    expect(find.text('ORBIT SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-option-defaultSkin')), findsNothing);
    final coreTab = find.byKey(const ValueKey('cosmetic-tab-core'));
    await tester.ensureVisible(coreTab);
    await tester.tap(coreTab);
    await tester.pumpAndSettle();
    expect(find.text('CORE SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('core-option-glacier')), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(trailTab);
    expect(
      tester.getRect(trailTab).right,
      lessThanOrEqualTo(tester.getRect(tabs).right),
    );
    await tester.tap(trailTab);
    await tester.pumpAndSettle();
    expect(find.text('TRAIL SKINS'), findsOneWidget);
    final solarPreview = find.byKey(const ValueKey('preview-trail-solar'));
    await tester.ensureVisible(solarPreview);
    await tester.tap(solarPreview);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cosmetic-preview-scene')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('cosmetic-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('TRAIL SKINS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _expectPreviewScene(WidgetTester tester, String skinIds) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(
          of: find.byKey(const ValueKey('cosmetic-preview-scene')),
          matching: find.byType(Semantics),
        )
        .first,
  );
  expect(semantics.properties.label, 'Preview scene: $skinIds');
  expect(find.byKey(const ValueKey('cosmetic-preview-scene')), findsOneWidget);
}

Future<void> _expectWalletOwnership(Set<String> expected) async {
  final restored = GemWallet();
  await restored.load();
  expect(restored.purchasedItemIds, expected);
}

class _ShopAudio extends GameAudioController {
  @override
  bool get musicEnabled => true;
  @override
  bool get effectsEnabled => true;
  @override
  Future<void> initialize() async {}
  @override
  void setGameState(AudioRunState state) {}
  @override
  void setAppActive(bool active) {}
  @override
  Future<void> setMusicEnabled(bool enabled) async {}
  @override
  Future<void> setEffectsEnabled(bool enabled) async {}
  @override
  void playEffect(GameSoundEffect effect) {}
  @override
  Future<void> shutdown() async {}
}
