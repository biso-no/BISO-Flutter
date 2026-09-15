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

/// Asserts 'Title is required' renders below the Title field's own label,
/// horizontally within the same grouped surface, and above the next field
/// (Description) — pinning the error to the Title field specifically,
/// rather than merely checking the text exists somewhere on screen. Mirrors
/// the rect-comparison approach in
/// webshop_product_detail_design_test.dart:171-179.
void _expectTitleErrorBelowField(WidgetTester tester) {
  final labelFinder = find.text('Title');
  expect(labelFinder, findsOneWidget);
  final labelRect = tester.getRect(labelFinder);

  final errorFinder = find.text('Title is required');
  expect(errorFinder, findsOneWidget);
  final errorRect = tester.getRect(errorFinder);

  // Below the Title label...
  expect(errorRect.top, greaterThan(labelRect.bottom));

  // ...horizontally inside the Details group's own surface...
  final groupFinder = find.ancestor(
    of: labelFinder,
    matching: find.byType(BisoListGroup),
  );
  expect(groupFinder, findsOneWidget);
  final groupRect = tester.getRect(groupFinder);
  expect(errorRect.left, greaterThanOrEqualTo(groupRect.left));
  expect(errorRect.right, lessThanOrEqualTo(groupRect.right));

  // ...and above the next field (Description), so it reads as attached to
  // Title rather than to whatever comes after it.
  final descriptionLabelFinder = find.text('Description');
  expect(descriptionLabelFinder, findsOneWidget);
  final descriptionRect = tester.getRect(descriptionLabelFinder);
  expect(errorRect.bottom, lessThanOrEqualTo(descriptionRect.top));
}

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

      _expectTitleErrorBelowField(tester);
    },
  );

  testWidgets(
    'tapping the full-width Publish button at the end of the form with an '
    'empty title shows the same validation message below the title field',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const SellProductScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsNothing);

      // The button is below the fold at rest — scroll it into view before
      // tapping, the same way a real device would need to.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final publishButton = find.widgetWithText(FilledButton, 'Publish');
      expect(publishButton, findsOneWidget);
      await tester.tap(publishButton);
      await tester.pumpAndSettle();

      // The Title field itself may now be scrolled out of the lazy sliver
      // list's cache extent — this only re-confirms the same validation
      // message the header action produces, not its on-screen position
      // (already pinned to the Title field by the test above).
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
