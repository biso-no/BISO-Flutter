import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a vacancy id or slug opens that vacancy', () {
    // biso://job?id=<id>
    expect(jobRouteFor('6702f1c2'), '/explore/volunteer/6702f1c2');
    // https://biso.no/app/jobs/<slug>
    expect(jobRouteFor('event-crew'), '/explore/volunteer/event-crew');
  });

  test('a link without a vacancy opens the list', () {
    expect(jobRouteFor(null), '/explore/volunteer');
    expect(jobRouteFor('  '), '/explore/volunteer');
  });

  test('an odd slug cannot reach another route', () {
    expect(jobRouteFor('a/apply'), '/explore/volunteer/a%2Fapply');
  });
}
