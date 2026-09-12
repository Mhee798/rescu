import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the scroll-to-top FAB's entrance animation.
///
/// RES-105 moved the FAB's visibility into an `Obx`, which cannot return null.
/// `Scaffold` animates its floating action button in
/// `_FloatingActionButtonTransition.didUpdateWidget`, and that method returns
/// early when both the old and new children are non-null *and* their keys
/// compare equal (`material/scaffold.dart:1368`). Two unkeyed widgets satisfy
/// both conditions, so swapping `SizedBox.shrink()` for a `FloatingActionButton`
/// made the button appear at full size with no scale-in.
///
/// These two cases differ only in whether the children carry distinct keys.
void main() {
  Widget app({required bool show, required bool keyed}) {
    return MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        floatingActionButton: show
            ? FloatingActionButton.small(
                key: keyed ? const ValueKey('scroll-to-top') : null,
                onPressed: () {},
                child: const Icon(Icons.arrow_upward),
              )
            : SizedBox.shrink(key: keyed ? const ValueKey('no-fab') : null),
      ),
    );
  }

  /// The scale `Scaffold` is currently applying to the FAB. `Scaffold` wraps it
  /// in `ScaleTransition` (`scaffold.dart:1484`), so reading that animation's
  /// value mid-pump is what distinguishes an animation from an instant swap.
  double fabScale(WidgetTester tester) {
    final transition = tester.widget<ScaleTransition>(
      find
          .ancestor(
            of: find.byType(FloatingActionButton),
            matching: find.byType(ScaleTransition),
          )
          .first,
    );
    return transition.scale.value;
  }

  /// Number of 16 ms frames before the FAB reaches its resting scale. One frame
  /// means it was never animated. Deliberately measured in frames rather than
  /// against a duration, so the test does not encode `Scaffold`'s curve or its
  /// 200 ms segue — only whether an animation happened at all.
  Future<int> framesToFullScale(WidgetTester tester) async {
    for (var frame = 1; frame <= 60; frame++) {
      if (fabScale(tester) == 1.0) {
        return frame;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    return -1;
  }

  testWidgets('scales in over several frames when the branches carry keys',
      (tester) async {
    await tester.pumpWidget(app(show: false, keyed: true));
    await tester.pumpWidget(app(show: true, keyed: true));
    await tester.pump();

    // Scaffold runs the outgoing child's exit before the incoming child's
    // entrance (`scaffold.dart:73-77`), so the FAB starts at zero and stays
    // there for a while — the count below spans both halves.
    expect(fabScale(tester), 0.0);
    expect(await framesToFullScale(tester), greaterThan(1));

    await tester.pumpAndSettle();
    expect(fabScale(tester), 1.0);
  });

  testWidgets(
      'appears at full size in one frame when both branches are unkeyed',
      (tester) async {
    await tester.pumpWidget(app(show: false, keyed: false));
    await tester.pumpWidget(app(show: true, keyed: false));
    await tester.pump();

    // This is the behaviour the keys exist to prevent, asserted so the test
    // above cannot quietly become vacuous: if Scaffold ever animates unkeyed
    // swaps too, this case fails and the keys can be dropped.
    expect(fabScale(tester), 1.0);
    expect(await framesToFullScale(tester), 1);
  });
}
