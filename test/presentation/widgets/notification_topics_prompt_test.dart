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

/// An [Account] whose [getPrefs] throws once, then succeeds - standing in for
/// a transient failure that a "Try again" tap should recover from.
class _FlakyOnceAccount extends Account {
  _FlakyOnceAccount() : super(Client());

  int _getPrefsCalls = 0;

  @override
  Future<models.Preferences> getPrefs() async {
    _getPrefsCalls++;
    if (_getPrefsCalls == 1) {
      throw AppwriteException('offline');
    }
    // Nothing stored: loadTopicIntent() falls through to the defaults.
    return models.Preferences(data: const <String, dynamic>{});
  }
}

/// An [Account] that can load intent fine but always fails to persist it -
/// standing in for a failure discovered only once the student taps Continue.
class _SaveFailingAccount extends Account {
  _SaveFailingAccount() : super(Client());

  @override
  Future<models.Preferences> getPrefs() async =>
      models.Preferences(data: const <String, dynamic>{});

  @override
  Future<models.User> updatePrefs({required Map prefs}) async {
    throw AppwriteException('offline');
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

  /// Presents [NotificationTopicsPrompt] the way `_showTopicsPrompt` actually
  /// does: as a non-dismissible, non-draggable modal bottom sheet pushed on
  /// top of a real route. Tests that drive the sheet all the way to a
  /// `Navigator.pop()` (via "Skip for now") need somewhere under it for that
  /// pop to reveal - unlike this file's other tests, which pump the prompt
  /// directly as the app's only route and never pop it.
  Future<void> pumpPrompt(
    WidgetTester tester,
    NotificationService service,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notificationServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (_) => const NotificationTopicsPrompt(),
                ),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the switches from a migrated legacy intent instead of the '
      'hardcoded defaults, showing a spinner while the load is in flight', (
    tester,
  ) async {
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
  });

  testWidgets(
    'shows a retry state instead of fabricated defaults when the intent '
    'load throws (finding 1): editable switches at that point could only be '
    "showing invented values, and Continue would persist them over the "
    "student's real migrated intent the instant it runs - the exact "
    'data-loss this prompt exists to prevent',
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

      // Not stuck loading...
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // ...and no editable switches wearing fabricated values either - that
      // is the bug this state exists to prevent, not a cosmetic detail.
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.text('Could not load your notification settings.'),
        findsOneWidget,
      );

      // The sheet is non-dismissible, so both ways forward must be offered.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip for now'), findsOneWidget);
    },
  );

  testWidgets(
    '"Try again" recovers from a failed load and shows the real switches '
    '(finding 1)',
    (tester) async {
      final service = NotificationService.withAccount(_FlakyOnceAccount());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [notificationServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: Scaffold(body: NotificationTopicsPrompt()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The fixture's first load fails - the state itself is covered in
      // detail by the test above.
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNWidgets(4));
      for (final tile in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(tile.value, isTrue);
      }
      // This is `ready`, not `loadFailed` wearing switches.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Skip for now'), findsNothing);
    },
  );

  testWidgets(
    '"Skip for now" after a failed load closes the sheet without ever '
    'saving anything (finding 1)',
    (tester) async {
      final service = NotificationService.withAccount(_ThrowingAccount());

      await pumpPrompt(tester, service);
      expect(find.byType(NotificationTopicsPrompt), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Skip for now'));
      await tester.pumpAndSettle();

      // Back to whatever was under the non-dismissible sheet - never
      // stranded.
      expect(find.byType(NotificationTopicsPrompt), findsNothing);
      expect(find.text('open sheet'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed save keeps the sheet open with a recoverable error, leaving '
    "the student's choices exactly as they left them (finding 2)",
    (tester) async {
      final service = NotificationService.withAccount(_SaveFailingAccount());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [notificationServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: Scaffold(body: NotificationTopicsPrompt()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Turn "News" off before saving, so the assertion below can tell a
      // preserved choice from a silently-reset one.
      await tester.tap(find.widgetWithText(SwitchListTile, 'News'));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not save your choices'),
        findsOneWidget,
      );
      // Still editable, still showing exactly what the student set - not
      // fabricated, and not silently reverted either.
      expect(find.byType(SwitchListTile), findsNWidgets(4));
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'News'),
            )
            .value,
        isFalse,
      );
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip for now'), findsOneWidget);
    },
  );

  testWidgets(
    '"Skip for now" after a failed save closes the sheet without retrying '
    'it (finding 2)',
    (tester) async {
      final service = NotificationService.withAccount(_SaveFailingAccount());

      await pumpPrompt(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Skip for now'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Skip for now'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationTopicsPrompt), findsNothing);
      expect(find.text('open sheet'), findsOneWidget);
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
