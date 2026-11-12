import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/expense_cost_type_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTablesDB extends Fake implements TablesDB {
  String? databaseId;
  String? tableId;
  List<String>? queries;

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
      'total': 1,
      'rows': [
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
  test('listActive asks for active types in sort order', () async {
    final fake = _FakeTablesDB();
    final options = await ExpenseCostTypeService(tablesDb: fake).listActive();

    expect(fake.databaseId, 'app');
    expect(fake.tableId, 'expense_cost_types');
    expect(fake.queries, [
      Query.equal('active', true),
      Query.orderAsc('sort_order'),
      Query.limit(100),
    ]);
    expect(options.single.slug, 'food');
    expect(options.single.askOccasion, isTrue);
  });
}
