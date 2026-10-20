import 'package:biso/data/models/news_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> newsRow({
  String enDescription = '<p>Hello</p>',
  Object? image = '6a8b12f80004a404560c',
  bool withEn = true,
}) => {
  r'$id': 'news_1',
  r'$createdAt': '2026-10-01T08:30:00.000+00:00',
  'slug': 'big-news',
  'status': 'published',
  'campus_id': '2',
  'sticky': true,
  'author': 'Kari',
  'image': image,
  'translation_refs': [
    {
      'locale': 'no',
      'title': 'Stor nyhet',
      'description': '<p>Hei</p>',
      'short_description': 'Kort',
    },
    if (withEn)
      {
        'locale': 'en',
        'title': 'Big news',
        'description': enDescription,
        'short_description': 'Short',
      },
  ],
};

void main() {
  group('NewsModel.fromAppwriteRow', () {
    test('resolves the requested language', () {
      final n = NewsModel.fromAppwriteRow(newsRow(), locale: 'en');
      expect(n.title, 'Big news');
      expect(n.body, '<p>Hello</p>');
      expect(n.shortDescription, 'Short');
    });

    test('falls back to Norwegian when the language is missing', () {
      final n = NewsModel.fromAppwriteRow(newsRow(withEn: false), locale: 'en');
      expect(n.title, 'Stor nyhet');
    });

    test('parses scalar columns', () {
      final n = NewsModel.fromAppwriteRow(newsRow());
      expect(n.id, 'news_1');
      expect(n.slug, 'big-news');
      expect(n.campusId, '2');
      expect(n.author, 'Kari');
      expect(n.sticky, isTrue);
    });

    test('builds the image URL from a bare file id', () {
      final n = NewsModel.fromAppwriteRow(newsRow());
      expect(n.image, isNotNull);
      expect(n.image, contains('6a8b12f80004a404560c'));
      expect(n.image, startsWith('http'));
    });

    test('image is null when absent', () {
      expect(NewsModel.fromAppwriteRow(newsRow(image: null)).image, isNull);
    });

    test('publishedAt comes from \$createdAt', () {
      final n = NewsModel.fromAppwriteRow(newsRow());
      expect(n.publishedAt, DateTime.parse('2026-10-01T08:30:00.000+00:00'));
    });

    test('hasRenderableBody is false for Plate JSON and empty bodies', () {
      for (final body in ['[{"type":"p"}]', '{"a":1}', '', '  [1]']) {
        final n = NewsModel.fromAppwriteRow(
          newsRow(enDescription: body),
          locale: 'en',
        );
        expect(n.hasRenderableBody, isFalse, reason: body);
      }
    });

    test('hasRenderableBody is true for HTML', () {
      final n = NewsModel.fromAppwriteRow(
        newsRow(enDescription: '<p>Hi</p>'),
        locale: 'en',
      );
      expect(n.hasRenderableBody, isTrue);
    });
  });
}
