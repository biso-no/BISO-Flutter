import 'package:biso/core/utils/norwegian_bank_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('norwegian bank account utilities', () {
    test('accepts a valid MOD11 account number', () {
      expect(isValidNorwegianBankAccount('86011117947'), isTrue);
      expect(validateNorwegianBankAccount('8601 11 17947'), isNull);
    });

    test('rejects invalid account numbers', () {
      expect(isValidNorwegianBankAccount('86011117948'), isFalse);
      expect(
        validateNorwegianBankAccount('8601 11 17948'),
        'Invalid Norwegian bank account number',
      );
      expect(
        validateNorwegianBankAccount('1234'),
        'Norwegian bank account must be 11 digits',
      );
    });

    test('formats normalized account numbers for display', () {
      expect(
        formatNorwegianBankAccount('86011117947'),
        '8601 11 17947',
      );
    });
  });
}
