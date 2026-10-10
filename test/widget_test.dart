import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'orbit_dash_best': 12});
  });

  group('angular collision helpers', () {
    test('finds the shortest distance across the zero boundary', () {
      expect(
        shortestAngularDistance(0.03, 2 * math.pi - 0.04),
        closeTo(0.07, 1e-12),
      );
      expect(
        shortestAngularDistance(2 * math.pi - 0.04, 0.03),
        closeTo(0.07, 1e-12),
      );
    });

    test('works after multiple full rotations', () {
      expect(
        shortestAngularDistance(8 * math.pi + 0.03, 6 * math.pi - 0.04),
        closeTo(0.07, 1e-12),
      );
    });

    test('preserves the strict collision threshold', () {
      expect(isAngularCollision(0, 0.159), isTrue);
      expect(isAngularCollision(0, 0.16), isFalse);
      expect(isAngularCollision(0, 0.161), isFalse);
    });
  });

  group('hazard cleanup', () {
    test(
      'keeps a hazard near alignment and expires it after a full relative turn',
      () {
        final nearAlignment = math.pi + 0.4;
        expect(hazardLifetimeExpired(nearAlignment - 0.01), isFalse);
        expect(hazardLifetimeExpired(nearAlignment), isFalse);
        expect(hazardLifetimeExpired(nearAlignment + 0.01), isFalse);
        expect(hazardLifetimeExpired(2 * math.pi), isTrue);
      },
    );
  });

  testWidgets('shows the start screen and starts a run', (tester) async {
    await tester.pumpWidget(const OrbitDashApp());
    await tester.pumpAndSettle();
    expect(find.text('READY, PILOT?'), findsOneWidget);
    expect(find.text('Dodge the red. Chase the glow.'), findsOneWidget);
    expect(find.text('BEST FLIGHT'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('START RUN'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('START RUN'));
    await tester.pump();
    expect(find.text('READY, PILOT?'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsOneWidget);
  });

  testWidgets('pause screen resumes or restarts through existing actions', (
    tester,
  ) async {
    await tester.pumpWidget(const OrbitDashApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('CURRENT SCORE'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('RESTART RUN'), findsOneWidget);

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.text('RESTART RUN'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows the final score and best result, then replays', (
    tester,
  ) async {
    await tester.pumpWidget(const OrbitDashApp());
    await tester.tap(find.text('START RUN'));
    await tester.pump();

    for (var frame = 0; frame < 220; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('GAME OVER').evaluate().isNotEmpty) break;
    }

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('FINAL SCORE'), findsOneWidget);
    expect(find.text('BEST FLIGHT'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsNothing);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('GAME OVER'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('start panel fits a compact viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const OrbitDashApp());
    expect(find.text('START RUN'), findsOneWidget);
    final buttonRect = tester.getRect(find.text('START RUN'));
    expect(buttonRect.left, greaterThanOrEqualTo(0));
    expect(buttonRect.right, lessThanOrEqualTo(320));
    expect(buttonRect.bottom, lessThanOrEqualTo(568));
  });
}
