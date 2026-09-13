import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/expiry_builder.dart';
import 'package:rescu/feature/shared_widget/flash_sale_countdown.dart';
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
}

/// A fixed instant so every expectation in this file is exact rather than
/// "within a second".
final DateTime _start = DateTime(2026, 9, 13, 12);
