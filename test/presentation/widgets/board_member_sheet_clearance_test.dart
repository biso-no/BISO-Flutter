import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/data/models/board_member_model.dart';
import 'package:biso/presentation/widgets/campus/campus_leadership_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const tabs = [
  BisoNavDestination(icon: Icons.home, label: 'Home'),
  BisoNavDestination(icon: Icons.explore, label: 'Explore'),
  BisoNavDestination(icon: Icons.person, label: 'Profile'),
];

void main() {
  testWidgets('member sheet contact rows clear the floating tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
            ),
            child: BisoNavigationScaffold(
              currentIndex: 1,
              routeKey: 'test',
              destinations: tabs,
              onSelected: (_) {},
              // Mirrors the app's ShellRoute: pages, and the sheets they
              // open, live in a navigator beneath the floating tab bar.
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const Material(
                    child: Center(
                      child: BoardMemberCard(
                        member: BoardMemberModel(
                          name: 'Adrian Aas Kleppe',
                          email: 'adrian@biso.no',
                          phone: '12345678',
                          role: 'Manager Cards',
                          officeLocation: 'Bergen',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Adrian Aas Kleppe'));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(BisoNavigationBar)).dy;
    expect(
      tester.getBottomLeft(find.text('adrian@biso.no')).dy,
      lessThan(barTop),
    );
    expect(tester.getBottomLeft(find.text('12345678')).dy, lessThan(barTop));
  });

  testWidgets('tapping the email row copies it when no mail app opens', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BoardMemberCard(
              member: BoardMemberModel(
                name: 'Mikkel Furseth',
                email: 'manager.aksje.bergen@biso.no',
                phone: '',
                role: 'Manager Aksjeklubben',
                officeLocation: 'Bergen',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mikkel Furseth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('manager.aksje.bergen@biso.no'));
    // The launcher's platform channel replies on the real event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(copied, 'manager.aksje.bergen@biso.no');
    expect(find.text('Email copied'), findsOneWidget);
  });
}
