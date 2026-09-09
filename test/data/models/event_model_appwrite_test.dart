import 'package:biso/data/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> get realEventRow => {
  r'$id': 'evt_kd',
  'slug': 'kd',
  'status': 'published',
  'campus_id': '1',
  'department_id': '25',
  'start_date': '2026-09-22T10:00:00.000+00:00',
  'end_date': '2026-09-24T16:00:00.000+00:00',
  'image':
      'https://appwrite.biso.no/v1/storage/buckets/media/files/6a8b12f80004a404560c/view?project=biso',
  'price': null,
  'member_price': null,
  'pricing_mode': 'free',
  'member_only': false,
  'location': 'BI Oslo',
  'location_mode': 'physical',
  'capacity': 5000,
  'waitlist': false,
  'category': 'career',
  'cover_pattern': 'dotted',
  'tags': ['Networking', 'Free', 'Career'],
  'ticket_url': null,
  'translation_refs': [
    {
      'locale': 'no',
      'title': 'Karrieredagene',
      'description': '<p>Bli med.</p>',
      'short_description': 'Bli med.',
      'content_type': 'event',
    },
    {
      'locale': 'en',
      'title': 'Carreer Days',
      'description': '<p>Join us.</p>',
      'short_description': 'Join us.',
      'content_type': 'event',
    },
  ],
};

void main() {
  group('EventModel.fromAppwriteRow', () {
    test('parses scalar columns from a real row', () {
      final e = EventModel.fromAppwriteRow(realEventRow);

      expect(e.id, 'evt_kd');
      expect(e.slug, 'kd');
      expect(e.campusId, '1');
      expect(e.departmentId, '25');
      expect(e.location, 'BI Oslo');
      expect(e.locationMode, 'physical');
      expect(e.capacity, 5000);
      expect(e.category, 'career');
      expect(e.tags, ['Networking', 'Free', 'Career']);
      expect(e.pricingMode, 'free');
      expect(e.memberOnly, isFalse);
      expect(e.startDate, DateTime.parse('2026-09-22T10:00:00.000+00:00'));
      expect(e.endDate, DateTime.parse('2026-09-24T16:00:00.000+00:00'));
    });

    test('resolves title and description for the requested locale', () {
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'en').title,
          'Carreer Days');
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'no').title,
          'Karrieredagene');
    });

    test('falls back to Norwegian for an unknown locale', () {
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'de').title,
          'Karrieredagene');
    });

    test('keeps a full image URL intact', () {
      expect(EventModel.fromAppwriteRow(realEventRow).images.single,
          contains('6a8b12f80004a404560c'));
    });

    test('normalizes a bare image file id into a URL', () {
      final row = {...realEventRow, 'image': '6a8b12f80004a404560c'};
      expect(EventModel.fromAppwriteRow(row).images.single,
          contains('/storage/buckets/media/files/6a8b12f80004a404560c/view'));
    });

    test('tolerates a row with no translations', () {
      final row = {...realEventRow}..remove('translation_refs');
      final e = EventModel.fromAppwriteRow(row);

      expect(e.title, '');
      expect(e.description, '');
    });

    test('falls back to the epoch sentinel when start_date is missing', () {
      final row = {...realEventRow}..remove('start_date');
      final e = EventModel.fromAppwriteRow(row);

      expect(e.startDate, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });

    test('falls back to the epoch sentinel when start_date is unparseable',
        () {
      final row = {...realEventRow, 'start_date': 'not-a-date'};
      final e = EventModel.fromAppwriteRow(row);

      expect(e.startDate, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });
  });

  group('EventModel value equality', () {
    test('two instances differing only in a new field are not equal', () {
      final a = EventModel.fromAppwriteRow(realEventRow);
      final withDifferentCapacity =
          EventModel.fromAppwriteRow({...realEventRow, 'capacity': 1});
      final withDifferentTags = EventModel.fromAppwriteRow({
        ...realEventRow,
        'tags': ['Different'],
      });

      expect(a.capacity, isNot(equals(withDifferentCapacity.capacity)));
      expect(a, isNot(equals(withDifferentCapacity)));
      expect(a, isNot(equals(withDifferentTags)));
    });

    test('two identical instances are equal', () {
      final a = EventModel.fromAppwriteRow(realEventRow);
      final b = EventModel.fromAppwriteRow(realEventRow);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
