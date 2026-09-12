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
      // Measured, not assumed: at offset zero `toLocal()` is the identity, so
      // the expectation above evaluates to '23:00 – 02:30' — which is exactly
      // what the pre-fix implementation produced. The whole label group is
      // therefore green against the bug here and covers nothing. Skip rather
      // than return, so a UTC run reports the blind spot instead of a pass.
      if (DateTime.now().timeZoneOffset == Duration.zero) {
        markTestSkipped(
            'local zone is UTC; the zone half of RES-106 is unobservable here');
        return;
      }
      expect(window().label, isNot('23:00 – 02:30'));
    });
  });

  // No test for `isToday` itself. It reads `DateTime.now()`, which is the whole
  // reason `isTodayAt` exists, and the only assertion available —
  // `isToday == isTodayAt(DateTime.now())` — restates the getter's body. It also
  // could not distinguish the variant it would be written to catch:
  // `isTodayAt(DateTime.now().toUtc())` is identical in behaviour, because
  // `isTodayAt` normalises its argument with `toLocal()`. Verified rather than
  // assumed. The delegation is covered by reading four lines, not by a test
  // that would only look like coverage.

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
    // These read DateTime.now(), so the fixture is built relative to now rather
    // than pinned to an instant. A fixed instant would quietly stop asserting
    // anything the moment wall-clock time passed it, while still reporting
    // green — the same failure mode the label group guards against.
    PickupWindowModel windowOffsetFromNow(Duration fromNow, Duration length) {
      final start = DateTime.now().toUtc().add(fromNow);
      return PickupWindowModel.fromJson({
        'start': start.toIso8601String(),
        'end': start.add(length).toIso8601String(),
      });
    }

    test('a window that has not started yet is not open', () {
      final w = windowOffsetFromNow(
        const Duration(hours: 2),
        const Duration(hours: 3),
      );

      expect(w.untilStart, greaterThan(Duration.zero));
      expect(w.isOpenNow, isFalse);
    });

    test('a window in progress is open', () {
      final w = windowOffsetFromNow(
        const Duration(hours: -1),
        const Duration(hours: 3),
      );

      expect(w.untilStart, lessThan(Duration.zero));
      expect(w.isOpenNow, isTrue);
    });

    test('a window that has already ended is not open', () {
      final w = windowOffsetFromNow(
        const Duration(hours: -5),
        const Duration(hours: 3),
      );

      expect(w.isOpenNow, isFalse);
    });
  });
}
