import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../app_config.dart';
import '../../routes/routes.dart';
import '../shared_widget/deal_card.dart';
import '../shared_widget/shimmer_deal_card.dart';
import 'home_controller.dart';
import 'widget/flash_deals_section.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Three narrow `Obx` scopes instead of one around the whole `Scaffold`.
    // The old scope read `scrollOffset.value`, which `_onScroll` wrote on every
    // scroll frame, so the entire feed subtree was reconstructed once per
    // rendered frame — measured at 23 rebuilds in 23 frames. Nothing inside it
    // changed except an elevation flag and whether the FAB was present.
    return Scaffold(
      // `Scaffold.appBar` takes a `PreferredSizeWidget`, which `Obx` is not, so
      // the reactive scope goes inside a `PreferredSize` rather than around it.
      // `kToolbarHeight` restates what `AppBar.preferredSize` used to compute:
      // correct while this AppBar has no `bottom:` and no `toolbarHeight:`, and
      // the place to update if either is ever added.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(
          () => AppBar(
            elevation: controller.isScrolled.value ? 2 : 0,
            shadowColor: Colors.black26,
            title: const Row(
              children: [
                Icon(Icons.eco, color: AppConfig.primaryGreen),
                SizedBox(width: 8),
                Text('Rescu',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => Get.toNamed(Routes.search),
              ),
              IconButton(
                icon: const Icon(Icons.map_outlined),
                onPressed: () => Get.toNamed(Routes.map),
              ),
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => Get.toNamed(Routes.orders),
              ),
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => Get.toNamed(Routes.cart),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'deeplink') _showDeepLinkDialog(context);
                  if (value == 'analytics') Get.toNamed(Routes.analyticsDebug);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'deeplink', child: Text('Simulate deep link…')),
                  PopupMenuItem(
                      value: 'analytics', child: Text('Analytics debug')),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return ListView(
            children: const [
              ShimmerDealCard(),
              ShimmerDealCard(),
              ShimmerDealCard(),
            ],
          );
        }
        final deals = controller.visibleDeals;
        // One or two header slots ahead of the cards, so `itemBuilder` can map
        // an index onto either a header or a deal without materialising a
        // second list of widgets.
        final hasFlashRail = controller.flashDeals.isNotEmpty;
        final headerCount = hasFlashRail ? 2 : 1;
        return SmartRefresher(
          controller: controller.refreshController,
          enablePullDown: true,
          enablePullUp: true,
          onRefresh: controller.refreshDeals,
          onLoading: controller.loadMore,
          // `ListView.builder`, not `ListView(children: [...])`. The spread
          // constructed one `DealCard` object per loaded deal every time this
          // scope ran — measured at 385 constructed against 93 actually built,
          // the rest discarded unbuilt — and `SliverChildListDelegate` holds
          // that whole list. The builder constructs only what the viewport and
          // cache extent ask for.
          child: ListView.builder(
            controller: controller.scrollController,
            itemCount: headerCount + deals.length + 1,
            itemBuilder: (context, index) {
              if (hasFlashRail && index == 0) {
                return FlashDealsSection(deals: controller.flashDeals);
              }
              if (index == headerCount - 1) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Text('Nearby deals',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      FilterChip(
                        label: const Text('Pickup today'),
                        selected: controller.todayOnly.value,
                        onSelected: (v) => controller.todayOnly.value = v,
                      ),
                    ],
                  ),
                );
              }
              final dealIndex = index - headerCount;
              if (dealIndex < deals.length) {
                return DealCard(deal: deals[dealIndex]);
              }
              return const SizedBox(height: 24);
            },
          ),
        );
      }),
      // `Obx` cannot return null, and `Scaffold` animates its FAB only when
      // *it* rebuilds with a different `floatingActionButton`
      // (`_FloatingActionButtonTransition.didUpdateWidget`). A narrow `Obx`
      // rebuilds itself and never the `Scaffold`, so that path is unreachable
      // here and the built-in scale-in is gone whatever the children are. The
      // old code got the animation for free because the whole `Scaffold` was
      // inside the `Obx` — the thing this ticket removed.
      //
      // Animating here restores it without giving the scope back. The button
      // stays mounted and is scaled instead, so it keeps its layout slot while
      // hidden; `IgnorePointer` is what stops a zero-scale button from
      // swallowing taps, since `Transform` affects paint and hit-testing but
      // not layout.
      floatingActionButton: Obx(() {
        final show = controller.showScrollToTop.value;
        return IgnorePointer(
          ignoring: !show,
          child: AnimatedScale(
            scale: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: FloatingActionButton.small(
              onPressed: controller.scrollToTop,
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        );
      }),
    );
  }

  void _showDeepLinkDialog(BuildContext context) {
    final textController =
        TextEditingController(text: 'rescu://open/deal?id=42&source=push');
    Get.dialog(
      AlertDialog(
        title: const Text('Simulate deep link'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            helperText: 'e.g. rescu://open/deal?id=42&source=push',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final uri = Uri.tryParse(textController.text.trim());
              Get.back();
              if (uri == null) return;
              final route =
                  uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
              Get.toNamed(route);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
