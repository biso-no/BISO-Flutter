import 'package:biso/core/utils/currency.dart';
import 'package:biso/data/models/shop_order.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/shop/order_screen.dart';
import 'package:biso/presentation/screens/shop/orders_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _buyerId = 'buyer-1';
const _user = UserModel(id: _buyerId, name: 'Test Buyer', email: 'buyer@bi.no');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(bool isAuthenticated)
    : super(
        AuthState(
          isAuthenticated: isAuthenticated,
          user: isAuthenticated ? _user : null,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never touches the network: `OrderScreen.verifyOrder` reads
/// `shopApiClientProvider` directly, so a real `ShopApiClient` would try an
/// HTTP call and hang the test.
class _FakeShopApiClient extends ShopApiClient {
  _FakeShopApiClient(this.order);

  final ShopOrder order;

  @override
  Future<ShopOrder> fetchOrder(String orderId) async => order;
}

ShopOrder _order({
  required String id,
  required ShopOrderStatus status,
  double total = 249,
  double discountTotal = 0,
  DateTime? createdAt,
  List<ShopOrderItem> items = const [],
  String? paymentLink,
  String? receiptUrl,
}) => ShopOrder(
  id: id,
  status: status,
  currency: 'NOK',
  subtotal: total + discountTotal,
  discountTotal: discountTotal,
  total: total,
  membershipApplied: discountTotal > 0,
  memberDiscountPercent: discountTotal > 0 ? 10 : 0,
  createdAt: createdAt ?? DateTime(2026, 1, 15),
  items: items,
  paymentLink: paymentLink,
  receiptUrl: receiptUrl,
);

/// The token every [ShopOrderStatus] maps to (fix round 1, ruling B), shared
/// by the orders list pill and the order detail header icon — see
/// `_statusPresentation` in `orders_screen.dart` and `_StatusHeader._presentation`
/// in `order_screen.dart`.
Color Function(BisoPalette) _expectedToken(ShopOrderStatus status) {
  switch (status) {
    case ShopOrderStatus.paid:
    case ShopOrderStatus.authorized:
      return (palette) => palette.success;
    case ShopOrderStatus.pending:
      return (palette) => palette.warning;
    case ShopOrderStatus.cancelled:
    case ShopOrderStatus.failed:
      return (palette) => palette.error;
    case ShopOrderStatus.refunded:
      return (palette) => palette.muted;
  }
}

/// Asserts [text] renders as a single, complete, full-size line — R11:
/// amounts never truncate, wrap, or scale down. Mirrors the check in
/// `cart_checkout_design_test.dart`.
void _expectFullSizeAmount(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsAtLeastNWidgets(1), reason: '"$text" should render in full');
  for (final element in finder.evaluate()) {
    final widgetFinder = find.byWidget(element.widget);
    expect(
      find.ancestor(of: widgetFinder, matching: find.byType(FittedBox)),
      findsNothing,
      reason: '"$text" is inside a FittedBox and so may be scaled down',
    );
    final paragraph = tester.renderObject<RenderParagraph>(widgetFinder);
    expect(paragraph.maxLines, 1, reason: '"$text" should be one line');
    expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" was ellipsized');
    final maxIntrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(maxIntrinsicWidth - 0.5),
      reason: '"$text" was laid out narrower than its natural width',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Orders', () {
    testWidgets(
      'builds on BisoPage in every appearance: signed out, empty, and with orders',
      (tester) async {
        await expectBuildsCleanly(
          tester,
          () => const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(false)),
            myOrdersProvider.overrideWith((_) async => const []),
          ],
        );

        await expectBuildsCleanly(
          tester,
          () => const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(true)),
            myOrdersProvider.overrideWith((_) async => const []),
          ],
        );

        await expectBuildsCleanly(
          tester,
          () => const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(true)),
            myOrdersProvider.overrideWith(
              (_) async => [
                _order(id: '1', status: ShopOrderStatus.paid),
                _order(id: '2', status: ShopOrderStatus.pending),
                _order(id: '3', status: ShopOrderStatus.failed),
              ],
            ),
          ],
        );
      },
    );

    testWidgets(
      'each row shows the order id, date, item names and total, and a paid '
      "order's status pill text color equals palette.success",
      (tester) async {
        final order = _order(
          id: 'abc123',
          status: ShopOrderStatus.paid,
          total: 349,
          createdAt: DateTime(2026, 3, 4),
          items: const [
            ShopOrderItem(
              name: 'Hoodie',
              quantity: 2,
              unitPrice: 174.5,
              lineTotal: 349,
            ),
          ],
        );

        for (final brightness in Brightness.values) {
          await pumpBisoScreen(
            tester,
            const OrdersScreen(),
            overrides: [
              authStateProvider.overrideWith((_) => _Auth(true)),
              myOrdersProvider.overrideWith((_) async => [order]),
            ],
            brightness: brightness,
          );
          await tester.pumpAndSettle();

          expect(find.text('Order abc123'), findsOneWidget);
          // Item names (fix round 1, ruling A), not the item count — the
          // count is only a fallback for an order with no item names.
          expect(find.textContaining('Hoodie'), findsOneWidget);
          expect(find.text(formatNok(349)), findsOneWidget);
          expect(find.text('Paid'), findsOneWidget);

          final palette = brightness == Brightness.dark
              ? BisoPalette.dark
              : BisoPalette.light;
          final pillText = tester.widget<Text>(find.text('Paid'));
          expect(pillText.style?.color, palette.success);

          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      'a large total renders in full, not ellipsized or scaled, at 1.6x '
      'text, and an order with no item names falls back to the item count '
      '(R11 / ruling A)',
      (tester) async {
        final order = _order(id: 'big', status: ShopOrderStatus.paid, total: 1234.50);
        await pumpBisoScreen(
          tester,
          const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(true)),
            myOrdersProvider.overrideWith((_) async => [order]),
          ],
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // No items on this order, so the subtitle falls back to the count.
        expect(find.textContaining('0 items'), findsOneWidget);

        expect(formatNok(1234.50), 'NOK 1234.50');
        // The row's content-sized trailing block (see _OrderAmountAndStatus)
        // renders the total on one line if it fits, or — the same last
        // resort R11 allows — splits only between the currency code and the
        // number. Either way, every visible piece must be shown in full.
        if (find.text('NOK 1234.50').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 1234.50');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '1234.50');
        }
      },
    );

    // A 20-character id (real order ids run about this long), two item
    // names, and a 4-digit-plus-decimals total — the combination fix round
    // 1 flagged: a fixed trailing width left as little as 34pt for this
    // title+subtitle on a 320pt phone. `paid` (a short pill, "Paid") is
    // deliberately chosen over a longer label: at 390pt/1.0x it keeps the
    // amount+pill block under ~40% of the row, which is what makes the
    // side-by-side layout the one this data actually gets there.
    final wideRowOrder = _order(
      id: 'ORD1234567890ABCDEFG',
      status: ShopOrderStatus.paid,
      total: 1234.50,
      createdAt: DateTime(2026, 1, 15),
      items: const [
        ShopOrderItem(name: 'Bag', quantity: 1, unitPrice: 617.25, lineTotal: 617.25),
        ShopOrderItem(name: 'Hat', quantity: 1, unitPrice: 617.25, lineTotal: 617.25),
      ],
    );
    final wideRowTitle = 'Order ${wideRowOrder.id}';
    const wideRowSubtitle = 'Jan 15, 2026 • Bag, Hat';

    testWidgets(
      'a 20-character id with item names and a large total shows the title, '
      'subtitle, amount and pill in full at 320pt/1.6x, with no overflow '
      '(fix round 1)',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(true)),
            myOrdersProvider.overrideWith((_) async => [wideRowOrder]),
          ],
          size: const Size(320, 844),
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text(wideRowTitle), findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(find.text(wideRowTitle)).didExceedMaxLines,
          isFalse,
          reason: 'the id should wrap within its cap, not ellipsize',
        );
        expect(find.text(wideRowSubtitle), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(wideRowSubtitle))
              .didExceedMaxLines,
          isFalse,
          reason: 'the date and item names should wrap within their cap, not ellipsize',
        );

        expect(formatNok(1234.50), 'NOK 1234.50');
        if (find.text('NOK 1234.50').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 1234.50');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '1234.50');
        }
        expect(find.text('Paid'), findsOneWidget);
      },
    );

    testWidgets(
      'the same order uses the side-by-side layout at 390pt/1.0x — the '
      'amount sits on the title row (fix round 1)',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const OrdersScreen(),
          overrides: [
            authStateProvider.overrideWith((_) => _Auth(true)),
            myOrdersProvider.overrideWith((_) async => [wideRowOrder]),
          ],
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final rowFinder = find.ancestor(
          of: find.text(wideRowTitle),
          matching: find.byType(BisoListRow),
        );
        expect(rowFinder, findsOneWidget);

        final amountWhole = find.descendant(
          of: rowFinder,
          matching: find.text('NOK 1234.50'),
        );
        final amountSplit =
            find.descendant(of: rowFinder, matching: find.text('NOK')).evaluate().isNotEmpty &&
            find
                .descendant(of: rowFinder, matching: find.text('1234.50'))
                .evaluate()
                .isNotEmpty;
        expect(
          amountWhole.evaluate().isNotEmpty || amountSplit,
          isTrue,
          reason: 'the amount should be inside the same BisoListRow as the '
              'title (side-by-side), not on a separate stacked line',
        );
      },
    );

    testWidgets(
      'the pill token matches every ShopOrderStatus value, in light and dark '
      '(fix round 1, ruling B)',
      (tester) async {
        const expected = {
          ShopOrderStatus.paid: 'Paid',
          ShopOrderStatus.authorized: 'Paid',
          ShopOrderStatus.pending: 'Awaiting payment',
          ShopOrderStatus.cancelled: 'Cancelled',
          ShopOrderStatus.failed: 'Failed',
          ShopOrderStatus.refunded: 'Refunded',
        };

        for (final status in ShopOrderStatus.values) {
          for (final brightness in Brightness.values) {
            final order = _order(id: 'status-$status', status: status);
            await pumpBisoScreen(
              tester,
              const OrdersScreen(),
              overrides: [
                authStateProvider.overrideWith((_) => _Auth(true)),
                myOrdersProvider.overrideWith((_) async => [order]),
              ],
              brightness: brightness,
            );
            await tester.pumpAndSettle();

            final label = expected[status]!;
            final pillFinder = find.text(label);
            expect(pillFinder, findsOneWidget, reason: '$status ($brightness)');
            final palette = brightness == Brightness.dark
                ? BisoPalette.dark
                : BisoPalette.light;
            final expectedColor = _expectedToken(status)(palette);
            expect(
              tester.widget<Text>(pillFinder).style?.color,
              expectedColor,
              reason: '$status ($brightness)',
            );

            await tester.pumpWidget(const SizedBox());
          }
        }
      },
    );
  });

  group('Order', () {
    List<Override> overridesFor(ShopOrder order) => [
      shopApiClientProvider.overrideWithValue(_FakeShopApiClient(order)),
    ];

    testWidgets('builds on BisoPage in every appearance: paid and failed', (
      tester,
    ) async {
      await expectBuildsCleanly(
        tester,
        () => const OrderScreen(orderId: 'order-1'),
        overrides: overridesFor(
          _order(id: 'order-1', status: ShopOrderStatus.paid),
        ),
      );

      await expectBuildsCleanly(
        tester,
        () => const OrderScreen(orderId: 'order-2'),
        overrides: overridesFor(
          _order(id: 'order-2', status: ShopOrderStatus.failed),
        ),
      );
    });

    testWidgets(
      'shows the checkmark title for a paid order, the clock title for a '
      'pending order, and the xmark title for a failed order',
      (tester) async {
        Future<void> expectStatus(ShopOrderStatus status, String title) async {
          await pumpBisoScreen(
            tester,
            OrderScreen(orderId: 'order-$status'),
            overrides: overridesFor(
              _order(id: 'order-$status', status: status),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
          // Disposes the screen so a pending order's poll timer (scheduled
          // only while the order stays pending) is cancelled before the next
          // pump, rather than left running past the end of the test.
          await tester.pumpWidget(const SizedBox());
        }

        await expectStatus(ShopOrderStatus.paid, 'Payment complete');
        await expectStatus(ShopOrderStatus.pending, 'Waiting for your payment');
        await expectStatus(ShopOrderStatus.failed, 'Payment failed');
      },
    );

    testWidgets(
      'a large total and a member discount render in full at 1.6x text (R11)',
      (tester) async {
        final order = _order(
          id: 'big-order',
          status: ShopOrderStatus.paid,
          total: 1234.50,
          discountTotal: 45.75,
          items: const [
            ShopOrderItem(
              name: 'Conference Ticket',
              quantity: 1,
              unitPrice: 1280.25,
              lineTotal: 1280.25,
            ),
          ],
        );
        await pumpBisoScreen(
          tester,
          const OrderScreen(orderId: 'big-order'),
          overrides: overridesFor(order),
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(formatNok(1280.25), 'NOK 1280.25');
        _expectFullSizeAmount(tester, 'NOK 1280.25');
        expect(formatNok(45.75), 'NOK 45.75');
        _expectFullSizeAmount(tester, '-NOK 45.75');

        // The total ("NOK 1234.50") renders at headlineMedium, the largest
        // style on the page — the amount most likely to need the tier-3
        // currency/number split (see _AmountRow's doc comment). Whichever
        // form it takes, every visible piece must still be full-size.
        expect(formatNok(1234.50), 'NOK 1234.50');
        if (find.text('NOK 1234.50').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 1234.50');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '1234.50');
        }
      },
    );

    testWidgets(
      'the status header icon and token match every ShopOrderStatus value, '
      'in light and dark, with cancelled and failed showing distinct icons '
      '(fix round 1, ruling B)',
      (tester) async {
        const expectedIcons = {
          ShopOrderStatus.paid: CupertinoIcons.checkmark_circle_fill,
          ShopOrderStatus.authorized: CupertinoIcons.checkmark_circle_fill,
          ShopOrderStatus.pending: CupertinoIcons.clock,
          ShopOrderStatus.cancelled: CupertinoIcons.xmark_circle,
          ShopOrderStatus.failed: CupertinoIcons.exclamationmark_circle,
          ShopOrderStatus.refunded: CupertinoIcons.arrow_counterclockwise,
        };
        expect(
          expectedIcons[ShopOrderStatus.cancelled],
          isNot(expectedIcons[ShopOrderStatus.failed]),
          reason: 'cancelled and failed must use distinct icons',
        );

        for (final status in ShopOrderStatus.values) {
          for (final brightness in Brightness.values) {
            final order = _order(id: 'hdr-$status', status: status);
            await pumpBisoScreen(
              tester,
              OrderScreen(orderId: order.id),
              overrides: overridesFor(order),
              brightness: brightness,
            );
            await tester.pumpAndSettle();

            final icon = expectedIcons[status]!;
            final iconFinder = find.byIcon(icon);
            expect(iconFinder, findsOneWidget, reason: '$status ($brightness)');
            final palette = brightness == Brightness.dark
                ? BisoPalette.dark
                : BisoPalette.light;
            final expectedColor = _expectedToken(status)(palette);
            expect(
              tester.widget<Icon>(iconFinder).color,
              expectedColor,
              reason: '$status ($brightness)',
            );

            await tester.pumpWidget(const SizedBox());
          }
        }
      },
    );
  });
}
