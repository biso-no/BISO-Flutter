import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart' hide Locale;
import 'package:appwrite/models.dart' as models;
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/update_decision.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/data/services/store_updater.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/notification_topics_prompt.dart';
import 'package:biso/presentation/widgets/update_recommended_dialog.dart';
import 'package:biso/presentation/widgets/update_required_overlay.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/update_prompt_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The update prompt, fixed to whatever the test sets it to.
class _FixedPrompt extends UpdatePromptNotifier {
  _FixedPrompt(this._initial);

  final UpdatePrompt _initial;
  bool snoozed = false;

  @override
  UpdatePrompt build() => _initial;

  @override
  Future<void> snooze() async {
    snoozed = true;
    state = UpdatePrompt.none;
  }

  /// Stands in for a fresh answer arriving.
  void answer(UpdatePrompt prompt) => state = prompt;
}

/// Counts every update started. While [store] is set, each update stays in
/// the store until it completes, the way the App Store sheet stays open.
class _RecordingUpdater implements StoreUpdater {
  int started = 0;
  Completer<void>? store;

  @override
  Future<void> startUpdate() async {
    started++;
    await store?.future;
  }
}

/// An [Account] answering each `getPrefs` from a queue: each call takes the
/// next answer, and the last one keeps answering every call after it.
///
/// An answer is the stored prefs, a [Completer] whose prefs are still on
/// their way, or an [Exception] to throw.
class _PrefsAccount extends Account {
  _PrefsAccount(List<Object> answers)
    : _answers = [...answers],
      super(Client());

  final List<Object> _answers;
  int reads = 0;

  @override
  Future<models.Preferences> getPrefs() async {
    reads++;
    final answer = _answers.length > 1 ? _answers.removeAt(0) : _answers.single;
    final Map<String, dynamic> data = switch (answer) {
      final Completer<Map<String, dynamic>> pending => await pending.future,
      final Map<String, dynamic> prefs => prefs,
      final Exception error => throw error,
      _ => throw ArgumentError.value(answer, 'answer'),
    };
    return models.Preferences(data: Map<String, dynamic>.from(data));
  }
}

/// A student who answered the topics prompt long ago.
const Map<String, dynamic> _answeredTopics = {
  kTopicIntentSetAtPrefKey: '2026-01-15T10:00:00.000Z',
};

/// A student who never answered it.
const Map<String, dynamic> _neverAnswered = <String, dynamic>{};

