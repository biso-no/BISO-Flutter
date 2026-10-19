import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app sign-in link opens the verify screen', () {
    expect(
      magicLinkRouteFor(
        Uri.parse(
          'https://biso.no/auth/verify?userId=u1&secret=s%2B1'
          '&expire=2026-10-19T06%3A48%3A10.108%2B00%3A00&project=biso',
        ),
      ),
      '/auth/verify-magic-link?userId=u1&secret=s%2B1',
    );
  });

  test('the www host and the custom scheme open it too', () {
    expect(
      magicLinkRouteFor(
        Uri.parse('https://www.biso.no/auth/verify?userId=u1&secret=s1'),
      ),
      '/auth/verify-magic-link?userId=u1&secret=s1',
    );
    expect(
      magicLinkRouteFor(Uri.parse('biso://auth/verify?userId=u1&secret=s1')),
      '/auth/verify-magic-link?userId=u1&secret=s1',
    );
  });

  // biso.no's own sign-in returns carry a userId and secret too. Spending one
  // in the app would sign the app in and break the student's sign-in on the
  // website.
  test('the website sign-in returns are not the app sign-in link', () {
    for (final path in ['/auth/callback', '/auth/oauth', '/auth/login']) {
      expect(
        magicLinkRouteFor(
          Uri.parse('https://biso.no$path?userId=u1&secret=s1'),
        ),
        isNull,
        reason: path,
      );
    }
  });

  test('a link without its credentials is not one', () {
    expect(
      magicLinkRouteFor(Uri.parse('https://biso.no/auth/verify?userId=u1')),
      isNull,
    );
  });
}
