import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/explore/sell_product_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

const _user = UserModel(id: 'seller-1', name: 'Kari Nordmann', email: 'kari@bi.no');

class _SignedIn extends StateNotifier<AuthState> implements AuthNotifier {
  _SignedIn() : super(const AuthState(isAuthenticated: true, user: _user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOut extends StateNotifier<AuthState> implements AuthNotifier {
  _SignedOut() : super(const AuthState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides({bool signedIn = true}) => [
  authStateProvider.overrideWith((_) => signedIn ? _SignedIn() : _SignedOut()),
  filterCampusProvider.overrideWithValue(_campus),
];

void main() {
  testWidgets('Sell product builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const SellProductScreen(),
      overrides: _overrides(),
    );
  });

  testWidgets('signed out shows a sign-in prompt instead of the form', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const SellProductScreen(),
      overrides: _overrides(signedIn: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Please sign in to sell items'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'submitting with an empty title shows the existing validation message '
    'below the title field',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const SellProductScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsNothing);

      await tester.tap(find.byTooltip('Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsOneWidget);
    },
  );

  testWidgets(
    'category and condition rows open a picker sheet that updates the '
    'row value on selection',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const SellProductScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(BisoListRow, 'Category'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(BisoListRow, 'Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(BisoListRow, 'Category'));
      await tester.pumpAndSettle();

      expect(find.text('Electronics'), findsWidgets);
      await tester.tap(find.text('Electronics').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(BisoListRow, 'Category'), findsOneWidget);
      final row = tester.widget<BisoListRow>(
        find.widgetWithText(BisoListRow, 'Category'),
      );
      expect(row.value, 'Electronics');
    },
  );

  testWidgets('tapping Cancel with no changes navigates away without a dialog', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const SellProductScreen(),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets(
    'tapping Cancel after typing shows the discard-changes dialog',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const SellProductScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'A title');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
    },
  );
}
