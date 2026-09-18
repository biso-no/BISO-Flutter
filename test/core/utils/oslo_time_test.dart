import 'package:biso/core/utils/oslo_time.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
