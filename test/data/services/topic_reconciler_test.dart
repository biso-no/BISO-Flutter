import 'package:biso/data/services/topic_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeTopicDiff', () {
    test('is empty when the device already matches what is wanted', () {
      final diff = computeTopicDiff(
        desired: {'general', 'news_oslo'},
        current: {'general': 'sub1', 'news_oslo': 'sub2'},
      );
      expect(diff.toCreate, isEmpty);
      expect(diff.toDelete, isEmpty);
      expect(diff.isEmpty, isTrue);
    });

    test('creates everything for a device with no subscriptions yet', () {
      final diff = computeTopicDiff(
        desired: {'general', 'news_oslo'},
        current: const {},
      );
      expect(diff.toCreate, {'general', 'news_oslo'});
      expect(diff.toDelete, isEmpty);
    });

    test('deletes what is no longer wanted', () {
      final diff = computeTopicDiff(
        desired: {'general'},
        current: {'general': 'sub1', 'news_oslo': 'sub2'},
      );
      expect(diff.toCreate, isEmpty);
      expect(diff.toDelete, {'news_oslo'});
    });

    test(
      'a campus move swaps the campus scope and keeps the national one, so a '
      'student who transfers stops getting the old campus feed',
      () {
        final diff = computeTopicDiff(
          desired: {'general', 'news_bergen', 'news_national'},
          current: {
            'general': 'sub1',
            'news_oslo': 'sub2',
            'news_national': 'sub3',
          },
        );
        expect(diff.toCreate, {'news_bergen'});
        expect(diff.toDelete, {'news_oslo'});
      },
    );

    test('turning everything off still keeps general', () {
      final diff = computeTopicDiff(
        desired: {'general'},
        current: {
          'general': 'sub1',
          'news_oslo': 'sub2',
          'events_oslo': 'sub3',
        },
      );
      expect(diff.toDelete, {'news_oslo', 'events_oslo'});
      expect(diff.toCreate, isEmpty);
    });
  });

  group('migrateLegacyIntent', () {
    test('renames the old products topic to shop', () {
      expect(
        migrateLegacyIntent(const {'products': false}),
        containsPair('shop', false),
      );
    });

    test(
      'drops expenses entirely - reimbursement updates become personal '
      'notifications, not a topic',
      () {
        final migrated = migrateLegacyIntent(const {'expenses': true});
        expect(migrated.containsKey('expenses'), isFalse);
      },
    );

    test('carries the unchanged topics across', () {
      final migrated = migrateLegacyIntent(const {
        'events': false,
        'jobs': true,
      });
      expect(migrated['events'], isFalse);
      expect(migrated['jobs'], isTrue);
    });

    test('defaults news on, since it had no old equivalent to carry over', () {
      expect(migrateLegacyIntent(const {'events': false})['news'], isTrue);
    });

    test('returns the defaults when there is nothing to migrate', () {
      final migrated = migrateLegacyIntent(null);
      expect(migrated['news'], isTrue);
      expect(migrated['events'], isTrue);
      expect(migrated['jobs'], isTrue);
      expect(migrated['shop'], isTrue);
    });

    test('produces exactly the four logical keys and no others', () {
      expect(
        migrateLegacyIntent(const {
          'products': true,
          'expenses': true,
          'orders': true,
        }).keys.toSet(),
        {'news', 'events', 'jobs', 'shop'},
      );
    });
  });
}
