import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/shop_order.dart';
import 'appwrite_service.dart';

/// Reads the buyer's own orders straight from Appwrite.
///
/// Order rows carry a per-buyer read grant (`Permission.read(Role.user(id))`,
/// written when the order is created), so the signed-in user's client sees
/// exactly their own orders and nothing else — no server round-trip needed for
/// the history list. Anything that has to *change* an order, or verify it with
/// the payment provider, goes through `ShopApiClient` instead: order rows are
/// only writable by the Operations Unit.
class OrderService {
  static const String collectionId = AppConstants.ordersCollectionId;

  /// Line items and the nested detail the receipt renders. Relations are only
  /// returned when explicitly selected.
  static const List<String> _orderSelect = [
    '*',
    'order_items.*',
    'order_items.variation.*',
    'order_items.field_answers.*',
  ];

  /// Builds the query list for the buyer's order history.
  ///
  /// No `userId` filter: row-level security already scopes the read to the
  /// caller's own rows, and adding one would silently hide orders placed
  /// before the buyer's account was linked.
  static List<String> buildHistoryQueries({int limit = 25, int offset = 0}) {
    return [
      Query.select(_orderSelect),
      Query.orderDesc(r'$createdAt'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  Future<List<ShopOrder>> listMyOrders({int limit = 25, int offset = 0}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildHistoryQueries(limit: limit, offset: offset),
    );
    return response.rows
        .map((row) => ShopOrder.fromAppwriteRow(rowData(row)))
        .toList(growable: false);
  }

  /// Reads one order without asking the provider to re-check it.
  ///
  /// Useful for rendering immediately while a verification call is in flight.
  /// Returns `null` when the order is not the caller's, since row security
  /// makes "not mine" and "not found" the same answer.
  Future<ShopOrder?> getOrder(String orderId) async {
    try {
      final row = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: orderId,
        queries: [Query.select(_orderSelect)],
      );
      return ShopOrder.fromAppwriteRow(rowData(row));
    } catch (_) {
      return null;
    }
  }
}
