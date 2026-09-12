import 'package:get/get.dart';

import '../feature/deal/deal_details_controller.dart';

class DealDetailsBinding extends Bindings {
  @override
  void dependencies() {
    // Tagged by the deal id in the route. Without a tag every `/deal` push
    // shares one instance key, so a deep link arriving while another deal is
    // already open finds the existing controller, skips `onInit`, and shows the
    // deal that was already there. `Get.parameters` is assigned during route
    // resolution, before bindings run, so it is the incoming route's id here.
    Get.lazyPut(
      () => DealDetailsController(
        dealRepo: Get.find(),
        cartService: Get.find(),
        analytics: Get.find(),
      ),
      tag: Get.parameters['id'],
    );
  }
}
