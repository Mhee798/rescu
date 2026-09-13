import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Regression tests for RES-101.
///
/// `searchDeals` is slower the shorter the query
/// (`fake_api_service.dart:96` — `max(0, 1200 - length * 280)`), so typing a
/// word letter by letter issues requests in the order the user typed and
/// receives them in very nearly the reverse. Nothing checked whether an
/// arriving response still belonged to the text in the box, so the first
/// letter's results — the slowest — won.
///
/// Reproduced on device first: typing "sushi" as one `adb shell input keyevent`
/// burst produced completions at 320, 442, 555, 1001 and 1238 ms for `sush`,
/// `sushi`, `sus`, `su` and `s`, and the screen settled on results for `s`
/// while the box read "sushi". The orderings below are those, made
/// deterministic.
void main() {
  late ScriptedSearchRepo repo;
  late SearchDealsController controller;

  setUp(() {
    repo = ScriptedSearchRepo();
    controller = SearchDealsController(dealRepo: repo);
  });

  /// Which response is on screen, identified by the marker the repo stamped
  /// into it. Two requests for the same query are otherwise identical, and
  /// telling them apart is the whole point of the A-B-A case below.
  int? shownMarker() =>
      controller.results.isEmpty ? null : controller.results.first.id;

  test('the slowest, earliest query does not win', () async {
    for (final q in ['s', 'su', 'sus', 'sush', 'sushi']) {
      controller.onQueryChanged(q);
    }

    // Arrival order measured on device: short queries last.
    await repo.settle('sush', marker: 4);
    await repo.settle('sushi', marker: 5);
    await repo.settle('sus', marker: 3);
    await repo.settle('su', marker: 2);
    await repo.settle('s', marker: 1);

    expect(shownMarker(), 5,
        reason: 'the box says "sushi"; the results must be its own');
  });

  test('an older request for the same query does not overwrite a newer one',
      () async {
    // sushi → sush → sushi. The first and third carry the same text, so a
    // guard that compares the query alone lets the first one through.
    controller.onQueryChanged('sushi');
    controller.onQueryChanged('sush');
    controller.onQueryChanged('sushi');

    await repo.settle('sushi', marker: 3, newest: true);
    expect(shownMarker(), 3);
    await repo.settle('sush', marker: 2);
    await repo.settle('sushi', marker: 1);

    expect(shownMarker(), 3,
        reason: 'the third request is the one the box is waiting on; the '
            'first carries the same text but older stock numbers');
  });

  test('clearing the box discards a response already in flight', () async {
    controller.onQueryChanged('sushi');
    controller.onQueryChanged('');

    await repo.settle('sushi', marker: 5);

    expect(controller.results, isEmpty,
        reason: 'the response was written into results before this fix and '
            'only went unseen because hasSearched gates the view');
    expect(controller.hasSearched.value, isFalse);
    expect(controller.isLoading.value, isFalse,
        reason: 'nothing else will clear it once the response is discarded');
  });

  test('a stale response does not hide the spinner for the live one', () async {
    controller.onQueryChanged('s');
    controller.onQueryChanged('sushi');

    await repo.settle('s', marker: 1); // the stale one answers first
    expect(controller.isLoading.value, isTrue,
        reason: 'the query in the box has not been answered yet');

    await repo.settle('sushi', marker: 5);
    expect(controller.isLoading.value, isFalse);
    expect(shownMarker(), 5);
  });

  test('a failed search for a query the user has left is ignored', () async {
    controller.onQueryChanged('s');
    controller.onQueryChanged('sushi');

    await repo.fail('s');
    await repo.settle('sushi', marker: 5);

    expect(shownMarker(), 5);
    expect(controller.isLoading.value, isFalse);
  });
}

/// A `DealRepo` that hands out a `Completer` per call so a test decides which
/// response lands first, and stamps a marker into each so two responses for the
/// same query can be told apart.
class ScriptedSearchRepo extends DealRepo {
  ScriptedSearchRepo() : super(api: FakeApiService());

  final _pending = <String, List<Completer<List<DealModel>>>>{};

  @override
  Future<List<DealModel>> search(String query) {
    final completer = Completer<List<DealModel>>();
    _pending.putIfAbsent(query, () => []).add(completer);
    return completer.future;
  }

  Future<void> settle(String query,
      {required int marker, bool newest = false}) async {
    final queue = _pending[query];
    expect(queue, isNotNull, reason: 'no request outstanding for "$query"');
    expect(queue, isNotEmpty, reason: 'no request outstanding for "$query"');
    final completer = newest ? queue!.removeLast() : queue!.removeAt(0);
    completer.complete([_deal(marker)]);
    if (queue.isEmpty) _pending.remove(query);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(String query) async {
    final queue = _pending[query];
    expect(queue, isNotNull, reason: 'no request outstanding for "$query"');
    queue!.removeAt(0).completeError(
        const ApiException('boom', statusCode: 500), StackTrace.empty);
    if (queue.isEmpty) _pending.remove(query);
    await Future<void>.delayed(Duration.zero);
  }
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
