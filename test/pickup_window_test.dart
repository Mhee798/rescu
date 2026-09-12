import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

/// Regression tests for RES-106.
///
/// The API sends instants as ISO-8601 UTC strings. The bug was that the client
/// read those instants as if they were already wall-clock times.
void main() {
  // A bakery open 06:00-09:30 in a UTC+7 market, as the backend serialises it.
  const startUtc = '2026-09-12T23:00:00Z';
  const endUtc = '2026-09-13T02:30:00Z';

  PickupWindowModel window() => PickupWindowModel.fromJson({
        'start': startUtc,
        'end': endUtc,
      });

  String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  group('label', () {
    test('renders the local clock, not the UTC clock', () {
      final start = DateTime.parse(startUtc).toLocal();
      final end = DateTime.parse(endUtc).toLocal();

      expect(window().label, '${hhmm(start)} – ${hhmm(end)}');
    });

    test('does not print the raw UTC fields', () {
      // The pre-fix implementation produced exactly this.
      if (DateTime.now().timeZoneOffset == Duration.zero) {
        // On a UTC machine local and UTC coincide and there is nothing to
        // catch; the assertion above still covers the conversion.
        return;
      }
      expect(window().label, isNot('23:00 – 02:30'));
    });
  });

  group('isTodayAt', () {
    test('is true on the local day the window starts', () {
      final startLocal = DateTime.parse(startUtc).toLocal();

      expect(window().isTodayAt(startLocal), isTrue);
    });

    test('is false the next day', () {
      final startLocal = DateTime.parse(startUtc).toLocal();

      expect(
        window().isTodayAt(startLocal.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('is false a month later — the old check compared only the day', () {
      final startLocal = DateTime.parse(startUtc).toLocal();
      final sameDayNextMonth = DateTime(
        startLocal.year,
        startLocal.month + 1,
        startLocal.day,
        12,
      );

      expect(window().isTodayAt(sameDayNextMonth), isFalse);
    });

    test('is false a year later on the same date', () {
      final startLocal = DateTime.parse(startUtc).toLocal();
      final sameDateNextYear = DateTime(
        startLocal.year + 1,
        startLocal.month,
        startLocal.day,
        12,
      );

      expect(window().isTodayAt(sameDateNextYear), isFalse);
    });
  });

  group('instant-based members are unaffected by the UTC flag', () {
    test('isOpenNow and untilStart agree with each other', () {
      final w = window();

      // Both read DateTime.now(), so assert the relationship rather than a
      // fixed value: a window that has not started yet cannot be open.
      if (w.untilStart > Duration.zero) {
        expect(w.isOpenNow, isFalse);
      }
    });
  });
}
