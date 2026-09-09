import 'package:biso/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeTopicSubscriptions', () {
    test(
      'treats the empty-list shape Appwrite returns for an empty map as '
      '"nothing stored", so the caller falls back to defaults instead of '
      'throwing',
      () {
        expect(decodeTopicSubscriptions(const <dynamic>[]), isNull);
      },
    );

    test('reads a stored map of topic flags', () {
      expect(
        decodeTopicSubscriptions(<String, dynamic>{
          'events': true,
          'expenses': false,
        }),
        <String, bool>{'events': true, 'expenses': false},
      );
    });

    test('reports an absent value as nothing stored', () {
      expect(decodeTopicSubscriptions(null), isNull);
    });

    test('ignores entries whose value is not a bool rather than throwing', () {
      expect(
        decodeTopicSubscriptions(<String, dynamic>{
          'events': true,
          'jobs': 'yes',
        }),
        <String, bool>{'events': true},
      );
    });
  });

  group('decodeTopicSubscriberIds', () {
    test(
      'returns an empty map for the empty-list shape rather than throwing — '
      'this is the value every account has before it first subscribes',
      () {
        expect(decodeTopicSubscriberIds(const <dynamic>[]), isEmpty);
      },
    );

    test('reads stored subscriber ids', () {
      expect(
        decodeTopicSubscriberIds(<String, dynamic>{'events': 'sub123'}),
        <String, String>{'events': 'sub123'},
      );
    });

    test('ignores entries whose value is not a string', () {
      expect(
        decodeTopicSubscriberIds(<String, dynamic>{
          'events': 'sub123',
          'jobs': 42,
        }),
        <String, String>{'events': 'sub123'},
      );
    });
  });
}
