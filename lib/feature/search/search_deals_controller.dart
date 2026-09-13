import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// The one request whose answer the screen is still waiting for.
  ///
  /// The backend answers short queries more slowly than long ones
  /// (`fake_api_service.dart:96`), so typing a word letter by letter sends
  /// requests in one order and receives them in very nearly the reverse. What
  /// arrives cannot be trusted to belong to the text in the box, and there is
  /// nothing in the response to check it against — `searchDeals` returns deals
  /// and no echo of the query — so the check has to be held here.
  ///
  /// The `Future` itself is the token rather than the query text or a counter.
  /// Comparing the text would let an older request for a query the user
  /// returned to overwrite a newer one for the same text, which reads as
  /// correct and is not: the two carry different stock numbers once a checkout
  /// has run (`fake_api_service.dart:196`). A counter would close that too but
  /// says nothing about what it guards, and has to be remembered in the
  /// cleared-box branch, where this is simply null.
  Future<List<DealModel>>? _inFlight;

  void onQueryChanged(String query) {
    _search(query);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      // Dropping the token discards whatever is still on its way. `isLoading`
      // has to be cleared here rather than left to that response, because
      // after this line no response is allowed to clear it and the screen
      // would keep the spinner up (`search_screen.dart:24` checks it first).
      _inFlight = null;
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }
    // `results` deliberately keeps the previous query's items until the new
    // ones arrive — clearing here would flash an empty state between every
    // keystroke. That makes the controller's state knowingly stale for a few
    // hundred milliseconds, and what keeps it off the screen is the order of
    // the checks in the view: `isLoading` is tested before `results`
    // (`search_screen.dart:24`). The guarantee is display-level, not
    // state-level, and a change to that `Obx` — results under a small inline
    // spinner, say — would bring the reported symptom back without touching
    // this file.
    isLoading.value = true;
    hasSearched.value = true;
    // Captured before the await: after it, `_inFlight` may be someone else's.
    final request = dealRepo.search(query);
    _inFlight = request;
    try {
      final found = await request;
      if (!identical(request, _inFlight)) return;
      results.assignAll(found);
    } catch (e) {
      // Unreachable against this backend: `searchDeals`
      // (`fake_api_service.dart:95`) is a delay and a filter with no throw
      // path. Left as it was found rather than extended — if it could fail,
      // the live-failure branch would need `results.clear()` or an error
      // state, because logging and returning leaves the previous query's
      // results on screen under the new text, which is this ticket's symptom
      // arriving by another route.
      if (!identical(request, _inFlight)) return;
      LogService.error('search failed', e);
    } finally {
      // Only the request the screen is waiting for may take the spinner down.
      // An earlier one finishing first would hide it while the answer the user
      // is actually waiting for is still in flight.
      if (identical(request, _inFlight)) isLoading.value = false;
    }
  }
}
