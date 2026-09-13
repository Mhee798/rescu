import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/cart_service.dart';

/// Shows the notices `CartService` publishes, wherever the user happens to be.
///
/// Mounted once, above the navigator, because the bag can change itself while
/// no screen that shows it is open — a flash sale ending removes a line whether
/// the user is on the map or reading a deal. Keeping it here rather than in the
/// service means the service never needs an overlay to exist, which is both an
/// architectural point and a practical one: `Get.snackbar` throws outright
/// without one, as a unit test of the bag found.
class CartNoticeHost extends StatefulWidget {
  final Widget child;

  const CartNoticeHost({super.key, required this.child});

  @override
  State<CartNoticeHost> createState() => _CartNoticeHostState();
}

class _CartNoticeHostState extends State<CartNoticeHost> {
  Worker? _notices;

  @override
  void initState() {
    super.initState();
    _notices = ever(Get.find<CartService>().removalNotice, (notice) {
      if (notice == null) return;
      Get.snackbar(
        notice.title,
        notice.message,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    });
  }

  @override
  void dispose() {
    _notices?.dispose();
    _notices = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
