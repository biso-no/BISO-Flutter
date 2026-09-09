import 'package:biso/core/utils/appwrite_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appwriteImageUrl', () {
    test('passes through an existing full URL unchanged', () {
      const url =
          'https://appwrite.biso.no/v1/storage/buckets/media/files/abc/view?project=biso';
      expect(appwriteImageUrl(url), url);
    });

    test('builds a view URL from a bare file id', () {
      final r = appwriteImageUrl('6a99004100362c968d1e');
      expect(r, contains('/storage/buckets/media/files/6a99004100362c968d1e/view'));
      expect(r, contains('project=biso'));
    });

    test('returns null for null or empty input', () {
      expect(appwriteImageUrl(null), isNull);
      expect(appwriteImageUrl(''), isNull);
      expect(appwriteImageUrl('   '), isNull);
    });
  });

  group('appwriteImageUrls', () {
    test('normalizes a mixed list of ids and URLs', () {
      const url =
          'https://appwrite.biso.no/v1/storage/buckets/media/files/xyz/view?project=biso';
      final r = appwriteImageUrls([url, '6a99004100362c968d1e', '', null]);

      expect(r.length, 2);
      expect(r.first, url);
      expect(r.last, contains('6a99004100362c968d1e'));
    });

    test('returns empty list for a non-list value', () {
      expect(appwriteImageUrls(null), isEmpty);
      expect(appwriteImageUrls('not-a-list'), isEmpty);
    });
  });
}
