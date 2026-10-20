import 'package:biso/data/services/local_notification_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('channelIdFor', () {
    test('urgent pushes use the urgent channel', () {
      expect(
        channelIdFor(<String, dynamic>{'category': 'urgent'}),
        kUrgentChannelId,
      );
      expect(kUrgentChannelId, 'biso_urgent');
    });

    test('every other push uses the default channel', () {
      expect(
        channelIdFor(<String, dynamic>{'category': 'event'}),
        kDefaultChannelId,
      );
      expect(channelIdFor(<String, dynamic>{}), kDefaultChannelId);
      expect(kDefaultChannelId, 'biso_default');
    });
  });
}
