import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a link without an event opens the list', () {
    expect(eventRouteFor(null), '/explore/events');
    expect(eventRouteFor(''), '/explore/events');
    expect(eventRouteFor('  '), '/explore/events');
  });

  test('an event id or slug opens that event', () {
    expect(eventRouteFor('abc'), '/explore/events/abc');
  });

  test('an odd slug is encoded and cannot reach another route', () {
    expect(eventRouteFor('a b'), '/explore/events/a%20b');
    expect(eventRouteFor('a/b'), '/explore/events/a%2Fb');
  });
}
