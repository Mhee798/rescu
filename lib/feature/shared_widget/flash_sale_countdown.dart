import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';

/// `mm:ss`, or `hh:mm:ss` once there is more than an hour left.
///
/// Returns null past the end so callers can decide what an expired deal looks
/// like rather than having a string forced on them.
String? formatFlashRemaining(Duration remaining) {
  if (remaining <= Duration.zero) return null;
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  final seconds = remaining.inSeconds % 60;
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

/// The live part of a flash-sale badge.
///
/// The `Obx` wraps the `Text` and nothing else on purpose: it is the only
/// thing whose content changes each second, and F-1 asks for per-second
/// rebuilds to stop there rather than reaching the card or the list. Whether
/// the deal is *expired* is a separate question with a different rebuild rate,
/// and `ExpiryBuilder` answers that one.
class FlashSaleCountdown extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;

  /// Shown once the sale has ended. The countdown does not decide what that
  /// looks like beyond the text.
  final String expiredLabel;

  const FlashSaleCountdown({
    super.key,
    required this.endsAt,
    this.style,
    this.expiredLabel = 'Expired',
  });

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    return Obx(() {
      final remaining = endsAt.difference(clock.now);
      return Text(formatFlashRemaining(remaining) ?? expiredLabel,
          style: style);
    });
  }
}
