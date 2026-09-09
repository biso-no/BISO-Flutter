import 'package:appwrite/models.dart';
import 'package:biso/core/utils/appwrite_row.dart';
import 'package:flutter_test/flutter_test.dart';

Row _buildRow({required String id, required Map<String, dynamic> data}) {
  return Row(
    $id: id,
    $sequence: '1',
    $tableId: 'events',
    $databaseId: 'app',
    $createdAt: '2026-01-01T00:00:00.000+00:00',
    $updatedAt: '2026-01-02T00:00:00.000+00:00',
    $permissions: const [],
    data: data,
  );
}

void main() {
  group('rowData', () {
    test('merges row.data with the row\'s own \$id/\$createdAt/\$updatedAt', () {
      final row = _buildRow(id: 'row-1', data: {'title': 'Test event'});

      final result = rowData(row);

      expect(result['title'], 'Test event');
      expect(result[r'$id'], 'row-1');
      expect(result[r'$createdAt'], '2026-01-01T00:00:00.000+00:00');
      expect(result[r'$updatedAt'], '2026-01-02T00:00:00.000+00:00');
    });

    test('system fields win over conflicting keys already in row.data', () {
      final row = _buildRow(
        id: 'row-2',
        data: {
          r'$id': 'stale-id',
          r'$createdAt': 'stale-created',
          r'$updatedAt': 'stale-updated',
          'title': 'Another event',
        },
      );

      final result = rowData(row);

      expect(result[r'$id'], 'row-2');
      expect(result[r'$createdAt'], '2026-01-01T00:00:00.000+00:00');
      expect(result[r'$updatedAt'], '2026-01-02T00:00:00.000+00:00');
      expect(result['title'], 'Another event');
    });
  });
}
