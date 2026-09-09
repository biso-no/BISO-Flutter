import 'package:biso/data/models/checkout_quote.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckoutQuote.fromJson', () {
    test('parses the server quote a buyer is shown and charged', () {
      final quote = CheckoutQuote.fromJson({
        'currency': 'NOK',
        'subtotal': 358.2,
        'discountTotal': 39.8,
        'total': 358.2,
        'membershipApplied': true,
        'memberDiscountPercent': 10.0,
        'items': [
          {
            'productId': 'prod-1',
            'name': 'BISO Hoodie',
            'title': 'BISO Hoodie — Large',
            'quantity': 2,
            'unitPrice': 179.1,
            'lineTotal': 358.2,
            'variationId': 'var-l',
            'variationName': 'Large',
          },
        ],
      });

      expect(quote.total, 358.2);
      expect(quote.membershipApplied, isTrue);
      expect(quote.items.single.variationName, 'Large');
      expect(
        quote.originalTotal,
        closeTo(398, 0.001),
        reason: 'the pre-discount total is what the saving is shown against',
      );
    });

    test('falls back to the line name when no title was composed', () {
      final quote = CheckoutQuote.fromJson({
        'items': [
          {'productId': 'p', 'name': 'Ticket', 'quantity': 1, 'unitPrice': 10},
        ],
      });

      expect(quote.items.single.title, 'Ticket');
    });

    test('tolerates a response with no items', () {
      final quote = CheckoutQuote.fromJson(const <String, dynamic>{});
      expect(quote.items, isEmpty);
      expect(quote.currency, 'NOK');
      expect(quote.total, 0);
    });
  });

  group('PaymentProviderAvailability', () {
    test('is offerable only when enabled and configured', () {
      final availability = PaymentProviderAvailability.fromJson({
        'id': 'vipps',
        'available': true,
        'enabled': true,
        'configured': true,
      });

      expect(availability?.provider, PaymentProvider.vipps);
      expect(availability?.available, isTrue);
    });

    test('reports an admin-disabled provider as unavailable', () {
      final availability = PaymentProviderAvailability.fromJson({
        'id': 'stripe',
        'available': false,
        'enabled': false,
        'configured': true,
      });

      expect(availability?.provider, PaymentProvider.stripe);
      expect(availability?.available, isFalse);
      expect(availability?.enabled, isFalse);
    });

    test('drops a provider the app does not know how to render', () {
      expect(
        PaymentProviderAvailability.fromJson({
          'id': 'klarna',
          'available': true,
        }),
        isNull,
      );
    });

    test('defaults every flag to false when the field is absent', () {
      final availability = PaymentProviderAvailability.fromJson({
        'id': 'vipps',
      });

      expect(availability?.available, isFalse);
      expect(availability?.enabled, isFalse);
      expect(availability?.configured, isFalse);
    });
  });
}
