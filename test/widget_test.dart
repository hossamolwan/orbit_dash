import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/main.dart';

void main() {
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
    test('keeps a hazard near alignment and expires it after a full relative turn', () {
      final nearAlignment = math.pi + 0.4;
      expect(hazardLifetimeExpired(nearAlignment - 0.01), isFalse);
      expect(hazardLifetimeExpired(nearAlignment), isFalse);
      expect(hazardLifetimeExpired(nearAlignment + 0.01), isFalse);
      expect(hazardLifetimeExpired(2 * math.pi), isTrue);
    });
  });

  testWidgets('starts, pauses, and resumes a run', (tester) async {
    await tester.pumpWidget(const OrbitDashApp());
    expect(find.text('READY, PILOT?'), findsOneWidget);
    await tester.tap(find.text('START RUN'));
    await tester.pump();
    expect(find.text('READY, PILOT?'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
  });
}
