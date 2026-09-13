import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

/// Regression tests for RES-102.
///
/// The bug was a `Timer.periodic` started in `initState` whose handle was never
/// kept and never cancelled, so it went on calling `setState` after the route
/// had popped and the State was defunct.
void main() {
  String shownText(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining('Opens in')).data!;

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

    // This case has no assertion of its own: it borrows flutter_test's
    // "A Timer is still pending even after the widget tree was disposed"
    // invariant, which is exactly the defect. That is a dependency, not
    // elegance — if the framework ever moves that check, this quietly becomes a
    // test that always passes. There is no clean way to assert a cancelled
    // timer directly, so the trade is accepted and written down.
  });

  testWidgets('rebuilding on each tick does not throw', (tester) async {
    await pumpCountdown(tester, DateTime.now().add(const Duration(hours: 2)));

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.textContaining('Opens in'), findsOneWidget);

    // Named for what it does. `tester.pump` advances FakeAsync's clock, which
    // is what fires the periodic timer, but the widget derives `remaining` from
    // `DateTime.now()`, which flutter_test does not fake — measured: the
    // rendered string is identical across six simulated seconds. So this covers
    // "three extra builds are harmless", not "the number counts down". The
    // arithmetic itself is verified on device, not here.
  });

  testWidgets('renders mm:ss under an hour', (tester) async {
    await pumpCountdown(
      tester,
      // The half-second of slack keeps the expected value off the boundary.
      DateTime.now().add(const Duration(minutes: 5, milliseconds: 500)),
    );

    // The format is pinned exactly so a later edit cannot quietly change what
    // an order screen says. An earlier version of this comment claimed F-1
    // would replace this widget; it does not — F-1 is the flash-sale
    // countdown, a different widget on different screens reading
    // `flashSaleEndsAt`, and this one stays as the pickup-window clock. The
    // value allows one second of drift for a slow run.
    expect(shownText(tester), matches(RegExp(r'^Opens in \d{2}:\d{2}$')));
    expect(shownText(tester), anyOf('Opens in 05:00', 'Opens in 04:59'));
  });

  testWidgets('renders hours and minutes over an hour', (tester) async {
    await pumpCountdown(
      tester,
      DateTime.now()
          .add(const Duration(hours: 3, minutes: 30, milliseconds: 500)),
    );

    expect(shownText(tester), matches(RegExp(r'^Opens in \d+h \d{1,2}m$')));
    expect(shownText(tester), anyOf('Opens in 3h 30m', 'Opens in 3h 29m'));
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
