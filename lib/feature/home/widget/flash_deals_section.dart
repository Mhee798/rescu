import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_config.dart';
import '../../../model/deal_model.dart';
import '../../../routes/routes.dart';
import '../../shared_widget/expiry_builder.dart';
import '../../shared_widget/flash_sale_countdown.dart';
import '../../shared_widget/the_network_image.dart';

/// Horizontal flash-sale rail.
class FlashDealsSection extends StatelessWidget {
  final List<DealModel> deals;

  const FlashDealsSection({super.key, required this.deals});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.bolt, color: Colors.red, size: 20),
              SizedBox(width: 4),
              Text('Flash sales',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: deals.length,
            itemBuilder: (context, index) {
              final deal = deals[index];
              return SizedBox(
                width: 200,
                // Wraps the whole tile: when the sale ends the tile stops being
                // tappable and changes how it reads, which is one rebuild at
                // the crossing rather than one a second. The countdown inside
                // is the part that changes every second.
                child: ExpiryBuilder(
                  endsAt: deal.flashSaleEndsAt,
                  builder: (context, expired) => Card(
                    color: Colors.white,
                    elevation: 0.5,
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: expired
                          ? null
                          : () => Get.toNamed(
                                Routes.dealRoute(deal.id, source: 'flash_rail'),
                                arguments: deal,
                              ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TheNetworkImage(
                              url: deal.imageUrl,
                              height: 90,
                              width: double.infinity),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(deal.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(deal.storeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey.shade600)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text('฿${deal.price.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppConfig.primaryGreen)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: expired
                                            ? Colors.grey.shade200
                                            : Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      // Once the sale is over the label is
                                      // fixed, so the live countdown comes out
                                      // rather than staying mounted printing
                                      // the same word: its `Obx` is subscribed
                                      // to the clock and would rebuild every
                                      // second, for every expired tile, for as
                                      // long as the rail is on screen.
                                      child: deal.flashSaleEndsAt == null
                                          ? const SizedBox.shrink()
                                          : expired
                                              ? Text('Expired',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey.shade600,
                                                  ))
                                              : FlashSaleCountdown(
                                                  endsAt: deal.flashSaleEndsAt!,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.red.shade700,
                                                  ),
                                                ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
