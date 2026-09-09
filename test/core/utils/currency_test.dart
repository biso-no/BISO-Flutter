import 'package:biso/core/utils/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatNok', () {
    test('drops the decimals on a whole-kroner price', () {
      expect(formatNok(399), 'NOK 399');
      expect(formatNok(399.0), 'NOK 399');
    });

    test('keeps the øre a member discount can produce', () {
      // 199 with 10% off is 179.10 — rounding that away would show a total the
      // buyer is not actually charged.
      expect(formatNok(179.1), 'NOK 179.10');
      expect(formatNok(99.5), 'NOK 99.50');
    });

    test('rounds a floating-point remainder to the nearest øre', () {
      expect(formatNok(0.1 + 0.2), 'NOK 0.30');
    });

    test('formats zero as free-of-decimals rather than blank', () {
      expect(formatNok(0), 'NOK 0');
    });
  });
}
