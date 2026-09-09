import 'package:biso/data/models/shop_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShopOrderStatus', () {
    test('treats authorized as settled, as the server already does', () {
      // Vipps authorises before capture, and the server decrements stock and
      // books the revenue on either — so showing "pending" here would be a lie.
      expect(ShopOrderStatus.authorized.isSuccessful, isTrue);
      expect(ShopOrderStatus.paid.isSuccessful, isTrue);
    });

    test('separates a terminal failure from a payment still in flight', () {
      expect(ShopOrderStatus.cancelled.isFailure, isTrue);
      expect(ShopOrderStatus.failed.isFailure, isTrue);
      expect(ShopOrderStatus.pending.isFailure, isFalse);
      expect(ShopOrderStatus.pending.isPending, isTrue);
    });

    test('falls back to pending for an unknown or missing status', () {
      expect(ShopOrderStatus.fromValue(null), ShopOrderStatus.pending);
      expect(ShopOrderStatus.fromValue('who-knows'), ShopOrderStatus.pending);
    });

    test('a refund is neither a success nor a failed payment', () {
      expect(ShopOrderStatus.refunded.isSuccessful, isFalse);
      expect(ShopOrderStatus.refunded.isFailure, isFalse);
    });
  });

  group('ShopOrder.fromJson', () {
    test('parses the API order view', () {
      final order = ShopOrder.fromJson({
        'id': 'order-1',
        'status': 'paid',
        'currency': 'NOK',
        'subtotal': 398.0,
        'discountTotal': 100.0,
        'total': 398.0,
        'membershipApplied': true,
        'memberDiscountPercent': 20.0,
        'createdAt': '2026-09-01T10:00:00.000+00:00',
        'paymentProvider': 'vipps',
        'receiptUrl': 'https://receipt.example/1',
        'items': [
          {
            'name': 'BISO Hoodie — Large',
            'quantity': 2,
            'unitPrice': 199.0,
            'lineTotal': 398.0,
            'productId': 'prod-1',
            'variationName': 'Large',
            'customFields': [
              {'id': 'attendee_name', 'label': 'Attendee name', 'value': 'Kari'},
            ],
          },
        ],
      });

      expect(order.status, ShopOrderStatus.paid);
      expect(order.itemCount, 2);
      expect(order.membershipApplied, isTrue);
      expect(order.items.single.customFields.single.value, 'Kari');
      expect(order.createdAt?.year, 2026);
    });

    test('derives a missing line total from unit price and quantity', () {
      final order = ShopOrder.fromJson({
        'id': 'order-2',
        'status': 'pending',
        'items': [
          {'name': 'Ticket', 'quantity': 3, 'unitPrice': 50.0},
        ],
      });

      expect(order.items.single.lineTotal, 150.0);
    });

    test('tolerates an order with no items', () {
      final order = ShopOrder.fromJson({'id': 'order-3', 'status': 'failed'});
      expect(order.items, isEmpty);
      expect(order.itemCount, 0);
      expect(order.status, ShopOrderStatus.failed);
    });
  });

  group('ShopOrder.fromAppwriteRow', () {
    test('parses a row with its nested lines, variation and answers', () {
      final order = ShopOrder.fromAppwriteRow({
        r'$id': 'order-9',
        r'$createdAt': '2026-08-20T09:30:00.000+00:00',
        'status': 'paid',
        'currency': 'NOK',
        'subtotal': 449.0,
        'discount_total': 50.0,
        'total': 449.0,
        'membership_applied': true,
        'member_discount_percent': 10.0,
        'payment_provider': 'vipps',
        'payment_receipt_url': 'https://receipt.example/9',
        'order_items': [
          {
            'name': 'BISO Hoodie — Large',
            'quantity': 1,
            'unit_price': 449.0,
            'line_total': 449.0,
            'product': {r'$id': 'prod-1'},
            'variation': {r'$id': 'var-l', 'name': 'Large'},
            'field_answers': [
              {
                'field_key': 'second',
                'label': 'Second question',
                'value': 'b',
                'sort_order': 1,
              },
              {
                'field_key': 'first',
                'label': 'First question',
                'value': 'a',
                'sort_order': 0,
              },
            ],
          },
        ],
      });

      expect(order.id, 'order-9');
      expect(order.status, ShopOrderStatus.paid);
      expect(order.receiptUrl, 'https://receipt.example/9');
      final item = order.items.single;
      expect(item.productId, 'prod-1');
      expect(item.variationName, 'Large');
      expect(
        item.customFields.map((answer) => answer.label).toList(),
        ['First question', 'Second question'],
        reason: 'answers are shown in the order they were asked',
      );
    });

    test('reads a relationship returned as a bare id', () {
      final order = ShopOrder.fromAppwriteRow({
        r'$id': 'order-10',
        'status': 'pending',
        'order_items': [
          {'name': 'Ticket', 'quantity': 1, 'unit_price': 10.0, 'product': 'p1'},
        ],
      });

      expect(order.items.single.productId, 'p1');
    });

    test('falls back to the legacy receipt column', () {
      final order = ShopOrder.fromAppwriteRow({
        r'$id': 'order-11',
        'status': 'paid',
        'receipt_link': 'https://legacy.example/receipt',
      });

      expect(order.receiptUrl, 'https://legacy.example/receipt');
    });

    test('tolerates a row with no nested lines', () {
      final order = ShopOrder.fromAppwriteRow({
        r'$id': 'order-12',
        'status': 'cancelled',
      });

      expect(order.items, isEmpty);
      expect(order.status, ShopOrderStatus.cancelled);
    });
  });
}
