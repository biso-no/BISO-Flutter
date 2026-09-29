/// Oslo wall-clock time without the full time zone database.
///
/// Norway follows the EU rule: summer time (UTC+2) from 01:00 UTC on the last
/// Sunday of March until 01:00 UTC on the last Sunday of October, UTC+1
/// otherwise.
library;

import 'package:intl/intl.dart';

/// [instant] as Oslo wall-clock time. The result is flagged UTC but its
/// fields are Oslo's: format it, never convert it again.
DateTime osloWallClock(DateTime instant) {
  final utc = instant.toUtc();
  return utc.add(Duration(hours: isOsloSummerTime(utc) ? 2 : 1));
}

bool isOsloSummerTime(DateTime instant) {
  final utc = instant.toUtc();
  final start = _lastSundayAtOneUtc(utc.year, DateTime.march);
  final end = _lastSundayAtOneUtc(utc.year, DateTime.october);
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// `HH:MM:SS` in Oslo.
String formatOsloClock(DateTime instant) {
  final t = osloWallClock(instant);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// The calendar day [value] names in Oslo, at midnight UTC so no later
/// conversion can move it.
///
/// A value with an offset (anything the server sends with `Z` or `+01:00`)
/// is an instant and is converted. A value without one is how a date-only
/// string like `2027-01-01` parses: its fields already are the day meant, so
/// the device's time zone is never applied to it.
DateTime osloCalendarDay(DateTime value) {
  final day = value.isUtc ? osloWallClock(value) : value;
  return DateTime.utc(day.year, day.month, day.day);
}

/// Today in Oslo, whatever time zone the device is set to.
DateTime osloToday([DateTime? now]) =>
    osloCalendarDay((now ?? DateTime.now()).toUtc());

/// [value] as a long date in [locale] ("1 January 2027", "1. januar 2027"),
/// read as an Oslo calendar day (see [osloCalendarDay]).
String formatOsloDate(DateTime value, String locale) =>
    DateFormat.yMMMMd(locale).format(osloCalendarDay(value));

DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % 7, 1);
}
