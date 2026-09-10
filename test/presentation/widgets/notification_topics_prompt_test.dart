import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/presentation/widgets/notification_topics_prompt.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [Account] whose [getPrefs] does not resolve until [release] is called,
/// so the test can observe the prompt's loading state deterministically
/// instead of racing the seed load against the first pump.
class _GatedFakeAccount extends Account {
  _GatedFakeAccount(this._prefs) : super(Client());

  final Map<String, dynamic> _prefs;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<models.Preferences> getPrefs() async {
    await _gate.future;
    return models.Preferences(data: Map<String, dynamic>.from(_prefs));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Constructing an Appwrite Client asks path_provider for a cookie
    // directory, which has no implementation under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets(
    'seeds the switches from a migrated legacy intent instead of the '
    'hardcoded defaults, showing a spinner while the load is in flight',
    (tester) async {
      final account = _GatedFakeAccount(<String, dynamic>{
        'topic_subscriptions': <String, dynamic>{
          'products': false,
          'events': false,
        },
      });
      final service = NotificationService.withAccount(account);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [notificationServiceProvider.overrideWithValue(service)],
          // A Scaffold, not just MaterialApp, because the switches are
          // Material components; in production they get their Material
          // ancestor from the showModalBottomSheet route this widget is
          // always opened in.
          child: const MaterialApp(
            home: Scaffold(body: NotificationTopicsPrompt()),
          ),
        ),
      );

      // The load hasn't resolved yet: the loading treatment is showing, and
      // the switches (which would otherwise flash the wrong defaults for a
      // frame) do not exist yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);

      account.release();
      await tester.pumpAndSettle();

      bool valueFor(String label) {
        return tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label))
            .value;
      }

      // Migrated from the legacy map: 'products' -> 'shop' off, 'events' off.
      expect(valueFor('Shop'), isFalse);
      expect(valueFor('Events'), isFalse);
      // Absent from the legacy map, so migrated to the default: on.
      expect(valueFor('News'), isTrue);
      expect(valueFor('Jobs'), isTrue);
    },
  );

  testWidgets(
    'falls back to the defaults, without getting stuck loading, when the '
    'intent load throws',
    (tester) async {
      final service = NotificationService.withAccount(_ThrowingAccount());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [notificationServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: Scaffold(body: NotificationTopicsPrompt()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNWidgets(4));
      for (final tile in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(tile.value, isTrue);
      }
    },
  );
}

/// An [Account] whose [getPrefs] always throws, standing in for a network
/// failure during the prompt's seed load.
class _ThrowingAccount extends Account {
  _ThrowingAccount() : super(Client());

  @override
  Future<models.Preferences> getPrefs() async {
    throw AppwriteException('offline');
  }
}
