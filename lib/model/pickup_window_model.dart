import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? ''),
      end: DateTime.parse(json['end'] as String? ?? ''),
    );
  }

  /// Human readable label, e.g. "17:30 – 21:00".
  ///
  /// `start` and `end` come from `DateTime.parse` of a `Z` string, so they are
  /// UTC instants. `DateFormat.format` reads the `DateTime`'s own fields rather
  /// than converting, so formatting them directly prints the UTC clock — a
  /// 06:00 window rendered as 23:00. `toLocal()` is what makes these wall-clock
  /// times instead of instants.
  String get label =>
      '${DateFormat('HH:mm').format(start.toLocal())} – ${DateFormat('HH:mm').format(end.toLocal())}';

  /// Whether pickup starts on the reader's current calendar day.
  bool get isToday => isTodayAt(DateTime.now());

  /// [isToday] with the current time supplied, so the comparison can be tested.
  ///
  /// "Today" is a property of the *user's* day, not the store's, so this is
  /// deliberately local-clock even if the API later sends per-store zones.
  bool isTodayAt(DateTime now) {
    final startLocal = start.toLocal();
    final today = now.toLocal();
    return startLocal.year == today.year &&
        startLocal.month == today.month &&
        startLocal.day == today.day;
  }

  /// Whether the store is currently accepting pickups.
  ///
  /// Correct as written: comparing two `DateTime`s compares instants, so the
  /// UTC flag does not matter here. Left alone deliberately.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  /// Also instant arithmetic, and also correct as written.
  Duration get untilStart => start.difference(DateTime.now());
}
