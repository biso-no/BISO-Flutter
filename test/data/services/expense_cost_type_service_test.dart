import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/expense_cost_type_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTablesDB extends Fake implements TablesDB {
  String? databaseId;
  String? tableId;
  List<String>? queries;
  final List<Map<String, dynamic>> extraRows;

  _FakeTablesDB({this.extraRows = const []});

  Map<String, dynamic> _row(String slug, Map<String, dynamic> extra) => {
    '\$id': slug,
    '\$sequence': 1,
    '\$tableId': tableId,
    '\$databaseId': databaseId,
    '\$createdAt': '2026-01-01T00:00:00.000+00:00',
    '\$updatedAt': '2026-01-01T00:00:00.000+00:00',
    '\$permissions': <String>[],
    'slug': slug,
    'label': slug,
    ...extra,
  };

  @override
  Future<models.RowList> listRows({
    required String databaseId,
    required String tableId,
    List<String>? queries,
    String? transactionId,
    bool? total,
    int? ttl,
  }) async {
    this.databaseId = databaseId;
    this.tableId = tableId;
    this.queries = queries;
    return models.RowList.fromMap({
      'total': 1 + extraRows.length,
      'rows': [
        for (final extra in extraRows) _row(extra['slug'] as String, extra),
        {
          '\$id': 'r1',
          '\$sequence': 1,
          '\$tableId': tableId,
          '\$databaseId': databaseId,
          '\$createdAt': '2026-01-01T00:00:00.000+00:00',
          '\$updatedAt': '2026-01-01T00:00:00.000+00:00',
          '\$permissions': <String>[],
          'slug': 'food',
          'label': 'Food',
          'label_no': 'Mat',
          'ask_occasion': true,
          'sort_order': 1,
        },
      ],
    });
  }
}

void main() {
  test('listActive reads the types in sort order', () async {
    final fake = _FakeTablesDB();
    final options = await ExpenseCostTypeService(tablesDb: fake).listActive();

    expect(fake.databaseId, 'app');
    expect(fake.tableId, 'expense_cost_types');
    expect(fake.queries, [Query.orderAsc('sort_order'), Query.limit(100)]);
    expect(options.single.slug, 'food');
    expect(options.single.askOccasion, isTrue);
  });

  test('listActive drops only types that are explicitly inactive', () async {
    final fake = _FakeTablesDB(
      extraRows: [
        {'slug': 'off', 'active': false},
        {'slug': 'unset'},
        {'slug': 'on', 'active': true},
      ],
    );
    final options = await ExpenseCostTypeService(tablesDb: fake).listActive();

    expect(options.map((o) => o.slug), ['unset', 'on', 'food']);
  });
}
