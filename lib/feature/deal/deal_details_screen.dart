import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_config.dart';
import '../../model/deal_model.dart';
import '../shared_widget/the_network_image.dart';
import 'deal_details_controller.dart';

class DealDetailsScreen extends GetView<DealDetailsController> {
  const DealDetailsScreen({super.key, this.tag});

  /// The deal id from the route. `GetView` passes this straight to `Get.find`,
  /// and `DealDetailsBinding` registers under the same value, so two `/deal`
  /// routes for different deals resolve to different controllers.
  // `GetView.tag` is a final field, not a getter, so shadowing it is the only
  // way to supply a tag — it is the pattern GetView's own doc comment shows.
  @override
  // ignore: overridden_fields
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Two narrow Obx scopes rather than one around the Scaffold: the deal
      // settles once, but the add-to-bag control must not be live before it
      // does, and nothing else at this level is reactive.
      body: Obx(() {
        final deal = controller.deal;
        if (deal != null) {
          return _DealBody(deal: deal, controller: controller);
        }
        final error = controller.loadError;
        if (error != null) {
          return _WithBackButton(
            child: _LoadFailure(
              message: error,
              onRetry: controller.canRetry ? controller.retry : null,
            ),
          );
        }
        return const _WithBackButton(
          child: Center(child: CircularProgressIndicator()),
        );
      }),
      bottomSheet: Obx(
        () => controller.deal == null
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.addToCart,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add to bag'),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The loaded screen gets its back arrow from `SliverAppBar`. The loading and
/// failure states have no app bar of their own, so without this the failure
/// state is a screen the user can be parked on with no way out.
class _WithBackButton extends StatelessWidget {
  final Widget child;

  const _WithBackButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Mirrors what AppBar does: a back affordance only when there is
        // somewhere to go back to, rather than a button that does nothing.
        if (Navigator.of(context).canPop())
          const SafeArea(
            child: Align(alignment: Alignment.topLeft, child: BackButton()),
          ),
      ],
    );
  }
}

/// Shown only when the deal could not be fetched at all — a link pointing at a
/// deal the catalog no longer has, or a failed request. A deal that exists
/// still renders the real page.
class _LoadFailure extends StatelessWidget {
  final String message;

  /// Null when retrying cannot change the outcome; the action is then not
  /// offered at all rather than offered and inert.
  final Future<void> Function()? onRetry;

  const _LoadFailure({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Takes the controller as a parameter rather than extending `GetView`. The
/// controller is registered under a tag, and a nested `GetView` has no way to
/// know which one — it would call the untagged `Get.find` and throw.
class _DealBody extends StatelessWidget {
  final DealModel deal;
  final DealDetailsController controller;

  const _DealBody({required this.deal, required this.controller});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: TheNetworkImage(url: deal.imageUrl, fit: BoxFit.cover),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.name,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(deal.storeName,
                    style:
                        TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                Text(deal.storeAddress,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('฿${deal.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppConfig.primaryGreen)),
                    const SizedBox(width: 8),
                    Text('฿${deal.originalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.lineThrough)),
                    const Spacer(),
                    Obx(() => Chip(
                          avatar:
                              const Icon(Icons.inventory_2_outlined, size: 16),
                          label: Text('${controller.quantityLeft ?? '-'} left'),
                        )),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E5E2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, color: AppConfig.primaryGreen),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pickup window',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey)),
                          Text(
                            '${deal.pickupWindow.label}'
                            '${deal.pickupWindow.isToday ? ' · today' : ''}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (deal.pickupWindow.isOpenNow)
                        const Chip(
                          label: Text('Open now'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('What you get',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(deal.description,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.grey.shade800)),
                if (deal.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: deal.tags
                        .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
