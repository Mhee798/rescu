import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';

/// `mm:ss`, or `hh:mm:ss` once there is more than an hour left.
///
/// Returns null past the end so callers can decide what an expired deal looks
/// like rather than having a string forced on them.
/// The seconds are rounded up rather than truncated. `endsAt` does not land on
/// a tick boundary, so a sub-second remainder is the normal case at the end of
/// a sale — and truncating it prints `00:00` while `ExpiryBuilder`, which flips
/// at `now >= endsAt`, still has the deal live and its button enabled.
String? formatFlashRemaining(Duration remaining) {
  if (remaining <= Duration.zero) return null;
  String two(int value) => value.toString().padLeft(2, '0');
  final total = (remaining.inMilliseconds / 1000).ceil();
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
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
