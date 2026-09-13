import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  final _deal = Rxn<DealModel>();
  DealModel? get deal => _deal.value;

  final _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final _loadError = RxnString();
  String? get loadError => _loadError.value;

  /// Whether re-running the fetch could produce a different outcome. A link
  /// carrying an unparseable id has nothing to retry — offering the action
  /// anyway gives the user a control that cannot change what they are looking
  /// at, and because the same message is re-assigned, the Rx does not even
  /// emit, so the screen does not so much as flicker.
  bool get canRetry => _routeDealId != null;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  Worker? _cartWorker;

  /// Captured once, while `onInit` is still on the route that opened this
  /// screen. `Get.parameters` is global navigation state that the next push
  /// replaces, and on the deep-link path `_adopt` now runs after an await.
  late final int? _routeDealId;
  late final String _source;

  @override
  void onInit() {
    super.onInit();
    _routeDealId = int.tryParse(Get.parameters['id'] ?? '');
    _source = Get.parameters['source'] ?? 'unknown';
    final arguments = Get.arguments;
    if (arguments is DealModel) {
      // Feed and flash-rail entry: the caller already holds the model, so this
      // is assigned before the first build and the screen never shows a spinner.
      _adopt(arguments);
    } else {
      // Deep-link entry: the route carries the id but no object. This is the
      // only route into the screen that has to go to the network.
      _loadFromRoute();
    }
  }

  void _adopt(DealModel deal) {
    // The deep-link fetch cannot be cancelled, so it can complete after the
    // user has popped the route and `onClose` has already run. Measured: with a
    // back press ~100ms in, `onClose` precedes the response every time. Without
    // this guard a screen the user cancelled subscribes to the session-long
    // CartService and re-checks that deal on every later add-to-bag.
    if (isClosed) return;
    _deal.value = deal;
    _quantityLeft.value = deal.quantityLeft;
    analytics.logEvent('deal_details_view', {
      'deal_id': deal.id,
      'source': _source,
    });
    _watchCart();
  }

  Future<void> _loadFromRoute() async {
    if (_isLoading.value) return;
    final id = _routeDealId;
    if (id == null) {
      _loadError.value = 'This link does not point at a deal.';
      return;
    }
    _isLoading.value = true;
    _loadError.value = null;
    try {
      _adopt(await dealRepo.fetchById(id));
    } on ApiException catch (e) {
      LogService.error('could not load deal $id', e);
      _loadError.value = e.statusCode == 404
          ? 'This deal is no longer available.'
          : 'We could not open this deal. Please try again.';
    } catch (e) {
      LogService.error('could not load deal $id', e);
      _loadError.value = 'We could not open this deal. Please try again.';
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> retry() => _loadFromRoute();

  /// Registered only once the deal is known. The callback reads the deal's id,
  /// so subscribing before it arrives would let a cart change during the
  /// deep-link fetch reach a deal that does not exist yet. Guarded against a
  /// second registration so a retry cannot end up with two subscriptions.
  void _watchCart() {
    if (_cartWorker != null) return;
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    _cartWorker = ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  @override
  void onClose() {
    // `ever` hands back a `Worker` precisely because the caller owns it: GetX
    // disposes this controller but knows nothing about the subscription it
    // registered on `CartService`, which outlives every screen. Bounding the
    // worker's life at this end, and at the other end with the `isClosed` guard
    // in `_adopt`, is what ties it to the controller — neither guard does it
    // alone.
    _cartWorker?.dispose();
    _cartWorker = null;
    super.onClose();
  }

  Future<void> _recheckAvailability() async {
    final deal = _deal.value;
    if (deal == null) return;
    LogService.log('re-checking availability for deal ${deal.id}');
    final fresh = await dealRepo.fetchById(deal.id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    final deal = _deal.value;
    if (deal == null) return;
    // A courtesy guard, not the enforcement. What guarantees the bag never
    // holds an expired flash line is `CartService`'s sweep
    // (`cart_service.dart:75`), which runs on the clock rather than on the
    // write; this one only saves the user a tap that would be undone a second
    // later by a removal notice.
    //
    // It has to read that same clock. `DateTime.now()` runs ahead of
    // `ClockService` by up to one tick, so in that window the card still shows
    // a live countdown and an enabled button while this guard rejects the tap
    // — the exact disagreement between badge and bag that one shared clock
    // exists to prevent.
    final endsAt = deal.flashSaleEndsAt;
    if (endsAt != null && !cartService.clock.now.isBefore(endsAt)) {
      Get.snackbar(
        'Flash sale ended',
        '${deal.name} is no longer on flash sale.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    cartService.add(deal);
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
