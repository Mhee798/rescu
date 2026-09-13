import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';
import 'clock_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
/// Something the bag did on its own that the user has to be told about.
///
/// Carries an [id] because `Rx` swallows a write equal to the value it already
/// holds, and two identical notices in a row are a real sequence — the same
/// deal cannot end twice, but two separate ones can produce the same wording.
class CartRemovalNotice {
  const CartRemovalNotice({
    required this.id,
    required this.title,
    required this.message,
  });

  final int id;
  final String title;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is CartRemovalNotice && other.id == id;

  @override
  int get hashCode => id;
}

class CartService extends GetxService {
  CartService({required this.clock});

  final ClockService clock;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// Removes flash-sale lines whose sale has ended.
  ///
  /// This lives here rather than on a card because a bag survives the screen
  /// it was filled from: the deal whose sale runs out may have no card built
  /// anywhere, and it still has to leave the bag. The subscription is on the
  /// same clock the countdowns use, so the bag and the badge cannot disagree
  /// about when a sale ended.
  Worker? _tick;

  /// Published rather than shown. A service calling `Get.snackbar` needs an
  /// overlay to exist, which ties the bag to a mounted UI — it throws outright
  /// in a unit test — and puts presentation in the layer that owns the data.
  /// `CartNoticeHost` listens for these and shows them.
  final removalNotice = Rxn<CartRemovalNotice>();
  int _noticeSequence = 0;

  @override
  void onInit() {
    super.onInit();
    _tick = ever(clock.nowRx, (_) => _dropEndedFlashSales());
  }

  @override
  void onClose() {
    // This service is `permanent`, so the worker outlives every screen either
    // way — but owning it explicitly is the habit RES-103 exists to enforce.
    _tick?.dispose();
    _tick = null;
    super.onClose();
  }

  void _dropEndedFlashSales() {
    final now = clock.now;
    final ended = items.where((item) {
      final endsAt = item.deal.flashSaleEndsAt;
      return endsAt != null && !now.isBefore(endsAt);
    }).toList();
    if (ended.isEmpty) return;

    final endedIds = ended.map((item) => item.deal.id).toSet();
    items.removeWhere((item) => endedIds.contains(item.deal.id));
    _recount();

    for (final item in ended) {
      LogService.log('cart: dropped ${item.deal.id}, flash sale ended');
    }
    removalNotice.value = CartRemovalNotice(
      id: ++_noticeSequence,
      title: ended.length == 1 ? 'Flash sale ended' : 'Flash sales ended',
      message: ended.length == 1
          ? '${ended.single.deal.name} was removed from your bag.'
          : '${ended.length} items were removed from your bag.',
    );
  }

  void add(DealModel deal) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _recount();
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      items.removeWhere((i) => i.deal.id == dealId);
    } else {
      items.refresh();
    }
    _recount();
  }

  void remove(int dealId) {
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }
}
