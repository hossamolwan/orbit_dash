import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/main.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/skins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    await tester.tap(find.byKey(const ValueKey('cosmetic-tab-orbit')));
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
    expect(driver.walletBalance, 260);
    expect(driver.selectedOrbit, OrbitSkinId.defaultOrbit);
    await tester.ensureVisible(aurora);
    await tester.tap(aurora);
    await tester.pumpAndSettle();
    expect(driver.selectedOrbit, OrbitSkinId.aurora);

    await tester.tap(find.byKey(const ValueKey('cosmetic-tab-ship')));
    await tester.pumpAndSettle();
    expect(driver.selectedSkin, ShipSkinId.defaultSkin);
    expect(driver.selectedOrbit, OrbitSkinId.aurora);
    expect(driver.walletBalance, 260);
    expect(
      find.byKey(const ValueKey('skin-option-defaultSkin')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cosmetic-tab-core')));
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
    expect(driver.walletBalance, 210);
    expect(driver.selectedCore, CoreSkinId.defaultCore);
    await tester.ensureVisible(crimson);
    await tester.tap(crimson);
    await tester.pumpAndSettle();
    expect(driver.walletBalance, 210);
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
    expect(restoredWallet.balance, 210);
    expect(restoredWallet.owns('orbit.aurora'), isTrue);
    expect(restoredWallet.owns('core.crimson'), isTrue);
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
    await tester.tap(find.byKey(const ValueKey('cosmetic-tab-orbit')));
    await tester.pumpAndSettle();
    expect(find.text('ORBIT SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-option-defaultSkin')), findsNothing);
    final tabs = find.byKey(const ValueKey('cosmetic-category-tabs-scroll'));
    final coreTab = find.byKey(const ValueKey('cosmetic-tab-core'));
    expect(
      tester.getRect(coreTab).right,
      greaterThan(tester.getRect(tabs).right),
    );
    await tester.ensureVisible(coreTab);
    expect(
      tester.getRect(coreTab).right,
      lessThanOrEqualTo(tester.getRect(tabs).right),
    );
    await tester.tap(coreTab);
    await tester.pumpAndSettle();
    expect(find.text('CORE SKINS'), findsOneWidget);
    expect(find.byKey(const ValueKey('core-option-glacier')), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-option-aurora')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
