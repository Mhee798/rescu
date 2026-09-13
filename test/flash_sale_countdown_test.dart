import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/expiry_builder.dart';
import 'package:rescu/feature/home/widget/flash_deals_section.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/feature/shared_widget/flash_sale_countdown.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/service/clock_service.dart';

/// Tests for F-1's two halves: the text that changes every second, and the
/// expiry that changes once.
void main() {
  group('formatFlashRemaining', () {
    test('mm:ss below an hour', () {
      expect(formatFlashRemaining(const Duration(minutes: 2, seconds: 5)),
          '02:05');
      expect(formatFlashRemaining(const Duration(seconds: 9)), '00:09');
      expect(formatFlashRemaining(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('hh:mm:ss from an hour up', () {
      expect(formatFlashRemaining(const Duration(hours: 1)), '01:00:00');
      expect(
        formatFlashRemaining(const Duration(hours: 12, minutes: 3, seconds: 4)),
        '12:03:04',
      );
    });

    test('null at or past zero, so the caller picks the expired wording', () {
      expect(formatFlashRemaining(Duration.zero), isNull);
      expect(formatFlashRemaining(const Duration(seconds: -1)), isNull);
    });

    test('rounds a part-second up, because the deal is still live', () {
      // Truncating would read 00:00 on a deal that is still tappable.
      expect(formatFlashRemaining(const Duration(milliseconds: 1)), '00:01');
      expect(formatFlashRemaining(const Duration(milliseconds: 1500)), '00:02');
      expect(
          formatFlashRemaining(
              const Duration(minutes: 59, seconds: 59, milliseconds: 500)),
          '01:00:00');
    });
  });

  // `flutter_test` fakes timers but not `DateTime.now()`, so pumping a second
  // fires the ticker and then sets it to the real wall clock, which has barely
  // moved. These tests drive the published time directly and give the internal
  // ticker an interval long enough that it never fires and overwrites them.
  late ClockService clock;

  void advanceTo(Duration fromStart) =>
      clock.nowRx.value = _start.add(fromStart);

  group('FlashSaleCountdown', () {
    setUp(() {
      clock = Get.put(ClockService(interval: const Duration(hours: 1)));
      clock.nowRx.value = _start;
    });
    tearDown(Get.reset);

    testWidgets('counts down once a second and then reads Expired',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlashSaleCountdown(
            endsAt: _start.add(const Duration(seconds: 3)),
          ),
        ),
      ));

      expect(find.text('00:03'), findsOneWidget);
      advanceTo(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('00:02'), findsOneWidget);
      advanceTo(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('only the Text rebuilds on a tick', (tester) async {
      var outerBuilds = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            outerBuilds++;
            return FlashSaleCountdown(
              endsAt: _start.add(const Duration(minutes: 5)),
            );
          }),
        ),
      ));
      expect(outerBuilds, 1);

      for (var i = 1; i <= 5; i++) {
        advanceTo(Duration(seconds: i));
        await tester.pump();
      }

      // The clock ticked five times and the text changed each time, but the
      // widget above the countdown was never rebuilt. That is the property F-1
      // asks for, stated as a test rather than as a claim about DevTools.
      expect(outerBuilds, 1);
      expect(find.text('04:55'), findsOneWidget);
    });
  });

  group('a feed-sized number of countdowns', () {
    setUp(() {
      clock = Get.put(ClockService(interval: const Duration(hours: 1)));
      clock.nowRx.value = _start;
    });
    tearDown(Get.reset);

    testWidgets('120 of them tick without rebuilding a single card',
        (tester) async {
      // The catalog only carries 14 flash deals, so the "100+ visible
      // countdowns" the feature asks about cannot be produced from the real
      // data, and `assets/data` is not editable. This builds the load instead.
      const count = 120;
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var listBuilds = 0;
      final cardBuilds = List<int>.filled(count, 0);

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          listBuilds++;
          return Column(
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  height: 40,
                  child: Builder(builder: (context) {
                    cardBuilds[i]++;
                    // Stand-in for a card: some chrome that must not be
                    // rebuilt, wrapped around the one live part.
                    return Row(
                      children: [
                        const Icon(Icons.bolt),
                        FlashSaleCountdown(
                          endsAt: _start.add(Duration(seconds: 90 + i)),
                        ),
                      ],
                    );
                  }),
                ),
            ],
          );
        }),
      ));

      expect(listBuilds, 1);
      expect(cardBuilds.every((builds) => builds == 1), isTrue);
      expect(find.text('01:30'), findsOneWidget);

      for (var second = 1; second <= 10; second++) {
        advanceTo(Duration(seconds: second));
        await tester.pump();
      }

      // Ten ticks across 120 live countdowns: every one of them is showing a
      // new number, and neither the list nor any card was rebuilt. This is the
      // property F-1 states, asserted directly rather than inferred from a
      // frame time.
      expect(find.text('01:20'), findsOneWidget);
      // The last card: 90 + 119 seconds to begin with, ten of them gone.
      expect(find.text('03:19'), findsOneWidget);
      expect(listBuilds, 1, reason: 'the list must not rebuild on a tick');
      expect(
        cardBuilds.where((builds) => builds != 1).length,
        0,
        reason: 'no card may rebuild on a tick',
      );
    });

    testWidgets('an expiring card rebuilds itself and no other',
        (tester) async {
      const count = 30;
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cardBuilds = List<int>.filled(count, 0);
      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                height: 40,
                // Only card 0 is about to expire.
                child: ExpiryBuilder(
                  endsAt: _start.add(Duration(seconds: i == 0 ? 2 : 600)),
                  builder: (context, expired) {
                    cardBuilds[i]++;
                    return Text(expired ? 'Expired $i' : 'Live $i');
                  },
                ),
              ),
          ],
        ),
      ));
      expect(cardBuilds.every((builds) => builds == 1), isTrue);

      advanceTo(const Duration(seconds: 2));
      await tester.pump();

      expect(cardBuilds[0], 2);
      expect(cardBuilds.skip(1).every((builds) => builds == 1), isTrue,
          reason: 'one deal expiring must not disturb its neighbours');
      expect(find.text('Expired 0'), findsOneWidget);
      expect(find.text('Live 29'), findsOneWidget);
    });
  });

  group('ExpiryBuilder', () {
    setUp(() {
      clock = Get.put(ClockService(interval: const Duration(hours: 1)));
      clock.nowRx.value = _start;
    });
    tearDown(Get.reset);

    testWidgets('rebuilds once when the deal expires, not once a second',
        (tester) async {
      var builds = 0;
      var expiredCallbacks = 0;
      await tester.pumpWidget(MaterialApp(
        home: ExpiryBuilder(
          endsAt: _start.add(const Duration(seconds: 3)),
          onExpired: () => expiredCallbacks++,
          builder: (context, expired) {
            builds++;
            return Text(expired ? 'Expired' : 'Live');
          },
        ),
      ));
      expect(builds, 1);
      expect(find.text('Live'), findsOneWidget);

      advanceTo(const Duration(seconds: 1));
      await tester.pump();
      advanceTo(const Duration(seconds: 2));
      await tester.pump();
      expect(builds, 1, reason: 'two ticks passed and nothing changed');

      advanceTo(const Duration(seconds: 3));
      await tester.pump();
      expect(builds, 2);
      expect(find.text('Expired'), findsOneWidget);
      expect(expiredCallbacks, 1);

      advanceTo(const Duration(seconds: 9));
      await tester.pump();
      expect(builds, 2, reason: 'expiry happens once');
      expect(expiredCallbacks, 1);
    });

    testWidgets('takes no subscription for a deal that is not a flash sale',
        (tester) async {
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: ExpiryBuilder(
          endsAt: null,
          builder: (context, expired) {
            builds++;
            return Text('$expired');
          },
        ),
      ));

      advanceTo(const Duration(seconds: 5));
      await tester.pump();
      expect(builds, 1);
      expect(find.text('false'), findsOneWidget);
    });

    testWidgets('starts expired when the sale is already over', (tester) async {
      var expiredCallbacks = 0;
      await tester.pumpWidget(MaterialApp(
        home: ExpiryBuilder(
          endsAt: _start.subtract(const Duration(seconds: 1)),
          onExpired: () => expiredCallbacks++,
          builder: (context, expired) => Text(expired ? 'Expired' : 'Live'),
        ),
      ));

      expect(find.text('Expired'), findsOneWidget);
      advanceTo(const Duration(seconds: 2));
      await tester.pump();
      // onExpired reports a crossing, and there was none to see.
      expect(expiredCallbacks, 0);
    });
  });

  group('an expired tile', () {
    setUp(() {
      clock = Get.put(ClockService(interval: const Duration(hours: 1)));
      clock.nowRx.value = _start;
    });
    tearDown(Get.reset);

    // Both surfaces that show a countdown have to take it back out at the
    // crossing, not leave it mounted printing the same word. A mounted
    // `FlashSaleCountdown` is subscribed to the clock, so it rebuilds once a
    // second for as long as the tile is on screen — which would make F-1's
    // "the per-second rebuild stops at the badge" false for expired deals.
    // The device measurement had four live countdowns and no expired ones, so
    // this case is only covered here.
    testWidgets('drops its countdown in the flash rail', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlashDealsSection(
            deals: [_deal(1, endsAt: _start.add(const Duration(seconds: 2)))],
          ),
        ),
      ));
      expect(find.byType(FlashSaleCountdown), findsOneWidget);

      advanceTo(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(FlashSaleCountdown), findsNothing);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('drops its countdown in the feed card', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DealCard(
            deal: _deal(1, endsAt: _start.add(const Duration(seconds: 2))),
          ),
        ),
      ));
      expect(find.byType(FlashSaleCountdown), findsOneWidget);

      advanceTo(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(FlashSaleCountdown), findsNothing);
      expect(find.text('EXPIRED'), findsOneWidget);
    });
  });
}

/// A fixed instant so every expectation in this file is exact rather than
/// "within a second".
final DateTime _start = DateTime(2026, 9, 13, 12);

DealModel _deal(int id, {DateTime? endsAt}) => DealModel(
      id: id,
      name: 'deal $id',
      description: '',
      imageUrl: 'https://example.invalid/$id.jpg',
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
