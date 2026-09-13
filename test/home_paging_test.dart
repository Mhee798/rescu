import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Regression tests for RES-104.
///
/// The feed's two writers — `refreshDeals` and `loadMore` — share `deals` and
/// the page counter, and neither can tell that the other moved the ground under
/// it while it was awaiting. The bug is not the shared write: it is that the
/// counter ends up describing a list it does not match, which only shows up as
/// duplicate cards on the *next* page load.
///
/// Reproduced here rather than on device. Twenty-four attempts to hit the race
/// through `adb shell input swipe` failed: pull-to-refresh only arms at the top
/// of the list while `onLoading` fires at the bottom, and a scripted gesture
/// round trip takes longer than the backend's 250-950 ms, so the load always
/// finished first. The orderings below are the ones a thumb produces; the
/// scripted repo just makes them deterministic.
void main() {
  // `loadComplete()` schedules a post-frame callback, so the controller needs a
  // binding even though no widget is involved.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedRepo repo;
  late HomeController controller;

  setUp(() {
    repo = ScriptedRepo();
    controller = HomeController(dealRepo: repo);
  });

  /// The feed should always be pages 1..k concatenated: ids 1, 2, 3 … with no
  /// repeats and no gaps. Every failure mode in this ticket breaks that shape.
  void expectContiguousFeed(HomeController c) {
    final ids = c.deals.map((d) => d.id).toList();
    expect(
      ids,
      List<int>.generate(ids.length, (i) => i + 1),
      reason: 'feed should be pages 1..k in order — got ${ids.length} items, '
          '${ids.length - ids.toSet().length} of them duplicates',
    );
  }

  /// Loads page 1 so the tests start from a feed the user could be looking at.
  Future<void> seed() async {
    unawaited(controller.refreshDeals());
    await repo.settle(1);
  }

  test('refresh landing before an in-flight loadMore does not duplicate a page',
      () async {
    await seed();

    unawaited(controller.loadMore()); // page 2 in flight
    unawaited(controller.refreshDeals()); // user pulls down
    await repo.settle(1); // refresh returns first
    await repo.settle(2); // the older load returns after it
    expectContiguousFeed(controller);

    // The damage only surfaces here: the counter says page 1, the list holds
    // two pages, so the next load asks for a page that is already present.
    unawaited(controller.loadMore());
    await repo.settleAll();
    expectContiguousFeed(controller);
  });

  test('an in-flight loadMore landing before the refresh leaves a clean feed',
      () async {
    await seed();

    unawaited(controller.loadMore());
    unawaited(controller.refreshDeals());
    await repo.settle(2); // the load returns first
    await repo.settle(1); // the refresh overwrites it
    expectContiguousFeed(controller);

    unawaited(controller.loadMore());
    await repo.settleAll();
    expectContiguousFeed(controller);
  });

  test('a loadMore started while a refresh is in flight does not leave a gap',
      () async {
    await seed();
    unawaited(controller.loadMore());
    await repo.settle(2);
    unawaited(controller.loadMore());
    await repo.settle(3); // feed is now pages 1-3

    unawaited(controller.refreshDeals()); // pull down, still loading
    unawaited(controller.loadMore()); // and the footer fires again
    await repo.settleAll();
    expectContiguousFeed(controller);
  });

  test('a second refresh while the first is in flight wins', () async {
    await seed();

    unawaited(controller.refreshDeals());
    unawaited(controller.refreshDeals());
    await repo.settleAll();
    expectContiguousFeed(controller);
    expect(controller.deals.length, 20);
  });

  test('a failed page load does not make the next one refetch page 1',
      () async {
    await seed();

    // `getDeals` cannot fail today, so this is a latent path rather than a
    // live one. It is covered because the page counter used to be advanced
    // before the request and rolled back in the catch, and a rollback that
    // runs after a concurrent refresh has already reset the counter takes it
    // below one — from which the next load refetches the feed's first page on
    // top of itself.
    unawaited(controller.loadMore()); // page 2 in flight
    unawaited(controller.refreshDeals()); // and a pull-down resets the counter
    await repo.settle(1);
    await repo.fail(2);

    unawaited(controller.loadMore());
    await repo.settleAll();
    expectContiguousFeed(controller);
  });

  /// `loadComplete()` defers to a post-frame callback, and `tester.pump()`
  /// produces no frame unless one is already scheduled — with a static widget
  /// tree nothing schedules one, so the callback would never run and both
  /// cases below would report the footer stuck no matter what the code did.
  Future<void> pumpAFrame(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  // The list assertions above cannot see what the user's pull gesture is left
  // looking at. A guard that returns early is only correct if everything it
  // skipped is either unnecessary or done by someone else, and these two cases
  // are what tells those apart. `testWidgets` because `loadComplete()` defers
  // to a post-frame callback.
  testWidgets('a load suppressed by an in-flight refresh releases the footer',
      (tester) async {
    // A frame has to be produced for `loadComplete()`'s post-frame callback to
    // run, and the binding produces none until something is pumped.
    await tester.pumpWidget(const SizedBox());
    unawaited(controller.refreshDeals());
    repo.completeNow(1);
    await tester.pump();

    // SmartRefresher puts the footer into `loading` before it calls onLoading.
    controller.refreshController.footerMode!.value = LoadStatus.loading;
    unawaited(controller.refreshDeals()); // the pull-down, still in flight
    unawaited(controller.loadMore()); // and the footer fires
    await pumpAFrame(tester);

    expect(
      controller.refreshController.footerStatus,
      LoadStatus.idle,
      reason: 'nothing else settles the footer — refreshDeals reaches only '
          'refreshCompleted(), which touches the header — so a silent return '
          'leaves the spinner up and kills pull-up for the session',
    );
    repo.completeNow(1);
    await tester.pump();
  });

  testWidgets(
      'a load suppressed by another load leaves the footer to that load',
      (tester) async {
    await seed();

    controller.refreshController.footerMode!.value = LoadStatus.loading;
    unawaited(controller.loadMore()); // this one owns the footer
    unawaited(controller.loadMore()); // suppressed, and must not touch it
    await pumpAFrame(tester);
    expect(controller.refreshController.footerStatus, LoadStatus.loading);

    repo.completeNow(2);
    await pumpAFrame(tester);
    expect(controller.refreshController.footerStatus, LoadStatus.idle,
        reason: 'the in-flight load settles it on its way out');
  });

  test('a stale refresh landing last does not overwrite the newer one',
      () async {
    await seed();

    unawaited(controller.refreshDeals()); // the first pull
    unawaited(controller.refreshDeals()); // the user pulls again
    // The newer request answers first and says the catalog is now one page…
    await repo.settle(1, totalPages: 1, newest: true);
    expect(controller.hasMore, isFalse);
    // …and the older one arrives afterwards still describing seven.
    await repo.settle(1, totalPages: 7);

    expect(controller.hasMore, isFalse,
        reason: 'the older response should have been discarded, not written');
  });

  test('a stale loadMore landing after a refresh does not write its metadata',
      () async {
    await seed();

    unawaited(controller.loadMore()); // page 2 in flight
    unawaited(controller.refreshDeals()); // user pulls down
    await repo.settle(1, totalPages: 1); // refresh: catalog is one page now
    expect(controller.hasMore, isFalse);
    await repo.settle(2, totalPages: 7); // the older load, from before

    expect(controller.hasMore, isFalse,
        reason: 'the pre-refresh response should have been discarded');
    expectContiguousFeed(controller);
  });
}

/// A `DealRepo` that hands out a `Completer` per page so a test decides which
/// response lands first.
class ScriptedRepo extends DealRepo {
  ScriptedRepo() : super(api: FakeApiService());

  static const _pageSize = 20;
  static const _totalPages = 7;

  final _pending = <int, List<Completer<PagedResponseModel<DealModel>>>>{};
  final requested = <int>[];

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) {
    requested.add(page);
    final completer = Completer<PagedResponseModel<DealModel>>();
    _pending.putIfAbsent(page, () => []).add(completer);
    return completer.future;
  }

  /// Completes the oldest outstanding request for [page] and lets the
  /// continuation run.
  ///
  /// [totalPages] stands in for "how fresh is this response". Two responses for
  /// the same page are otherwise identical, so without it a stale one being
  /// written over a newer one is invisible.
  Future<void> settle(int page,
      {int totalPages = _totalPages, bool newest = false}) async {
    final queue = _pending[page];
    expect(queue, isNotNull, reason: 'no request outstanding for page $page');
    expect(queue, isNotEmpty, reason: 'no request outstanding for page $page');
    final completer = newest ? queue!.removeLast() : queue!.removeAt(0);
    completer.complete(_response(page, totalPages));
    if (queue.isEmpty) _pending.remove(page);
    await Future<void>.delayed(Duration.zero);
  }

  /// Fails the oldest outstanding request for [page].
  Future<void> fail(int page) async {
    final queue = _pending[page];
    expect(queue, isNotNull, reason: 'no request outstanding for page $page');
    queue!.removeAt(0).completeError(
        const ApiException('boom', statusCode: 500), StackTrace.empty);
    if (queue.isEmpty) _pending.remove(page);
    await Future<void>.delayed(Duration.zero);
  }

  /// Completes the oldest outstanding request for [page] without awaiting.
  /// `testWidgets` runs inside `FakeAsync`, where `Future.delayed` does not
  /// resolve on its own, so a widget test completes here and pumps instead.
  void completeNow(int page) {
    final queue = _pending[page];
    expect(queue, isNotNull, reason: 'no request outstanding for page $page');
    queue!.removeAt(0).complete(_response(page, _totalPages));
    if (queue.isEmpty) _pending.remove(page);
  }

  /// Completes everything still outstanding, oldest page first.
  Future<void> settleAll() async {
    while (_pending.isNotEmpty) {
      await settle((_pending.keys.toList()..sort()).first);
    }
  }

  PagedResponseModel<DealModel> _response(int page, [int? totalPages]) =>
      PagedResponseModel(
        items: List.generate(
          _pageSize,
          (i) => _deal((page - 1) * _pageSize + i + 1),
        ),
        page: page,
        totalPages: totalPages ?? _totalPages,
      );
}

DealModel _deal(int id) => DealModel(
      id: id,
      name: 'deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 10,
      price: 5,
      currencyCode: 'THB',
      quantityLeft: 1,
      storeId: 1,
      storeName: 'store',
      storeAddress: 'address',
      lat: 0,
      lng: 0,
      rating: null,
      tags: const [],
      pickupWindow: PickupWindowModel(
        start: DateTime.utc(2026, 1, 1, 1),
        end: DateTime.utc(2026, 1, 1, 3),
      ),
      flashSaleEndsAt: null,
    );