const _student = UserModel(id: 'student-a', name: 'A', email: 'a@bi.no');

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

  late _FixedPrompt notifier;
  late _RecordingUpdater updater;
  late GoRouter router;
  late GlobalKey<NavigatorState> navigatorKey;
  late WidgetRef homeRef;
  late bool homeTapped;

  // Every test in this file shares one isolate, and with it each prompt's
  // record of what it showed this session.
  setUp(() {
    resetTopicsPromptSession();
    resetUpdateRecommendedSession();
    updater = _RecordingUpdater();
    homeTapped = false;
  });

  /// The app the way `BisoApp` builds it: a router, with the required
  /// overlay in `MaterialApp.router`'s `builder`, above the Navigator.
  ///
  /// [child] is the home route; `/second` is a route to push above it.
  /// [topics] is who the topics prompt asks, by default a student who
  /// answered it long ago.
  Widget app({
    required UpdatePrompt prompt,
    required Widget child,
    NotificationService? topics,
  }) {
    notifier = _FixedPrompt(prompt);
    navigatorKey = GlobalKey<NavigatorState>();
    router = GoRouter(
      navigatorKey: navigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              homeRef = ref;
              return GestureDetector(
                onTap: () => homeTapped = true,
                child: child,
              );
            },
          ),
        ),
        GoRoute(path: '/second', builder: (_, _) => const Text('second')),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        updatePromptProvider.overrideWith(() => notifier),
        storeUpdaterProvider.overrideWithValue(updater),
        notificationServiceProvider.overrideWithValue(
          topics ??
              NotificationService.withAccount(_PrefsAccount([_answeredTopics])),
        ),
        currentUserProvider.overrideWithValue(_student),
      ],
      child: MaterialApp.router(
        theme: PremiumTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) =>
            UpdateRequiredOverlay(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  /// What `BisoApp` passes the prompts: the root Navigator's context.
  BuildContext promptContext() => navigatorKey.currentContext!;

  group('the required overlay', () {
    testWidgets('covers the app but keeps it mounted', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.required, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Time to update'), findsOneWidget);
      expect(
        find.text(
          'This version of the BISO app is no longer supported. Update to '
          'keep using the app.',
        ),
        findsOneWidget,
      );
      expect(find.text('home', skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('home'), warnIfMissed: false);
      expect(homeTapped, isFalse);
    });

    testWidgets('hides the app underneath from screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.required, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Time to update'), findsOneWidget);
      expect(find.semantics.byLabel('home'), findsNothing);
      semantics.dispose();
    });

    testWidgets('has no close control', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.required, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CloseButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets(
      'back neither dismisses it nor pops the route hidden underneath',
      (tester) async {
        await tester.pumpWidget(
          app(prompt: UpdatePrompt.required, child: const Text('home')),
        );
        await tester.pumpAndSettle();
        router.push('/second');
        await tester.pumpAndSettle();

        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue, reason: 'back is consumed, not left to exit');
        expect(find.text('Time to update'), findsOneWidget);
        expect(find.text('second', skipOffstage: false), findsOneWidget);
        expect(router.state.uri.path, '/second');
      },
    );

    testWidgets(
      'a block that arrives after launch holds back too, keeps the app '
      'underneath as it was, and back works again once it lifts',
      (tester) async {
        await tester.pumpWidget(
          app(prompt: UpdatePrompt.none, child: const Text('home')),
        );
        await tester.pumpAndSettle();
        // The router has no key to carry it over if the tree under the
        // overlay changed shape; the Navigator's GlobalKey would hide that.
        Element routerElement() => tester.element(
          find.byWidgetPredicate((widget) => widget is Router),
        );
        final routing = routerElement();
        final home = tester.element(find.text('home'));
        router.push('/second');
        await tester.pumpAndSettle();

        // A fresh answer on resume: the minimum is now above this version.
        notifier.answer(UpdatePrompt.required);
        await tester.pumpAndSettle();
        expect(find.text('Time to update'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/second');
        expect(
          routerElement(),
          same(routing),
          reason: 'the app underneath is never rebuilt from scratch',
        );
        expect(
          tester.element(find.text('home', skipOffstage: false)),
          same(home),
        );

        // A later fresh answer says this version is fine again.
        notifier.answer(UpdatePrompt.none);
        await tester.pumpAndSettle();
        expect(find.text('Time to update'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/');
        expect(routerElement(), same(routing));
        expect(tester.element(find.text('home')), same(home));
      },
    );

    testWidgets(
      'tells Android the app does not handle back while it is up, so a '
      'predictive back gesture cannot pop a route underneath, and hands '
      "back the app's own answer once it lifts",
      (tester) async {
        final frameworkHandlesBack = <bool>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
              frameworkHandlesBack.add(call.arguments as bool);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        // WidgetsApp tells the platform nothing until the app is running.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        await tester.pumpWidget(
          app(prompt: UpdatePrompt.none, child: const Text('home')),
        );
        await tester.pumpAndSettle();
        router.push('/second');
        await tester.pumpAndSettle();
        expect(frameworkHandlesBack.last, isTrue, reason: '/second can pop');

        notifier.answer(UpdatePrompt.required);
        await tester.pumpAndSettle();
        expect(frameworkHandlesBack.last, isFalse);

        // Navigation underneath carries on, but cannot claim back.
        router.push('/second');
        await tester.pumpAndSettle();
        expect(frameworkHandlesBack.last, isFalse);

        notifier.answer(UpdatePrompt.none);
        await tester.pumpAndSettle();
        expect(frameworkHandlesBack.last, isTrue);
      },
    );

    testWidgets('Update starts the store update', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.required, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      expect(updater.started, 1);
    });

    testWidgets(
      'Update is disabled while the store is open and comes back once it '
      'closes: a second tap would open the store twice',
      (tester) async {
        updater.store = Completer<void>();
        await tester.pumpWidget(
          app(prompt: UpdatePrompt.required, child: const Text('home')),
        );
        await tester.pumpAndSettle();

        FilledButton button() =>
            tester.widget<FilledButton>(find.byType(FilledButton));

        await tester.tap(find.text('Update'));
        await tester.pump();
        expect(updater.started, 1);
        expect(button().onPressed, isNull);

        await tester.tap(find.text('Update'), warnIfMissed: false);
        await tester.pump();
        expect(updater.started, 1);

        updater.store!.complete();
        await tester.pumpAndSettle();
        expect(button().onPressed, isNotNull);
        expect(find.text('Time to update'), findsOneWidget);

        await tester.tap(find.text('Update'));
        expect(updater.started, 2);
      },
    );

    testWidgets(
      'Update comes back when the app returns to the foreground, even if '
      'the store never says it is done: iOS can decline the sheet without '
      'ever answering',
      (tester) async {
        // Never completes.
        updater.store = Completer<void>();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          app(prompt: UpdatePrompt.required, child: const Text('home')),
        );
        await tester.pumpAndSettle();

        FilledButton button() =>
            tester.widget<FilledButton>(find.byType(FilledButton));

        await tester.tap(find.text('Update'));
        await tester.pump();
        expect(button().onPressed, isNull);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        expect(button().onPressed, isNotNull);

        await tester.tap(find.text('Update'));
        await tester.pump();
        expect(updater.started, 2);
        expect(button().onPressed, isNull);
      },
    );

    testWidgets('no overlay when no update is required', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.none, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Time to update'), findsNothing);
      await tester.tap(find.text('home'));
      expect(homeTapped, isTrue);
    });

    testWidgets('no overlay for a recommended update either', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.recommended, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Time to update'), findsNothing);
    });
  });

  group('the recommended popup', () {
    const title = 'A new version is available';

    testWidgets('Not now snoozes the recommendation', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.recommended, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(
        find.text('Update the BISO app to get the latest improvements.'),
        findsOneWidget,
      );
      expect(updateRecommendedShowing, isTrue);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(notifier.snoozed, isTrue);
      expect(find.text(title), findsNothing);
      expect(updateRecommendedShowing, isFalse);
      expect(updater.started, 0);
    });

    testWidgets('Update closes it and starts the store update', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.recommended, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(find.text(title), findsNothing);
      expect(updater.started, 1);
      expect(notifier.snoozed, isFalse);
    });

    testWidgets('shows at most once per session', (tester) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.recommended, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      // BisoApp asks again on every rebuild.
      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });

    testWidgets('a second call while it is up does not stack another', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(prompt: UpdatePrompt.recommended, child: const Text('home')),
      );
      await tester.pumpAndSettle();

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });

    testWidgets('shows nothing unless an update is recommended', (
      tester,
    ) async {
      for (final prompt in [UpdatePrompt.none, UpdatePrompt.required]) {
        await tester.pumpWidget(app(prompt: prompt, child: const Text('home')));
        await tester.pumpAndSettle();

        unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing, reason: '$prompt');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the recommendation stays away after the topics prompt was '
        'shown', (tester) async {
      // Not answered, so the sheet shows; its own load fails, which puts
      // "Skip for now" on screen.
      final topics = NotificationService.withAccount(
        _PrefsAccount([_neverAnswered, AppwriteException('offline')]),
      );
      await tester.pumpWidget(
        app(
          prompt: UpdatePrompt.recommended,
          child: const Text('home'),
          topics: topics,
        ),
      );
      await tester.pumpAndSettle();

      // As BisoApp does: the topics prompt first, then the popup.
      unawaited(maybeShowTopicsPrompt(promptContext(), homeRef));
      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTopicsPrompt), findsOneWidget);
      expect(find.text(title), findsNothing, reason: 'never on top of it');
      expect(topicsPromptShownThisSession, isTrue);

      await tester.tap(find.widgetWithText(TextButton, 'Skip for now'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTopicsPrompt), findsNothing);
      expect(find.text(title), findsNothing, reason: 'one prompt a session');

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });

    testWidgets(
      'a topics prompt still checking whether to show is waited for, and '
      'when it shows nothing the popup still appears: a student who '
      'answered topics long ago would otherwise never see it',
      (tester) async {
        final answered = Completer<Map<String, dynamic>>();
        await tester.pumpWidget(
          app(
            prompt: UpdatePrompt.recommended,
            child: const Text('home'),
            topics: NotificationService.withAccount(_PrefsAccount([answered])),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(maybeShowTopicsPrompt(promptContext(), homeRef));
        unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing, reason: 'topics still deciding');

        answered.complete(_answeredTopics);
        await tester.pumpAndSettle();
        expect(find.byType(NotificationTopicsPrompt), findsNothing);
        expect(topicsPromptShownThisSession, isFalse);
        expect(find.text(title), findsOneWidget);

        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the topics prompt does not open while the popup is up', (
      tester,
    ) async {
      final account = _PrefsAccount([
        _neverAnswered,
        AppwriteException('offline'),
      ]);
      await tester.pumpWidget(
        app(
          prompt: UpdatePrompt.recommended,
          child: const Text('home'),
          topics: NotificationService.withAccount(account),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(maybeShowUpdateRecommended(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);

      unawaited(maybeShowTopicsPrompt(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTopicsPrompt), findsNothing);
      expect(account.reads, 0, reason: 'it did not even check');

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      // Once the popup has gone, BisoApp's next build asks again.
      unawaited(maybeShowTopicsPrompt(promptContext(), homeRef));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTopicsPrompt), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Skip for now'));
      await tester.pumpAndSettle();
    });
  });

  test('the update copy exists in English and Norwegian', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final no = lookupAppLocalizations(const Locale('no'));

    expect(en.updateRequiredTitle, 'Time to update');
    expect(
      en.updateRequiredBody,
      'This version of the BISO app is no longer supported. Update to keep '
      'using the app.',
    );
    expect(en.updateRecommendedTitle, 'A new version is available');
    expect(
      en.updateRecommendedBody,
      'Update the BISO app to get the latest improvements.',
    );
    expect(en.updateButton, 'Update');
    expect(en.updateNotNow, 'Not now');

    expect(no.updateRequiredTitle, 'På tide å oppdatere');
    expect(
      no.updateRequiredBody,
      'Denne versjonen av BISO-appen støttes ikke lenger. Oppdater for å '
      'fortsette å bruke appen.',
    );
    expect(no.updateRecommendedTitle, 'En ny versjon er tilgjengelig');
    expect(
      no.updateRecommendedBody,
      'Oppdater BISO-appen for å få de siste forbedringene.',
    );
    expect(no.updateButton, 'Oppdater');
    expect(no.updateNotNow, 'Ikke nå');
  });
}
