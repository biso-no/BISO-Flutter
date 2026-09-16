import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a paid return opens the membership screen on that order', () {
    expect(
      membershipRouteFor({'orderId': 'order-1', 'status': 'paid'}),
      '/profile/membership?orderId=order-1',
    );
  });

  test('a cancelled return carries the cancellation', () {
    expect(
      membershipRouteFor({'orderId': 'order-1', 'cancelled': '1'}),
      '/profile/membership?orderId=order-1&cancelled=1',
    );
  });

  test('a finished BI link asks the screen to re-check', () {
    expect(membershipRouteFor({'linked': '1'}), '/profile/membership?linked=1');
  });

  test('a bare link just opens the screen', () {
    expect(membershipRouteFor(const {}), '/profile/membership');
  });
}
