import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

void main() {
  late FakeScreenPresentation screen;
  late FixedMemberPass pass;

  Future<void> openPresentation(
    WidgetTester tester, {
    bool deferScreenCalls = false,
  }) async {
    screen = FakeScreenPresentation()..deferCalls = deferScreenCalls;
    pass = FixedMemberPass(activeView());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberPassProvider.overrideWith(() => pass),
          screenPresentationProvider.overrideWithValue(screen),
        ],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPassPresentation(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('shows the pass full screen and holds the codes', (tester) async {
    await openPresentation(tester);
    expect(find.byType(MemberPassPresentation), findsOneWidget);
    final card = tester.widget<PassCard>(find.byType(PassCard));
    expect(card.presentation, isTrue);
    expect(pass.holds, 1);
    expect(screen.enters, 1);
    expect(screen.exits, 0);
  });

  testWidgets('restores the screen in the background and on close', (
    tester,
  ) async {
    await openPresentation(tester);

    lifecycle(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await tester.pump();
    expect(screen.exits, 1);

    lifecycle(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    // Each call waits for the one before it.
    await tester.pump();
    expect(screen.enters, 2);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsNothing);
    expect(screen.exits, 2);
  });

  testWidgets('a quick flap runs enter and exit in order, one at a time', (
    tester,
  ) async {
    await openPresentation(tester, deferScreenCalls: true);
    expect(screen.calls, ['enter']);

    // inactive -> resumed -> inactive while the first enter is still running.
    lifecycle(tester, const [AppLifecycleState.inactive]);
    lifecycle(tester, const [AppLifecycleState.resumed]);
    lifecycle(tester, const [AppLifecycleState.inactive]);
    await tester.pump();
    expect(screen.calls, ['enter'], reason: 'the rest waits for the first');

    screen.pendingCalls[0].complete();
    await tester.pump();
    expect(screen.calls, ['enter', 'exit']);
    screen.pendingCalls[1].complete();
    await tester.pump();
    expect(screen.calls, ['enter', 'exit', 'enter']);
    screen.pendingCalls[2].complete();
    await tester.pump();
    // The last call leaves the screen restored, as the app is inactive.
    expect(screen.calls, ['enter', 'exit', 'enter', 'exit']);
    screen.pendingCalls[3].complete();
    await tester.pump();

    // Idle again: the next call starts at once, and closing restores.
    lifecycle(tester, const [AppLifecycleState.resumed]);
    expect(screen.calls.last, 'enter');
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(screen.calls, hasLength(5), reason: 'exit waits for enter');
    screen.pendingCalls[4].complete();
    await tester.pump();
    expect(screen.calls, ['enter', 'exit', 'enter', 'exit', 'enter', 'exit']);
    screen.pendingCalls[5].complete();
    await tester.pump();
    expect(screen.maxConcurrent, 1);
  });

  testWidgets('a tap anywhere closes it', (tester) async {
    await openPresentation(tester);
    await tester.tapAt(const Offset(20, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsNothing);
    expect(screen.exits, 1);
  });
}
