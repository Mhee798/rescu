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

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  Worker? _cartWorker;

  @override
  void onInit() {
    super.onInit();
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
    _deal.value = deal;
    _quantityLeft.value = deal.quantityLeft;
    analytics.logEvent('deal_details_view', {
      'deal_id': deal.id,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    _watchCart();
  }

  Future<void> _loadFromRoute() async {
    final id = int.tryParse(Get.parameters['id'] ?? '');
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
    cartService.add(deal);
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
