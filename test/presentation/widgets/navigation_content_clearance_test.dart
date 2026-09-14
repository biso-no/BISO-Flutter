import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/data/models/chat_model.dart';
import 'package:biso/data/models/shop_order.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_conversation_screen.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/presentation/screens/shop/orders_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const tabs = [
  BisoNavDestination(icon: Icons.home, label: 'Home'),
  BisoNavDestination(icon: Icons.explore, label: 'Explore'),
  BisoNavDestination(icon: Icons.person, label: 'Profile'),
];

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true,
    user: UserModel(id: 'test', name: 'Student', email: 'student@bi.no')));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChatService implements ChatService {
  @override
  Future<void> markChatAsRead(String chatId, String userId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget page, {bool shell = true, ValueChanged<int>? onSelected}) =>
  ProviderScope(overrides: [
    authStateProvider.overrideWith((_) => _Auth()),
    myOrdersProvider.overrideWith((_) async => List.generate(20, (i) => ShopOrder.fromJson({
      'id': '$i', 'status': 'paid', 'total': 100,
    }))),
    chatMessagesProvider('chat').overrideWith((_) => Stream.value([])),
    chatServiceProvider.overrideWithValue(_ChatService()),
  ], child: MaterialApp(home: MediaQuery(
    data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34), viewPadding: EdgeInsets.only(bottom: 34)),
    child: shell ? BisoNavigationScaffold(
      currentIndex: 1, routeKey: 'test', destinations: tabs,
      onSelected: onSelected ?? (_) {}, child: page,
    ) : page,
  )));

void main() {
  testWidgets('order cards retain their height and the last order clears glass', (tester) async {
    await tester.pumpWidget(app(const OrdersScreen(), shell: false));
    await tester.pumpAndSettle();
    final card = find.ancestor(of: find.text('Order 0'), matching: find.byType(BisoListRow)).first;
    final normalHeight = tester.getSize(card).height;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(const OrdersScreen()));
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, normalHeight);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    // Lazy slivers refine their extent when the final cards are first built.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.extentAfter, 0);
    final last = find.ancestor(of: find.text('Order 19'), matching: find.byType(BisoListRow)).first;
    expect(tester.getRect(last).bottom, lessThan(tester.getRect(find.byKey(const ValueKey('biso-nav-expanded'))).top));
  });

  testWidgets('marketplace chat composer stays above navigation and accepts focus', (tester) async {
    final selections = <int>[];
    await tester.pumpWidget(app(const ChatConversationScreen(
      chat: ChatModel(id: 'chat', name: 'Marketplace conversation'),
    ), onSelected: selections.add));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    final nav = find.byKey(const ValueKey('biso-nav-expanded'));
    expect(tester.getRect(field).bottom, lessThan(tester.getRect(nav).top));
    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(selections, isEmpty);
  });
}
