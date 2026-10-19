import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The account a BI sign-in left behind.
class _Account extends Fake implements Account {
  @override
  Future<models.User> get() async => models.User.fromMap({
    r'$id': 'bi-user',
    'name': 'Kari Nordmann',
    'email': 's1234567@bi.no',
    'status': true,
    'emailVerification': true,
    'phoneVerification': false,
    'mfa': false,
    'prefs': <String, dynamic>{},
    'targets': <dynamic>[],
  });
}

/// Holds [profile] as the account's `user` row, or no row at all.
class _Tables extends Fake implements TablesDB {
  _Tables([this.profile]);

  final Map<String, dynamic>? profile;

  @override
  Future<models.Row> getRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    List<String>? queries,
    String? transactionId,
  }) async {
    final row = profile;
    if (row == null) throw AppwriteException('Row not found', 404);
    return models.Row.fromMap({r'$id': rowId, 'data': row});
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('getCurrentUser keeps the session user for an offline launch, so a '
      'BI sign-in survives one', () async {
    final service = AuthService(account: _Account(), databases: _Tables());

    await service.getCurrentUser();

    final cached = await service.getCachedSessionUser();
    expect(cached?.id, 'bi-user');
    expect(cached?.email, 's1234567@bi.no');
    expect(cached?.name, 'Kari Nordmann');
  });

  test('getCurrentUser replaces the previous account in the cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'session_user_id': 'old-user',
      'session_user_email': 'old@example.com',
      'session_user_name': 'Old Account',
    });
    final service = AuthService(
      account: _Account(),
      databases: _Tables({
        r'$id': 'bi-user',
        'name': 'Kari N.',
        'email': 's1234567@bi.no',
      }),
    );

    await service.getCurrentUser();

    final cached = await service.getCachedSessionUser();
    expect(cached?.id, 'bi-user');
    expect(cached?.name, 'Kari N.');
  });
}
