import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Regression test for the scroll-to-top FAB's entrance animation.
///
/// RES-105 moved the FAB's visibility into a narrow `Obx`. That breaks
/// `Scaffold`'s built-in scale-in, and not for the reason it first appears:
/// `Scaffold` animates the button in
/// `_FloatingActionButtonTransition.didUpdateWidget`, which only runs when the
/// **`Scaffold`** rebuilds with a different `floatingActionButton`. An `Obx`
/// rebuilds itself and never its parent, so that method is never reached and
/// the `ScaleTransition` stays pinned at the value it settled on at mount —
/// 1.0, because `Obx` is non-null from the first frame. No arrangement of keys
/// or children inside the `Obx` can change that.
///
/// So the animation is done here instead, and these tests are written around
/// the production shape — `Obx` inside `Scaffold`, driven by writing to the
/// `Rx` — because an earlier version of this file toggled the branch with
/// `pumpWidget`, which rebuilds the `Scaffold` and therefore tested a path the
/// app never takes. It passed while the app popped the button in at full size.
void main() {
  /// Mirrors `HomeScreen`'s floating action button exactly.
  Widget app(RxBool show, {required bool animated}) {
    return MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        floatingActionButton: Obx(() {
          final visible = show.value;
          final button = FloatingActionButton.small(
            onPressed: () {},
            child: const Icon(Icons.arrow_upward),
          );
          if (!animated) {
            return visible ? button : const SizedBox.shrink();
          }
          return IgnorePointer(
            ignoring: !visible,
            child: AnimatedScale(
              scale: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: button,
            ),
          );
        }),
      ),
    );
  }

  /// The scale actually applied to the button, wherever it comes from —
  /// `Scaffold`'s own `ScaleTransition` or the `AnimatedScale` above it.
  double appliedScale(WidgetTester tester) {
    final transforms = tester.widgetList<Transform>(
      find.ancestor(
        of: find.byType(FloatingActionButton),
        matching: find.byType(Transform),
      ),
    );
    var scale = 1.0;
    for (final t in transforms) {
      scale *= t.transform.storage[0];
    }
    return scale;
  }

  /// Frames before the button reaches full size. One means it was never
  /// animated. Counted in frames rather than against a duration so the test
  /// encodes no particular curve.
  Future<int> framesToFullScale(WidgetTester tester) async {
    for (var frame = 1; frame <= 60; frame++) {
      if ((appliedScale(tester) - 1.0).abs() < 0.001) {
        return frame;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    return -1;
  }

  testWidgets('scales in over several frames when the flag flips',
      (tester) async {
    final show = false.obs;
    addTearDown(show.close);
    await tester.pumpWidget(app(show, animated: true));
    expect(appliedScale(tester), lessThan(0.001));

    show.value = true;
    await tester.pump();

    expect(await framesToFullScale(tester), greaterThan(1));
    await tester.pumpAndSettle();
    expect(appliedScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('hidden button cannot be tapped while it is scaled away',
      (tester) async {
    var taps = 0;
    final show = false.obs;
    addTearDown(show.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          floatingActionButton: Obx(
            () => IgnorePointer(
              ignoring: !show.value,
              child: AnimatedScale(
                scale: show.value ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: FloatingActionButton.small(
                  onPressed: () => taps++,
                  child: const Icon(Icons.arrow_upward),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // A zero-scale Transform still occupies its layout slot, so without the
    // IgnorePointer the collapsed button remains a live tap target.
    await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);

    show.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 1);
  });

  testWidgets('without the AnimatedScale it appears at full size in one frame',
      (tester) async {
    final show = false.obs;
    addTearDown(show.close);
    await tester.pumpWidget(app(show, animated: false));

    show.value = true;
    await tester.pump();

    // The control. This is what the screen did between the Obx scoping and
    // this fix: Scaffold's own transition never runs, so the button is simply
    // there. If this ever starts animating, the AnimatedScale is redundant.
    expect(await framesToFullScale(tester), 1);
  });
}
