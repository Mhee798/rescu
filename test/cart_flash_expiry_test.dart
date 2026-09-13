import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/clock_service.dart';

/// F-1: "if it is already in the bag it is removed with a visible notice".
///
/// The bag outlives the screen it was filled from, so this cannot be a card's
/// job — the deal whose sale ends may have no card built anywhere. These tests
/// drive the clock the countdowns use and check the bag reacts on its own.
void main() {
  final start = DateTime(2026, 9, 13, 12);
  late ClockService clock;
  late CartService cart;

  setUp(() {
    // A long interval so the internal ticker never fires and overwrites the
    // time the test is setting; `flutter_test` fakes timers, not the wall
    // clock, so the published value is what has to move.
    clock = Get.put(ClockService(interval: const Duration(hours: 1)));
    clock.nowRx.value = start;
    cart = Get.put(CartService(clock: clock));
  });
  tearDown(Get.reset);

  void advanceTo(Duration fromStart) =>
      clock.nowRx.value = start.add(fromStart);

  test('a flash deal leaves the bag when its sale ends', () {
    cart.add(_deal(1, endsAt: start.add(const Duration(seconds: 30))));
    cart.add(_deal(2));
    expect(cart.items.length, 2);
    expect(cart.itemCount.value, 2);

    advanceTo(const Duration(seconds: 29));
    expect(cart.items.length, 2, reason: 'still a second to go');

    advanceTo(const Duration(seconds: 30));
    expect(cart.items.map((item) => item.deal.id), [2]);
    expect(cart.itemCount.value, 1, reason: 'the count has to follow');
  });

  test('quantity above one leaves with its line', () {
    final deal = _deal(1, endsAt: start.add(const Duration(seconds: 10)));
    cart.add(deal);
    cart.add(deal);
    cart.add(deal);
    expect(cart.itemCount.value, 3);

    advanceTo(const Duration(seconds: 10));
    expect(cart.items, isEmpty);
    expect(cart.itemCount.value, 0);
    expect(cart.total, 0);
  });

  test('deals with no flash sale are never touched', () {
    cart.add(_deal(1));
    cart.add(_deal(2));

    advanceTo(const Duration(days: 3));
    expect(cart.items.length, 2);
  });

  test('several ending on the same tick go together', () {
    cart.add(_deal(1, endsAt: start.add(const Duration(seconds: 5))));
    cart.add(_deal(2, endsAt: start.add(const Duration(seconds: 5))));
    cart.add(_deal(3));

    advanceTo(const Duration(seconds: 5));
    expect(cart.items.map((item) => item.deal.id), [3]);
  });

  test('a deal added after its sale ended is dropped on the next tick', () {
    // The details screen blocks this, but the bag is the thing that has to be
    // right; an expired line must not be able to sit there unnoticed.
    cart.add(_deal(1, endsAt: start.subtract(const Duration(seconds: 1))));
    expect(cart.items.length, 1);

    advanceTo(const Duration(seconds: 1));
    expect(cart.items, isEmpty);
  });
}

DealModel _deal(int id, {DateTime? endsAt}) => DealModel(
      id: id,
      name: 'deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 10,
      price: 5,
      currencyCode: 'THB',
      quantityLeft: 9,
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
      flashSaleEndsAt: endsAt,
    );
