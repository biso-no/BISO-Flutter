import 'package:biso/core/utils/oslo_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  group('summer time switches at 01:00 UTC on the last Sunday', () {
    final cases = {
      // year: (march switch, october switch)
      2026: (DateTime.utc(2026, 3, 29, 1), DateTime.utc(2026, 10, 25, 1)),
      2027: (DateTime.utc(2027, 3, 28, 1), DateTime.utc(2027, 10, 31, 1)),
    };
    cases.forEach((year, switches) {
      final (spring, autumn) = switches;
      test('$year spring forward', () {
        expect(isOsloSummerTime(spring.subtract(ms)), isFalse);
        expect(isOsloSummerTime(spring), isTrue);
        expect(formatOsloClock(spring.subtract(ms)), '01:59:59');
        expect(formatOsloClock(spring), '03:00:00');
      });
      test('$year fall back', () {
        expect(isOsloSummerTime(autumn.subtract(ms)), isTrue);
        expect(isOsloSummerTime(autumn), isFalse);
        expect(formatOsloClock(autumn.subtract(ms)), '02:59:59');
        expect(formatOsloClock(autumn), '02:00:00');
      });
    });
  });

  test('an ordinary summer time is UTC+2', () {
    expect(formatOsloClock(DateTime.utc(2026, 7, 15, 12, 5, 9)), '14:05:09');
  });

  test('an ordinary winter time is UTC+1', () {
    expect(formatOsloClock(DateTime.utc(2026, 1, 15, 23, 30)), '00:30:00');
    expect(osloWallClock(DateTime.utc(2026, 1, 15, 23, 30)).day, 16);
  });

  test('a local DateTime gives the same answer as its UTC instant', () {
    final utc = DateTime.utc(2026, 9, 17, 10);
    expect(formatOsloClock(utc.toLocal()), formatOsloClock(utc));
  });

  group('membership dates are Oslo calendar days', () {
    setUpAll(initializeDateFormatting);

    test('a date-only value keeps its day', () {
      final day = DateTime.parse('2027-01-01');
      expect(formatOsloDate(day, 'en'), 'January 1, 2027');
      expect(formatOsloDate(day, 'no'), '1. januar 2027');
    });

    test('an instant is read in Oslo, not in the device time zone', () {
      // Midnight on 1 January in Oslo is still 31 December in UTC.
      final instant = DateTime.parse('2026-12-31T23:00:00Z');
      expect(osloCalendarDay(instant), DateTime.utc(2027, 1, 1));
      expect(formatOsloDate(instant, 'en'), 'January 1, 2027');
      expect(formatOsloDate(instant.toLocal(), 'en'), 'January 1, 2027');
    });

    test('today is the Oslo day', () {
      expect(
        osloToday(DateTime.utc(2026, 12, 31, 23, 30)),
        DateTime.utc(2027, 1, 1),
      );
    });
  });
}
