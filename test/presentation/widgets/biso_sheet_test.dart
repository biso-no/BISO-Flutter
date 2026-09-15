import 'dart:io';

import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tabs = [
  BisoNavDestination(icon: Icons.home, label: 'Home'),
  BisoNavDestination(icon: Icons.explore, label: 'Explore'),
  BisoNavDestination(icon: Icons.person, label: 'Profile'),
];

/// Pumps a page inside the tab bar the way the app's ShellRoute nests it: in
/// a navigator beneath the floating bar, so sheets it opens land there too.
Future<void> pumpInShell(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  bool shell = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          final page = Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (context) => Material(
                child: Center(
                  child: TextButton(
                    onPressed: () => open(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
            ),
            child: shell
                ? BisoNavigationScaffold(
                    currentIndex: 1,
                    routeKey: 'test',
                    destinations: tabs,
                    onSelected: (_) {},
                    child: page,
                  )
                : page,
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a SafeArea sheet clears the floating tab bar', (tester) async {
    await pumpInShell(
      tester,
      (context) => showBisoSheet<void>(
        context: context,
        builder: (_) => const SafeArea(
          top: false,
          child: SizedBox(height: 100, child: Text('last row')),
        ),
      ),
    );

    final barTop = tester.getTopLeft(find.byType(BisoNavigationBar)).dy;
    expect(
      tester.getBottomLeft(find.text('last row')).dy,
      lessThanOrEqualTo(barTop),
    );
  });

  testWidgets('outside the tab bar a sheet keeps the device safe area', (
    tester,
  ) async {
    late double bottomPadding;
    await pumpInShell(
      tester,
      shell: false,
      (context) => showBisoSheet<void>(
        context: context,
        builder: (context) {
          bottomPadding = MediaQuery.paddingOf(context).bottom;
          return const SizedBox(height: 100);
        },
      ),
    );

    expect(bottomPadding, 34);
  });

  test('sheets are opened through showBisoSheet', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('core/theme/biso_sheet.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (line.contains('showModalBottomSheet')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    // A raw sheet opened under the floating tab bar loses its bottom safe
    // area, so its last rows hide behind the bar.
    expect(offenders, isEmpty);
  });
}
