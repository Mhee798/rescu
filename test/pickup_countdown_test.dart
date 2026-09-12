import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

/// Regression tests for RES-102.
///
/// The bug was a `Timer.periodic` started in `initState` whose handle was never
/// kept and never cancelled, so it went on calling `setState` after the route
/// had popped and the State was defunct.
void main() {
  Future<void> pumpCountdown(WidgetTester tester, DateTime pickupStart) {
    return tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: PickupCountdown(pickupStart: pickupStart))),
    );
  }

  testWidgets('cancels its timer when disposed', (tester) async {
    await pumpCountdown(tester, DateTime.now().add(const Duration(hours: 2)));

    // Replace the tree, which disposes the countdown the way popping the route
    // does, then let the periodic timer's next tick come due.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump(const Duration(seconds: 2));

    // No assertion is needed here: flutter_test fails the test itself with
    // "A Timer is still pending even after the widget tree was disposed" if the
    // timer outlives the widget, which is exactly the defect. Before the fix
    // this test fails on that invariant.
  });

  testWidgets('survives several ticks while mounted', (tester) async {
    await pumpCountdown(tester, DateTime.now().add(const Duration(hours: 2)));

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.textContaining('Opens in'), findsOneWidget);
  });

  testWidgets('shows minutes and seconds under an hour', (tester) async {
    await pumpCountdown(tester, DateTime.now().add(const Duration(minutes: 5)));

    expect(find.textContaining('Opens in 0'), findsOneWidget);
  });

  testWidgets('shows hours and minutes over an hour', (tester) async {
    await pumpCountdown(tester, DateTime.now().add(const Duration(hours: 3)));

    expect(find.textContaining('h '), findsOneWidget);
  });

  testWidgets('says the window is open once the start time has passed',
      (tester) async {
    await pumpCountdown(
      tester,
      DateTime.now().subtract(const Duration(minutes: 5)),
    );

    expect(find.text('Pickup window is open'), findsOneWidget);
  });
}
