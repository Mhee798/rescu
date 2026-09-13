import 'dart:async';

import 'package:get/get.dart';

/// One ticker for every countdown in the app.
///
/// The alternative — a `Timer` inside each countdown widget — puts one timer
/// per visible card on the home feed, each firing on its own phase, so the
/// feed wakes up many times a second instead of once and the seconds on
/// adjacent cards change at visibly different moments. It is also the shape
/// that produced RES-102: a timer owned by a widget that forgets to cancel it.
///
/// Nothing here knows what a countdown is. It publishes the time, once a
/// second, and the widgets that care subscribe to it.
class ClockService extends GetxService {
  ClockService({Duration interval = const Duration(seconds: 1)})
      : _interval = interval;

  final Duration _interval;
  Timer? _ticker;

  final Rx<DateTime> _now = DateTime.now().obs;

  /// The current second. Reading this inside an `Obx` subscribes that scope to
  /// every tick — keep such scopes down to the text that shows the time.
  DateTime get now => _now.value;

  /// For `ever(...)` subscriptions that want to react to a tick without
  /// rebuilding on every one. See `ExpiryBuilder`.
  Rx<DateTime> get nowRx => _now;

  @override
  void onInit() {
    super.onInit();
    _ticker = Timer.periodic(_interval, (_) => _now.value = DateTime.now());
  }

  @override
  void onClose() {
    _ticker?.cancel();
    _ticker = null;
    super.onClose();
  }
}
