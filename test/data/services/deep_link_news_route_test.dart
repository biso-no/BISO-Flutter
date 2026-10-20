import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a link without an article opens the list', () {
    expect(newsRouteFor(null), '/explore/news');
    expect(newsRouteFor(''), '/explore/news');
    expect(newsRouteFor('  '), '/explore/news');
  });

  test('an id or slug opens the article', () {
    expect(newsRouteFor('n1'), '/explore/news/n1');
    expect(newsRouteFor('autumn-news'), '/explore/news/autumn-news');
  });

  test('the key is encoded as one path segment', () {
    expect(newsRouteFor('a b'), '/explore/news/a%20b');
    expect(newsRouteFor('a/b'), '/explore/news/a%2Fb');
  });

  test('biso://news?id=n1 resolves to the article route', () {
    final uri = Uri.parse('biso://news?id=n1');
    expect(uri.host, 'news');
    expect(newsRouteFor(uri.queryParameters['id']), '/explore/news/n1');
  });
}
