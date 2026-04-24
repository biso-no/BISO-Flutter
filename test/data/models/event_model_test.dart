import 'package:biso/data/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventModel.fromFunctionEvent', () {
    test('uses WooCommerce-style ACF metadata campus when available', () {
      final event = EventModel.fromFunctionEvent({
        'id': 123,
        'title': {'rendered': 'Campus Event'},
        'content': {'rendered': '<p>Event description</p>'},
        'start_date': '2026-06-01T18:00:00',
        'venue': {'name': 'BI Oslo'},
        'organizer': {'id': 9, 'name': 'BISO Oslo'},
        'meta_data': [
          {'key': 'campus', 'value': '1'},
          {'key': '_campus', 'value': 'field_66a3ba7e42ec0'},
        ],
      }, campusId: '2');

      expect(event.id, '123');
      expect(event.campusId, '1');
      expect(event.title, 'Campus Event');
      expect(event.venue, 'BI Oslo');
    });

    test('uses acf campus before request campus fallback', () {
      final event = EventModel.fromFunctionEvent({
        'id': 456,
        'title': 'Bergen Event',
        'description': 'Description',
        'start_date': '2026-06-01T18:00:00',
        'acf': {'campus': '2'},
      }, campusId: '1');

      expect(event.campusId, '2');
    });

    test(
      'falls back to request campus when payload has no campus metadata',
      () {
        final event = EventModel.fromFunctionEvent({
          'id': 789,
          'title': 'Fallback Event',
          'description': 'Description',
          'start_date': '2026-06-01T18:00:00',
        }, campusId: '3');

        expect(event.campusId, '3');
      },
    );
  });
}
