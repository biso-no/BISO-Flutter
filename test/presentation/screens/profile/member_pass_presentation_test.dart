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

  Future<void> openPresentation(WidgetTester tester) async {
    screen = FakeScreenPresentation();
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
    expect(screen.exits, 1);

    lifecycle(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(screen.enters, 2);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsNothing);
    expect(screen.exits, 2);
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
