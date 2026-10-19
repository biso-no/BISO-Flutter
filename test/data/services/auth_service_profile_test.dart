import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/profile_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account extends Fake implements Account {
  @override
  Future<models.User> get() async => models.User.fromMap({
    r'$id': 'user-1',
    'name': 'Kari Nordmann',
    'email': 'kari@example.com',
    'status': true,
    'emailVerification': true,
    'phoneVerification': false,
    'mfa': false,
    'prefs': <String, dynamic>{},
    'targets': <dynamic>[],
  });
}

/// The row [getCurrentUser] reads: no bank_account, no departments.
class _Tables extends Fake implements TablesDB {
  /// The queries of every row read, in order.
  final List<List<String>> reads = [];

  @override
  Future<models.Row> getRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    List<String>? queries,
    String? transactionId,
  }) async {
    reads.add(queries ?? const []);
    return models.Row.fromMap({
      r'$id': rowId,
      'data': {
        r'$id': rowId,
        'name': 'Kari Nordmann',
        'email': 'k@example.com',
      },
    });
  }
}

void main() {
  late Map<String, dynamic> sent;
  late _Tables tables;

  AuthService service() => AuthService(
    account: _Account(),
    databases: tables = _Tables(),
    profileApi: ProfileApiClient(
      httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'profile': {r'$id': 'user-1', ...sent},
          }),
          200,
        );
      }),
      jwtProvider: () async => 'jwt',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a name edit sends neither bank_account nor departments', () async {
    await service().updateUserProfile(name: 'Kari N.');

    expect(sent, {'name': 'Kari N.'});
    expect(sent.containsKey('bank_account'), isFalse);
    expect(sent.containsKey('departments'), isFalse);
  });

  test('a departments edit sends departments', () async {
    await service().updateUserProfile(departments: ['dept-1', 'dept-2']);

    expect(sent, {
      'departments': ['dept-1', 'dept-2'],
    });
  });

  test('getCurrentUser selects plain columns only, not the departments '
      'relationship', () async {
    final user = await service().getCurrentUser();

    expect(user?.name, 'Kari Nordmann');
    final selected = [
      for (final query in tables.reads.single)
        ...(jsonDecode(query)['values'] as List).cast<String>(),
    ];
    expect(selected, isNot(contains('departments')));
    expect(selected, containsAll(['department_ids', 'bank_account', 'swift']));
  });

  test("avatar file ids fit Appwrite's 36-character limit", () {
    final names = AuthService.avatarUploadNames('a' * 20);

    expect(names.fileId.length, lessThanOrEqualTo(36));
    expect(names.fileId, matches(RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$')));
    expect(names.fileName, startsWith('avatar_${'a' * 20}_'));
    expect(names.fileName, endsWith('.jpg'));
  });
}
