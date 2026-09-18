/// Oslo wall-clock time without the full time zone database.
///
/// Norway follows the EU rule: summer time (UTC+2) from 01:00 UTC on the last
/// Sunday of March until 01:00 UTC on the last Sunday of October, UTC+1
/// otherwise.
library;

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

DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % 7, 1);
}
