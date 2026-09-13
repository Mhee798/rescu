import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';

/// Rebuilds its child when a deal crosses from live to expired — once, at the
/// boundary, not once a second.
///
/// An `Obx` reading the clock cannot do this. `Obx` rebuilds whenever the
/// observable it read notifies, whether or not the value the scope *derives*
/// from it changed, so `Obx(() => card(expired: now.isAfter(endsAt)))` would
/// rebuild the whole card every second to produce the same card. That is the
/// thing F-1 explicitly rules out.
///
/// So the tick is consumed by a listener instead of by a reactive scope, and
/// `setState` is called only when the boolean actually flips. Visible cards on
/// the feed therefore cost one subscription each and zero rebuilds per second.
///
/// The `Worker` is disposed in `dispose`. `ever` hands one back because the
/// caller owns it, and `ClockService` is registered `permanent: true` — the
/// exact pairing that made RES-103 a leak.
class ExpiryBuilder extends StatefulWidget {
  /// Null for a deal that is not a flash sale; the builder is then called once
  /// with `expired: false` and no subscription is taken.
  final DateTime? endsAt;

  final Widget Function(BuildContext context, bool expired) builder;

  /// Called the moment this deal crosses into expiry while on screen.
  final VoidCallback? onExpired;

  const ExpiryBuilder({
    super.key,
    required this.endsAt,
    required this.builder,
    this.onExpired,
  });

  @override
  State<ExpiryBuilder> createState() => _ExpiryBuilderState();
}

class _ExpiryBuilderState extends State<ExpiryBuilder> {
  Worker? _tick;
  late bool _expired;

  ClockService get _clock => Get.find<ClockService>();

  /// Reads the clock rather than `DateTime.now()` so that the decision and the
  /// countdown on screen are taken from the same instant — otherwise a card can
  /// read `00:01` while its own expiry has already fired. It is also the only
  /// way a test can move time: `flutter_test` fakes timers but not
  /// `DateTime.now()`, so `tester.pump(...)` alone advances the ticker without
  /// advancing the wall clock the comparison used.
  bool _isExpired() {
    final endsAt = widget.endsAt;
    return endsAt != null && !_clock.now.isBefore(endsAt);
  }

  @override
  void initState() {
    super.initState();
    _expired = _isExpired();
    _subscribe();
  }

  @override
  void didUpdateWidget(ExpiryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled list item can arrive carrying a different deal.
    if (oldWidget.endsAt != widget.endsAt) {
      _expired = _isExpired();
      _tick?.dispose();
      _tick = null;
      _subscribe();
    }
  }

  void _subscribe() {
    // Nothing to wait for: not a flash sale, or the sale was already over when
    // this card was built.
    if (widget.endsAt == null || _expired) return;
    _tick = ever(_clock.nowRx, (_) {
      // The subscription is deliberately *not* disposed here, and the `_expired`
      // guard is what makes that safe. Disposing a `Worker` from inside its own
      // callback does not take effect when you ask: the stream is mid-
      // notification, so `GetStream.removeSubscription` defers the removal
      // behind `await Future.delayed(Duration.zero)`
      // (`get_stream.dart:21-27`). The listener survives at least one more
      // tick — measured, a second rebuild arrived six seconds after expiry —
      // and the deferred removal also leaves a pending timer that
      // `flutter_test` reports as a leak. Cleanup happens in `dispose`, where
      // the stream is idle and the removal is immediate.
      if (_expired || !_isExpired()) return;
      setState(() => _expired = true);
      widget.onExpired?.call();
    });
  }

  @override
  void dispose() {
    _tick?.dispose();
    _tick = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _expired);
}
