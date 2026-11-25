import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/gem_shop.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orbit_dash/account_scoped_preferences.dart';

void main() {
  test(
    'Gem package catalog has stable ordered products and approved prices',
    () {
      expect(gemPackages.map((p) => p.id), [
        'gems.small',
        'gems.medium',
        'gems.large',
        'gems.mega',
      ]);
      expect(gemPackages.map((p) => p.totalGems), [500, 1300, 2850, 7200]);
      expect(gemPackages.map((p) => p.displayOrder), [0, 1, 2, 3]);
      expect(gemPackages.map((p) => p.displayPrice), [
        r'$0.99',
        r'$2.99',
        r'$4.99',
        r'$9.99',
      ]);
      expect(gemPackages.where((p) => p.featured).map((p) => p.id), [
        'gems.large',
      ]);
    },
  );

  testWidgets('Gem shop renders packages and purchase does not change wallet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AccountScopedPreferences.localKey(GemWallet.stateKey): '{"version":2,"balance":42,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
    });
    final wallet = GemWallet();
    await wallet.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GemShopDialog(balance: wallet.balance)),
      ),
    );
    expect(find.text('YOUR BALANCE  42 G'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(find.text(r'$0.99'), findsOneWidget);
    expect(find.text(r'$2.99'), findsOneWidget);
    expect(find.text(r'$4.99'), findsOneWidget);
    expect(find.text(r'$9.99'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gem-package-gems.small')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOT AVAILABLE').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Purchases are coming soon. Your Gem balance has not changed.'),
      findsOneWidget,
    );
    expect(wallet.balance, 42);
    final restored = GemWallet();
    await restored.load();
    expect(restored.balance, 42);
  });

  testWidgets(
    'separate Get Gems HUD button opens shop and balance stays display-only',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        AccountScopedPreferences.localKey(GemWallet.stateKey): '{"version":2,"balance":42,"dailyRewardDate":null,"dailyRewardIds":[],"purchases":{}}',
      });
      await tester.pumpWidget(
        MaterialApp(home: OrbitGamePage(audioController: _GemShopAudio())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gem-balance-display')), findsOneWidget);
      expect(find.byKey(const ValueKey('get-gems-button')), findsOneWidget);
      expect(find.text('GET GEMS'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('get-gems-button'))),
        const Size(88, 48),
      );
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('get-gems-button')),
      );
      expect(
        button.style?.foregroundColor?.resolve({}),
        const Color(0xffffd66e),
      );
      expect(button.style?.backgroundColor?.resolve({}), isNull);
      expect(button.style?.side?.resolve({}), isNull);
      expect(
        button.style?.overlayColor?.resolve({WidgetState.pressed}),
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('gem-balance-display')));
      await tester.pumpAndSettle();
      expect(find.text('GEM SHOP'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('get-gems-button')));
      await tester.pumpAndSettle();
      expect(find.text('YOUR BALANCE  42 G'), findsOneWidget);
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('START RUN'), findsOneWidget);
      expect(find.text('GEM SHOP'), findsNothing);
      final wallet = GemWallet();
      await wallet.load();
      expect(wallet.balance, 42);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Get Gems button remains visible with zero balance', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: OrbitGamePage(audioController: _GemShopAudio())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('main-menu-gem-balance')), findsOneWidget);
    expect(find.text('0 G'), findsOneWidget);
    expect(find.byKey(const ValueKey('get-gems-button')), findsOneWidget);
    expect(find.text('GET GEMS'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('get-gems-button'))),
      const Size(68, 48),
    );
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('get-gems-button')),
    );
    expect(button.style?.textStyle?.resolve({})?.fontSize, 9);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _GemShopAudio extends GameAudioController {
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
