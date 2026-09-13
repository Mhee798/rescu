import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class HomeController extends GetxController {
  final DealRepo dealRepo;

  HomeController({required this.dealRepo});

  final deals = <DealModel>[].obs;
  final flashDeals = <DealModel>[].obs;
  final isLoading = true.obs;
  final todayOnly = false.obs;

  /// Two threshold flags rather than the raw offset. `_onScroll` fires on every
  /// scroll frame, and an `Rx` that carries the offset therefore notifies on
  /// every one of them; `Rx.value` skips the notification when the value is
  /// unchanged (`rx_impl.dart:101`), so a bool flips twice per journey down the
  /// feed instead of 60-120 times a second. Nothing outside this class ever
  /// needed the offset itself — both uses were threshold comparisons.
  final isScrolled = false.obs;
  final showScrollToTop = false.obs;

  final scrollController = ScrollController();
  final refreshController = RefreshController();

  int _page = 1;
  int _totalPages = 1;
  bool _isFetchingMore = false;
  bool _isRefreshing = false;

  /// Incremented whenever a refresh replaces the feed. Both writers capture it
  /// before awaiting and compare it after, so a response that belongs to a list
  /// the user has already replaced is discarded instead of being written.
  int _generation = 0;

  bool get hasMore => _page < _totalPages;

  List<DealModel> get visibleDeals => todayOnly.value
      ? deals.where((d) => d.pickupWindow.isToday).toList()
      : deals.toList();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _initialLoad();
  }

  void _onScroll() {
    final offset = scrollController.offset;
    isScrolled.value = offset > 4;
    showScrollToTop.value = offset > 800;
  }

  Future<void> _initialLoad() async {
    isLoading.value = true;
    try {
      await Future.wait([refreshDeals(), _loadFlashDeals()]);
    } catch (e) {
      LogService.error('initial load failed', e);
    }
    isLoading.value = false;
  }

  Future<void> _loadFlashDeals() async {
    flashDeals.assignAll(await dealRepo.fetchFlashDeals());
  }

  Future<void> refreshDeals() async {
    final generation = ++_generation;
    _isRefreshing = true;
    try {
      final res = await dealRepo.fetchDeals(page: 1);
      // A newer refresh started while this one was in flight, so this response
      // describes a list that no longer exists. The newer one owns the screen
      // and will complete the header.
      if (generation != _generation) return;
      _page = 1;
      _totalPages = res.totalPages;
      deals.assignAll(res.items);
      refreshController.refreshCompleted();
    } finally {
      if (generation == _generation) _isRefreshing = false;
    }
  }

  Future<void> loadMore() async {
    // A refresh in flight is about to redefine which page comes next, so there
    // is no page worth asking for until it lands. Without this the request goes
    // out against the pre-refresh `_page` and appends a page from the middle of
    // the catalog to a list that has just been reset to its first page.
    if (_isFetchingMore || _isRefreshing) return;
    if (!hasMore) {
      refreshController.loadNoData();
      return;
    }
    _isFetchingMore = true;
    final generation = _generation;
    // The page number advances only once the response is in. Incrementing
    // before the request meant a concurrent refresh could reset `_page` and
    // leave the counter describing a list it no longer matches — which is this
    // ticket — and it needed the `_page--` in the catch block to undo itself.
    final requestedPage = _page + 1;
    try {
      final res = await dealRepo.fetchDeals(page: requestedPage);
      if (generation == _generation) {
        _page = requestedPage;
        _totalPages = res.totalPages;
        deals.addAll(res.items);
      }
    } catch (e) {
      LogService.error('loadMore failed', e);
    }
    _isFetchingMore = false;
    refreshController.loadComplete();
  }

  void scrollToTop() {
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  void onClose() {
    scrollController.dispose();
    refreshController.dispose();
    super.onClose();
  }
}
