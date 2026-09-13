import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_config.dart';
import 'repository/deal_repo.dart';
import 'repository/order_repo.dart';
import 'repository/store_repo.dart';
import 'feature/shared_widget/cart_notice_host.dart';
import 'routes/routes.dart';
import 'service/analytics_service.dart';
import 'service/cart_service.dart';
import 'service/clock_service.dart';
import 'service/fake_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const RescuApp());
}

Future<void> initDependencies() async {
  await Get.putAsync(() => FakeApiService().init(), permanent: true);
  Get.put(AnalyticsService(), permanent: true);
  // One ticker for every countdown in the app; see ClockService.
  Get.put(ClockService(), permanent: true);
  Get.put(CartService(clock: Get.find()), permanent: true);
  Get.lazyPut(() => DealRepo(api: Get.find()), fenix: true);
  Get.lazyPut(() => StoreRepo(api: Get.find()), fenix: true);
  Get.lazyPut(() => OrderRepo(api: Get.find()), fenix: true);
}

class RescuApp extends StatelessWidget {
  const RescuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppConfig.theme,
      initialRoute: Routes.home,
      getPages: Routes.pages,
      // Above the navigator so a bag notice reaches the user on any screen.
      builder: (context, child) =>
          CartNoticeHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
