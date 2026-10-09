import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_dash/main.dart';

void main() {
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
