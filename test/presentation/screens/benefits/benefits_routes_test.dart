import 'package:biso/presentation/screens/benefits/benefits_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list route takes an optional campus', () {
    expect(benefitsPath, '/explore/benefits');
    expect(benefitsRoute(), '/explore/benefits');
    expect(benefitsRoute(campusParam: '3'), '/explore/benefits?campus=3');
    expect(
      benefitsRoute(campusParam: nationalCampusParam),
      '/explore/benefits?campus=national',
    );
  });

  test('a deal route always names its campus', () {
    expect(benefitRoute('b1', campusId: '3'), '/explore/benefits/b1?campus=3');
    expect(
      benefitRoute('b1', campusId: null),
      '/explore/benefits/b1?campus=national',
    );
  });

  test('"national" is the all-of-BISO list', () {
    expect(campusIdFromParam('national'), isNull);
    expect(campusIdFromParam(''), isNull);
    expect(campusIdFromParam('3'), '3');
    expect(pinnedCampusParam(null), 'national');
    expect(pinnedCampusParam('3'), '3');
  });
}
