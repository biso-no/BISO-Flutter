# App Launch — Membership and Expenses in the App (BISO-Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Students can verify their BISO membership (checked against 24SevenOffice at launch and on return to the app), link their BI account through biso.no, buy a membership with the providers the admin has enabled, and submit reimbursements — with every write going through `apps/api`.

**Architecture:** Three small HTTP clients (`ProfileApiClient`, `MembershipApiClient`, extended `ExpenseApiClient`) share one JWT helper. A Riverpod `AsyncNotifier` owns the membership overview (cached per user, re-verified on resume); a `StateNotifier` controller persists and resolves an in-flight membership payment the same way the shop's `CheckoutController` does. One `BisoPage` screen renders every membership state. Legacy Appwrite-Function membership code, the unreachable Student ID screen and `flutter_appauth` are removed.

**Tech Stack:** Flutter 3.47 / Dart, flutter_riverpod 2.6, go_router, http 1.6 (`package:http/testing.dart` in tests), shared_preferences, url_launcher, Appwrite Dart SDK 26.

**Spec:** `docs/superpowers/specs/2026-09-15-app-launch-membership-expenses-design.md` (Phase 3). **Server contracts:** `docs/superpowers/plans/2026-09-15-app-launch-platform.md` (Tasks 2, 3, 4, 6, 12, 13, 14).

## Global Constraints

- Repo: BISO-Flutter worktree `/Users/markus/Documents/dev/BISO-Flutter/.claude/worktrees/problem-to-solve-3bff42`, branch `claude/biso-mobile-app-review-7080ff`. All paths below are relative to it.
- Verify with `flutter test <paths>`, `flutter analyze`, and `dart format --output=none --set-exit-if-changed <paths>`. Baseline before this plan: 721 tests passing.
- Screens follow the 2026-09 design system: import `lib/presentation/widgets/biso/biso.dart`, build on `BisoPage`, colors from `BisoPalette.of(context)` / `BisoAccent`, CupertinoIcons only, Museo (display/headline styles) weight 300 only. Every new screen file is added to `migratedFiles` in `test/presentation/design_rules_test.dart`.
- Copy style: the shop and membership flows use plain English strings in the widget code, as `lib/presentation/screens/shop/*` already does. Do not add ARB keys in this plan.
- Server contracts are fixed by the platform plan and must be parsed exactly:
  - `PUT /api/profile` → `{ success: true, profile: {…user row…} }` / `{ success: false, error }`.
  - `POST /api/expenses/attachments` (multipart `file`) → `201 { success: true, file: { fileId, name, mimeType, size, viewUrl } }` / `{ success: false, error }`.
  - `DELETE /api/expenses/draft?expenseId=…` → `{ success: true }` / `{ success: false, error }`.
  - `GET /api/config` → `features.expenses` is the live admin switch.
  - `GET /api/membership[?refresh=1]` → `{ state, studentId, isMember, memberships[], expiredMemberships[], currentExpiry, reason, checkedAt, offeredPlans[], defaultCampusId, campuses[] }` (401 `{ message }`).
  - `POST /api/payment/{vipps|stripe}/membership-checkout` body `{ planId, campusId, client: "app" }` → `{ checkoutUrl, orderId }`; errors `{ message }` with 401/403/409/503.
  - Return deep links: `biso://membership?orderId=…&status=…`, `biso://membership?orderId=…&cancelled=1`, and `biso://membership?linked=1` from `https://biso.no/membership/link`.
- Every request to `apps/api` sends `Authorization: Bearer <Appwrite JWT>` from `account.createJWT()`; a missing session sends none and the server's 401 is surfaced.
- Commit messages: imperative sentence case, no type prefix (repo style, e.g. "Keep the back to sign-in button on the code screen"), ending with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## File map

| Area | Files |
|---|---|
| API auth | Create `lib/data/services/api_auth.dart` |
| Profile writes | Create `lib/data/services/profile_api_client.dart`; modify `lib/data/services/auth_service.dart`, `lib/data/services/privacy_service.dart` |
| Expenses | Modify `lib/data/services/expense_api_client.dart`, `lib/providers/expense/expense_provider.dart`, `lib/presentation/screens/expense/create_expense_screen.dart`, `lib/presentation/screens/explore/expenses_screen.dart`, `lib/presentation/screens/profile/profile_screen.dart`; create `lib/presentation/widgets/expenses_unavailable_page.dart` |
| Membership data | Create `lib/data/models/membership_overview.dart`, `lib/data/services/membership_api_client.dart` |
| Membership state | Create `lib/providers/membership/membership_overview_provider.dart`, `lib/providers/membership/membership_checkout_provider.dart`; modify `lib/providers/auth/auth_provider.dart`, `lib/main.dart` |
| Membership UI | Create `lib/presentation/screens/profile/membership_screen.dart`; modify `lib/main.dart`, `lib/presentation/screens/profile/profile_screen.dart`, `lib/data/services/deep_link_service.dart`, `test/presentation/design_rules_test.dart` |
| Removals | Delete `lib/data/services/membership_service.dart`, `lib/data/services/student_service.dart`, `lib/data/services/oauth_service.dart`, `lib/providers/membership/membership_provider.dart`, `lib/presentation/screens/profile/student_id_screen.dart`, `lib/presentation/widgets/membership_purchase_modal.dart`, `lib/presentation/widgets/show_membership_purchase_modal.dart`; modify `lib/data/services/auth_service.dart`, `lib/data/services/validator_service.dart`, `pubspec.yaml`, `ios/Runner/Info.plist`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `CLAUDE.md` |

---

### Task 1: Save profiles through `PUT /api/profile`

**Files:**
- Create: `lib/data/services/api_auth.dart`
- Create: `lib/data/services/profile_api_client.dart`
- Create: `test/data/services/profile_api_client_test.dart`
- Modify: `lib/data/services/auth_service.dart`
- Modify: `lib/data/services/privacy_service.dart`

**Interfaces:**
- Produces (`api_auth.dart`): `typedef ApiJwtProvider = Future<String?> Function();`, `Future<String?> appwriteJwt()`, `Uri apiUri(String path, [Map<String, String>? query])`.
- Produces (`profile_api_client.dart`): `class ProfileApiException implements Exception { final String message; final int? statusCode; }` and `class ProfileApiClient { ProfileApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider}); Future<Map<String, dynamic>> upsert(Map<String, dynamic> fields); }`.
- `AuthService` gains an optional constructor parameter `AuthService({ProfileApiClient? profileApi})`.

- [ ] **Step 1: Write the failing test**

Create `test/data/services/profile_api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:biso/data/services/profile_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  ProfileApiClient clientReturning(
    http.Response response, {
    String? jwt = 'jwt-1',
  }) {
    return ProfileApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => jwt,
    );
  }

  test('saves fields with a bearer token and returns the saved row', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': true,
          'profile': {r'$id': 'user-1', 'name': 'Ada', 'is_public': true},
        }),
        200,
      ),
    );

    final profile = await client.upsert({'name': 'Ada', 'is_public': true});

    expect(sent.method, 'PUT');
    expect(sent.url.toString(), 'https://api.biso.no/api/profile');
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(jsonDecode(sent.body), {'name': 'Ada', 'is_public': true});
    expect(profile[r'$id'], 'user-1');
  });

  test('sends no authorization header without a session', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Authentication required'}),
        401,
      ),
      jwt: null,
    );

    await expectLater(
      client.upsert({'name': 'Ada'}),
      throwsA(
        isA<ProfileApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Authentication required'),
      ),
    );
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('surfaces the server message when a value is rejected', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Invalid profile'}),
        400,
      ),
    );

    await expectLater(
      client.upsert({'name': 'x' * 31}),
      throwsA(
        isA<ProfileApiException>().having(
          (e) => e.message,
          'message',
          'Invalid profile',
        ),
      ),
    );
  });

  test('turns a non-JSON gateway error into a readable failure', () async {
    final client = clientReturning(http.Response('<html>502</html>', 502));

    await expectLater(
      client.upsert({'name': 'Ada'}),
      throwsA(
        isA<ProfileApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having(
              (e) => e.message,
              'message',
              'We could not save your profile.',
            ),
      ),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/services/profile_api_client_test.dart`
Expected: FAIL — `profile_api_client.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/data/services/api_auth.dart`:

```dart
import '../../core/constants/app_constants.dart';
import 'appwrite_service.dart';

/// Supplies the bearer token `apps/api` authenticates the app with.
typedef ApiJwtProvider = Future<String?> Function();

/// A short-lived Appwrite JWT for the signed-in account, or null without a
/// session. A request then goes out unauthenticated and the server's 401 is
/// what the caller shows, rather than a local guess about the session.
Future<String?> appwriteJwt() async {
  try {
    return (await account.createJWT()).jwt;
  } catch (_) {
    return null;
  }
}

/// [path] on the `apps/api` base URL, without doubling the slash.
Uri apiUri(String path, [Map<String, String>? query]) {
  final base = AppConstants.apiBaseUrl.endsWith('/')
      ? AppConstants.apiBaseUrl.substring(0, AppConstants.apiBaseUrl.length - 1)
      : AppConstants.apiBaseUrl;
  return Uri.parse(
    '$base$path',
  ).replace(queryParameters: query == null || query.isEmpty ? null : query);
}
```

Create `lib/data/services/profile_api_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_auth.dart';

/// A profile save the server refused, with its message.
class ProfileApiException implements Exception {
  const ProfileApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Saves the signed-in person's own profile through `apps/api`.
///
/// Profile rows are read-only to their owner, so the app cannot write them
/// directly. The server keeps only self-service fields — name, contact and
/// bank details, avatar, bio, privacy, campus and interests — and drops
/// everything else. The student id and other BI link fields are set by the
/// BI link on biso.no, never through here.
class ProfileApiClient {
  ProfileApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);
  static const String _fallbackMessage = 'We could not save your profile.';

  /// Writes [fields] (creating the profile if it does not exist yet) and
  /// returns the saved row.
  Future<Map<String, dynamic>> upsert(Map<String, dynamic> fields) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await client
          .put(
            apiUri('/api/profile'),
            headers: {
              'content-type': 'application/json',
              if (jwt != null) 'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode(fields),
          )
          .timeout(_timeout);

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        body = <String, dynamic>{};
      }

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      final profile = body['profile'];
      if (!ok || body['success'] != true || profile is! Map<String, dynamic>) {
        throw ProfileApiException(
          (body['error'] ?? _fallbackMessage).toString(),
          statusCode: response.statusCode,
        );
      }
      return profile;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
```

In `lib/data/services/auth_service.dart`:

1. Add `import 'profile_api_client.dart';` and, as the first members of `AuthService`:

```dart
  AuthService({ProfileApiClient? profileApi})
    : _profileApi = profileApi ?? ProfileApiClient();

  /// Profile rows are read-only to their owner; every profile write goes
  /// through `PUT /api/profile`.
  final ProfileApiClient _profileApi;
```

2. Replace the body of `createUserProfile` with:

```dart
    try {
      // The server stamps the account's email on a new row itself.
      final saved = await _profileApi.upsert({
        'name': name,
        'phone': phone,
        'address': address,
        'city': city,
        'zip': zipCode,
        'campus_id': campusId,
        'departments': departments ?? <String>[],
        'bank_account': bankAccount,
      });
      return UserModel.fromMap(saved);
    } on ProfileApiException catch (e) {
      throw AuthException('Failed to create profile: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred');
    }
```

3. In `updateUserProfile`, replace

```dart
      final doc = await _databases.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: currentUser.id,
        data: updatedData,
      );

      final updatedUser = UserModel.fromMap(doc.data);
```

with

```dart
      final updatedUser = UserModel.fromMap(
        await _profileApi.upsert(updatedData),
      );
```

and add `on ProfileApiException catch (e) { throw AuthException('Failed to update profile: ${e.message}'); }` before its existing `on AppwriteException` clause.

4. In `updatePaymentInformation`, replace

```dart
      final response = await _databases.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: currentUser.id,
        data: updateData,
      );
```

with `final response = await _profileApi.upsert(updateData);`, change `return UserModel.fromDocument(response);` to `return UserModel.fromMap(response);`, and add `on ProfileApiException catch (e) { throw AuthException('Failed to update payment information: ${e.message}'); }` before its `on AppwriteException` clause.

In `lib/data/services/privacy_service.dart`: add `import 'profile_api_client.dart';`, add the field `final ProfileApiClient _profileApi = ProfileApiClient();` under `PrivacyService._internal();`, and replace

```dart
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
        data: {'is_public': isPublic},
      );
```

with

```dart
      // Profile rows are read-only to their owner; the privacy flag is saved
      // through the API like every other profile field.
      await _profileApi.upsert({'is_public': isPublic});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/services/profile_api_client_test.dart && flutter analyze lib/data/services`
Expected: PASS; no new analyzer issues (remove any import that became unused, e.g. `app_constants.dart` in `privacy_service.dart` only if nothing else uses it).

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/api_auth.dart lib/data/services/profile_api_client.dart test/data/services/profile_api_client_test.dart lib/data/services/auth_service.dart lib/data/services/privacy_service.dart
git commit -m "Save profiles through the API instead of writing the row directly

Profile rows become read-only to their owner so a student cannot write
someone else's student id into their own profile. Onboarding, profile edits,
payment details and the privacy switch now save through PUT /api/profile.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 2: Upload receipts, delete drafts and follow the reimbursements switch through the API

**Files:**
- Modify: `lib/data/services/expense_api_client.dart`
- Create: `test/data/services/expense_api_client_test.dart`
- Modify: `lib/providers/expense/expense_provider.dart`
- Modify: `lib/providers/config/app_config_provider.dart`
- Create: `lib/presentation/widgets/expenses_unavailable_page.dart`
- Modify: `lib/presentation/screens/explore/expenses_screen.dart`
- Modify: `lib/presentation/screens/expense/create_expense_screen.dart`
- Modify: `lib/presentation/screens/profile/profile_screen.dart`
- Create: `test/presentation/screens/explore/expenses_unavailable_test.dart`
- Modify: `test/presentation/screens/profile/profile_design_test.dart`, `test/presentation/screens/explore/expenses_design_test.dart`, `test/presentation/screens/expense/create_expense_design_test.dart` (overrides only)
- Modify: `test/presentation/design_rules_test.dart`

**Interfaces:**
- Consumes: `ApiJwtProvider`, `appwriteJwt`, `apiUri` (Task 1).
- Produces: `ExpenseApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})`, `Future<ExpenseUploadedFile> uploadExpenseAttachment(File file)` (now via `POST /api/expenses/attachments`), `Future<void> deleteDraft(String expenseId)`.
- Produces: `final expensesEnabledProvider = Provider<bool?>` in `app_config_provider.dart` (null while the config loads); `ExpensesNotifier(ExpenseServiceV2 service, ExpenseApiClient api)`; `ExpensesUnavailablePage`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/services/expense_api_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:biso/data/services/expense_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('expense_api_client_test');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ExpenseApiClient clientReturning(http.Response response) {
    return ExpenseApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-1',
    );
  }

  File pngReceipt() {
    final file = File('${tempDir.path}/receipt.png');
    file.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    return file;
  }

  test('uploads a receipt to the attachments route and reads the stored file', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': true,
          'file': {
            'fileId': 'file-1',
            'mimeType': 'image/png',
            'name': 'receipt.png',
            'size': 8,
            'viewUrl': 'https://appwrite.biso.no/v1/storage/buckets/expenses/files/file-1/view?project=biso',
          },
        }),
        201,
      ),
    );

    final uploaded = await client.uploadExpenseAttachment(pngReceipt());

    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/expenses/attachments',
    );
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(utf8.decode(sent.bodyBytes, allowMalformed: true), contains('filename="receipt.png"'));
    expect(uploaded.fileId, 'file-1');
    expect(uploaded.fileName, 'receipt.png');
    expect(uploaded.mimeType, 'image/png');
    expect(uploaded.viewUrl, contains('/files/file-1/view'));
  });

  test("shows the server's reason when a receipt is refused", () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'error': 'Unsupported file type. Please upload a PDF, PNG, or JPEG file.',
        }),
        415,
      ),
    );

    await expectLater(
      client.uploadExpenseAttachment(pngReceipt()),
      throwsA(
        isA<ExpenseApiException>()
            .having((e) => e.statusCode, 'statusCode', 415)
            .having((e) => e.message, 'message', contains('PDF, PNG, or JPEG')),
      ),
    );
  });

  test('deletes a draft through the draft route', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'success': true}), 200),
    );

    await client.deleteDraft('expense-1');

    expect(sent.method, 'DELETE');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/expenses/draft?expenseId=expense-1',
    );
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
  });

  test('refuses to report a submitted expense as deleted', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'error': 'Only draft expenses can be deleted',
        }),
        409,
      ),
    );

    await expectLater(
      client.deleteDraft('expense-1'),
      throwsA(
        isA<ExpenseApiException>().having(
          (e) => e.message,
          'message',
          'Only draft expenses can be deleted',
        ),
      ),
    );
  });

  test('turns a non-JSON error page into a readable failure', () async {
    final client = clientReturning(http.Response('<html>502</html>', 502));

    await expectLater(
      client.deleteDraft('expense-1'),
      throwsA(isA<ExpenseApiException>()),
    );
  });
}
```

Create `test/presentation/screens/explore/expenses_unavailable_test.dart`:

```dart
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/screens/explore/expenses_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(id: 'u1', name: 'Test Student', email: 'student@bi.no');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _switchedOff() => [
  authStateProvider.overrideWith((_) => _Auth()),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: false),
  ),
];

void main() {
  testWidgets('the expenses list says reimbursements are off instead of loading', (
    tester,
  ) async {
    await pumpBisoScreen(tester, const ExpensesScreen(), overrides: _switchedOff());
    await tester.pumpAndSettle();

    expect(find.text('Reimbursements are currently unavailable'), findsOneWidget);
  });

  testWidgets('a deep link to a new expense also lands on the unavailable page', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(),
      overrides: _switchedOff(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reimbursements are currently unavailable'), findsOneWidget);
  });
}
```

(If `UserModel` or `CreateExpenseScreen` require more constructor arguments than shown, pass the minimal values the compiler asks for; do not change the assertions.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/services/expense_api_client_test.dart test/presentation/screens/explore/expenses_unavailable_test.dart`
Expected: FAIL — `ExpenseApiClient` has no `jwtProvider`/`deleteDraft`, uploads go to Appwrite storage, and neither screen knows the switch.

- [ ] **Step 3: Implement**

Replace `lib/data/services/expense_api_client.dart` above `detectExpenseMimeType` with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../models/expense_v2_models.dart';
import 'api_auth.dart';

class ExpenseApiException implements Exception {
  final String message;
  final int? statusCode;

  const ExpenseApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// The app's client for the reimbursement routes on `apps/api`.
///
/// Expense rows are read-only to the student and the `expenses` bucket has no
/// user create grant, so every write — receipts, drafts, submission, draft
/// deletion — goes through the API with the student's JWT.
class ExpenseApiClient {
  ExpenseApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _jsonTimeout = Duration(seconds: 20);

  /// Stores one receipt and returns the file the draft should reference.
  Future<ExpenseUploadedFile> uploadExpenseAttachment(File file) async {
    final request = http.MultipartRequest(
      'POST',
      apiUri('/api/expenses/attachments'),
    );
    request.headers.addAll(await _authHeaders());
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(detectExpenseMimeType(file.path)),
      ),
    );

    final response = await _sendMultipart(
      request,
      const Duration(seconds: 60),
    );
    final data = _decodeResponse(response.body, response.statusCode);
    final stored = data['file'];
    if (stored is! Map || stored['fileId'] == null) {
      throw const ExpenseApiException('The receipt could not be stored.');
    }
    return ExpenseUploadedFile(
      fileId: stored['fileId'].toString(),
      viewUrl: (stored['viewUrl'] ?? '').toString(),
      mimeType: (stored['mimeType'] ?? detectExpenseMimeType(file.path))
          .toString(),
      fileName: (stored['name'] ?? '').toString(),
    );
  }

  Future<ExpenseOcrResult> runOcr(File file, {String? purpose}) async {
    final request = http.MultipartRequest(
      'POST',
      apiUri('/api/expenses/ocr', {
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      }),
    );
    request.headers.addAll(await _authHeaders());
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(detectExpenseMimeType(file.path)),
      ),
    );

    final response = await _sendMultipart(
      request,
      const Duration(seconds: 30),
    );
    final data = _decodeResponse(response.body, response.statusCode);
    return ExpenseOcrResult.fromMap(data);
  }

  Future<String> summarize({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) async {
    final payload = ExpensePayloadBuilder.buildSummaryPayload(
      assignment: assignment,
      receipts: receipts,
    );
    final data = await _postJson('/api/expenses/summary', payload);
    return (data['summary'] ?? '').toString();
  }

  Future<ExpenseDraftResult> saveDraft(Map<String, dynamic> payload) async {
    final data = await _postJson('/api/expenses/draft', payload);
    return ExpenseDraftResult.fromMap(data);
  }

  Future<ExpenseSubmitResult> submit(Map<String, dynamic> payload) async {
    final data = await _postJson('/api/expenses/submit', payload);
    return ExpenseSubmitResult.fromMap(data);
  }

  /// Deletes one of the student's own drafts and the receipts it referenced.
  /// The server refuses anything that has left draft.
  Future<void> deleteDraft(String expenseId) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client
          .delete(
            apiUri('/api/expenses/draft', {'expenseId': expenseId}),
            headers: await _authHeaders(),
          )
          .timeout(_jsonTimeout);
      _decodeResponse(response.body, response.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client
          .post(
            apiUri(path),
            headers: {
              ...await _authHeaders(),
              'content-type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_jsonTimeout);
      return _decodeResponse(response.body, response.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendMultipart(
    http.MultipartRequest request,
    Duration timeout,
  ) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final streamed = await client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final jwt = await _jwtProvider();
    return jwt == null ? const {} : {'Authorization': 'Bearer $jwt'};
  }

  Map<String, dynamic> _decodeResponse(String body, int statusCode) {
    Map<String, dynamic> map;
    try {
      final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      map = <String, dynamic>{};
    }
    if (statusCode < 200 || statusCode >= 300 || map['success'] == false) {
      throw ExpenseApiException(
        (map['error'] ?? map['message'] ?? 'Expense API request failed')
            .toString(),
        statusCode: statusCode,
      );
    }
    return map;
  }
}
```

(Keep `detectExpenseMimeType` below unchanged. The `appwrite` and `app_constants.dart` imports and `_publicFileUrl` are gone with the direct storage upload.)

In `lib/providers/expense/expense_provider.dart`:

```dart
final expensesStateProvider =
    StateNotifierProvider<ExpensesNotifier, ExpensesState>((ref) {
      return ExpensesNotifier(
        ref.watch(expenseServiceProvider),
        ref.watch(expenseApiClientProvider),
      );
    });
```

and in `ExpensesNotifier`: add `final ExpenseApiClient _api;`, change the constructor to `ExpensesNotifier(this._service, this._api) : super(const ExpensesState()) {`, and in `deleteExpense` replace `await _service.deleteExpense(expenseId);` with:

```dart
      // Students have no delete grant on expense rows; the API checks the
      // draft is theirs and still a draft before deleting it.
      await _api.deleteDraft(expenseId);
```

Run `grep -rn "ExpensesNotifier(" lib test` and pass an `ExpenseApiClient` wherever one is constructed.

Remove the direct-write paths nothing uses any more, so they cannot be called by mistake:
- from `ExpensesNotifier`: the methods `createExpense` and `updateExpense` (no screen calls them);
- from `lib/data/services/expense_service_v2.dart`: `createExpense`, `updateExpense`, `deleteExpense`, `addExpenseAttachment`, `createExpenseDocument`, `uploadAttachmentFile`, `createAttachmentDocument`, `analyzeReceiptText`, `summarizeExpenseDescriptions`, plus any private helper or import only they used. Keep the read methods (`getUserExpenses`, `getExpense`, `getExpensesByStatus`, `getExpensesByCampus`, `getExpensesByDepartment`, `getExpenseStatistics`, `listDepartmentsForCampus`, `listCampuses`).

If a test fake (for example in `create_expense_design_test.dart`) overrides one of the removed methods, delete that override.

Append to `lib/providers/config/app_config_provider.dart`:

```dart
/// Whether reimbursements are switched on (`expenses_module` in the admin),
/// or null while the config is still loading. The API enforces the same
/// switch; this only decides what the app offers.
final expensesEnabledProvider = Provider<bool?>((ref) {
  return ref.watch(appConfigProvider).valueOrNull?.expensesEnabled;
});
```

Create `lib/presentation/widgets/expenses_unavailable_page.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/utils/navigation_utils.dart';
import 'biso/biso.dart';

/// Shown instead of the reimbursement screens while BISO has reimbursements
/// switched off.
///
/// Every way in — Explore, Profile, deep links, the share sheet and home
/// screen shortcuts — lands on those screens, so checking the switch there
/// covers them all. The API refuses submissions either way.
class ExpensesUnavailablePage extends StatelessWidget {
  const ExpensesUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BisoPage(
      title: 'Reimbursements',
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      slivers: const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.doc_text,
            accent: BisoAccent.coral,
            title: 'Reimbursements are currently unavailable',
            message:
                'You can submit expenses here again as soon as BISO switches '
                'reimbursements back on.',
          ),
        ),
      ],
    );
  }
}
```

In `lib/presentation/screens/explore/expenses_screen.dart`: import `../../../providers/config/app_config_provider.dart` and `../../widgets/expenses_unavailable_page.dart`, and directly after the `if (!authState.isAuthenticated) { … }` block in `build` add:

```dart
    if (ref.watch(expensesEnabledProvider) == false) {
      return const ExpensesUnavailablePage();
    }
```

In `lib/presentation/screens/expense/create_expense_screen.dart`:
1. Import the same two files, and make the first statement of the state's `Widget build(BuildContext context)`:

```dart
    if (ref.watch(expensesEnabledProvider) == false) {
      return const ExpensesUnavailablePage();
    }
```

2. Give both `pickImage` calls `imageQuality: 90` (re-encodes HEIC photos as JPEG, which the API and the ledger merge accept): `_imagePicker.pickImage(source: ImageSource.camera, imageQuality: 90)` and `_imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90)`.
3. In both `FilePicker.pickFiles` calls change `allowedExtensions` to `['pdf', 'jpg', 'jpeg', 'png']`.
4. In `_isSupportedOcrMime`, reduce the set to `{'image/jpeg', 'image/png', 'application/pdf'}`.

In `lib/presentation/screens/profile/profile_screen.dart`: delete `_featureFlagServiceProvider`, `expenseFeatureFlagProvider` and the `feature_flag_service.dart` import; import `../../../providers/config/app_config_provider.dart`; replace

```dart
    final expenseFlagAsync = ref.watch(expenseFeatureFlagProvider);
    final showExpenseHistory = expenseFlagAsync.valueOrNull ?? false;
```

with

```dart
    final showExpenseHistory = ref.watch(expensesEnabledProvider) ?? false;
```

Tests that referenced the old provider: in `test/presentation/screens/profile/profile_design_test.dart` replace `expenseFeatureFlagProvider.overrideWith((_) async => true),` with `appConfigProvider.overrideWith((_) async => const AppConfig(expensesEnabled: true)),` (import `package:biso/data/models/app_config.dart` and `package:biso/providers/config/app_config_provider.dart`). Run `grep -rn expenseFeatureFlagProvider test lib` and apply the same replacement wherever it appears. In `expenses_design_test.dart` and `create_expense_design_test.dart`, add that same `appConfigProvider` override to every overrides list, so the screens never reach the network in tests.

Add `'lib/presentation/widgets/expenses_unavailable_page.dart',` to `migratedFiles` in `test/presentation/design_rules_test.dart`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/services/expense_api_client_test.dart test/presentation/screens/explore test/presentation/screens/expense test/presentation/screens/profile test/presentation/design_rules_test.dart`
Run: `flutter analyze`
Expected: PASS; no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/expense_api_client.dart lib/data/services/expense_service_v2.dart test/data/services/expense_api_client_test.dart lib/providers/expense/expense_provider.dart lib/providers/config/app_config_provider.dart lib/presentation/widgets/expenses_unavailable_page.dart lib/presentation/screens/explore/expenses_screen.dart lib/presentation/screens/expense/create_expense_screen.dart lib/presentation/screens/profile/profile_screen.dart test/presentation
git commit -m "Upload receipts and delete drafts through the API

The expenses bucket and expense rows give students no write access, so
receipt uploads and draft deletes failed. Both now go through apps/api,
photos are re-encoded as JPEG, and the reimbursement screens follow the
admin's live switch instead of a hard-coded flag.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 3: Membership overview model and API client

**Files:**
- Create: `lib/data/models/membership_overview.dart`
- Create: `test/data/models/membership_overview_test.dart`
- Create: `lib/data/services/membership_api_client.dart`
- Create: `test/data/services/membership_api_client_test.dart`

**Interfaces:**
- Consumes: `ApiJwtProvider`, `appwriteJwt`, `apiUri` (Task 1); `PaymentProvider` (`lib/data/models/payment_provider.dart`); `StartedCheckout` (`lib/data/services/shop_api_client.dart`).
- Produces (`membership_overview.dart`):
  - `enum MembershipGateState { needsBiLink, needsDirectoryRecord, checkUnavailable, alreadyMember, noPlansAvailable, eligible }` with `static MembershipGateState fromValue(String?)` (unknown → `checkUnavailable`).
  - `class MembershipPeriod { String id; String name; String? category; DateTime? startDate; DateTime? expiryDate; }`
  - `class MembershipPlanOption { String id; String name; double price; String duration; int accrualMonths; DateTime? startDate; DateTime? expiryDate; }`
  - `class MembershipCampus { String id; String name; }`
  - `class MembershipOverview { MembershipGateState state; String? studentId; bool isMember; List<MembershipPeriod> memberships; List<MembershipPeriod> expiredMemberships; DateTime? currentExpiry; String? reason; DateTime checkedAt; List<MembershipPlanOption> offeredPlans; String? defaultCampusId; List<MembershipCampus> campuses; bool fromCache; }` with `fromJson(Map<String, dynamic>, {bool fromCache = false})`, `toJson()`, `asCached()`, getters `isLinked`, `canPurchase`, `currentMembership`, `lastExpiredMembership`.
- Produces (`membership_api_client.dart`): `class MembershipApiException { String message; int? statusCode; bool get isUnauthorized; bool get isProviderDisabled; bool get isAlreadyCovered; bool get isUnavailable; }` and `class MembershipApiClient { MembershipApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider}); Future<MembershipOverview> fetchOverview({bool refresh = false}); Future<StartedCheckout> startCheckout({required PaymentProvider provider, required String planId, required String campusId}); }`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/models/membership_overview_test.dart`:

```dart
import 'package:biso/data/models/membership_overview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> serverOverview({
  String state = 'eligible',
  bool isMember = true,
}) => {
  'state': state,
  'studentId': 's1715738',
  'isMember': isMember,
  'memberships': [
    {
      'id': 'semester',
      'name': 'BISO Membership fall 2026',
      'category': '113176',
      'startDate': '2026-08-01',
      'expiryDate': '2026-12-31',
    },
    {
      'id': 'year',
      'name': 'BISO Membership fall 2026 and spring 2027',
      'category': '113178',
      'startDate': '2026-08-01',
      'expiryDate': '2027-06-30',
    },
  ],
  'expiredMemberships': [
    {
      'id': 'spring',
      'name': 'BISO Membership spring 2026',
      'category': '113170',
      'startDate': '2026-01-01',
      'expiryDate': '2026-06-30',
    },
  ],
  'currentExpiry': '2027-06-30',
  'reason': null,
  'checkedAt': '2026-09-15T08:00:00.000Z',
  'offeredPlans': [
    {
      'id': '82',
      'name': 'BISO Membership fall 2026 - spring 2029',
      'price': 1350,
      'duration': 'three_years',
      'accrualMonths': 36,
      'startDate': '2026-08-01',
      'expiryDate': '2029-06-30',
    },
  ],
  'defaultCampusId': '2',
  'campuses': [
    {'id': '1', 'name': 'Oslo'},
    {'id': '2', 'name': 'Bergen'},
  ],
};

void main() {
  test('reads the server overview', () {
    final overview = MembershipOverview.fromJson(serverOverview());

    expect(overview.state, MembershipGateState.eligible);
    expect(overview.studentId, 's1715738');
    expect(overview.isMember, isTrue);
    expect(overview.currentMembership?.id, 'year');
    expect(overview.lastExpiredMembership?.id, 'spring');
    expect(overview.currentExpiry, DateTime(2027, 6, 30));
    expect(overview.checkedAt, DateTime.utc(2026, 9, 15, 8));
    expect(overview.offeredPlans.single.price, 1350);
    expect(overview.offeredPlans.single.accrualMonths, 36);
    expect(overview.campuses.map((c) => c.name), ['Oslo', 'Bergen']);
    expect(overview.canPurchase, isTrue);
    expect(overview.isLinked, isTrue);
    expect(overview.fromCache, isFalse);
  });

  test('never reads an unknown state as permission to buy', () {
    final overview = MembershipOverview.fromJson(
      serverOverview(state: 'something_new'),
    );

    expect(overview.state, MembershipGateState.checkUnavailable);
    expect(overview.canPurchase, isFalse);
  });

  test('an unlinked student is not linked and cannot buy', () {
    final overview = MembershipOverview.fromJson({
      ...serverOverview(state: 'needs_bi_link', isMember: false),
      'studentId': null,
      'memberships': <Object>[],
      'offeredPlans': <Object>[],
    });

    expect(overview.isLinked, isFalse);
    expect(overview.canPurchase, isFalse);
    expect(overview.currentMembership, isNull);
  });

  test('survives a round trip through the device cache, marked as cached', () {
    final original = MembershipOverview.fromJson(serverOverview());

    final restored = MembershipOverview.fromJson(
      original.toJson(),
    ).asCached();

    expect(restored.fromCache, isTrue);
    expect(restored.state, original.state);
    expect(restored.memberships, original.memberships);
    expect(restored.expiredMemberships, original.expiredMemberships);
    expect(restored.offeredPlans, original.offeredPlans);
    expect(restored.checkedAt, original.checkedAt);
  });
}
```

Create `test/data/services/membership_api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  MembershipApiClient clientReturning(http.Response response) {
    return MembershipApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-1',
    );
  }

  final overviewBody = jsonEncode({
    'state': 'needs_bi_link',
    'studentId': null,
    'isMember': false,
    'memberships': <Object>[],
    'expiredMemberships': <Object>[],
    'currentExpiry': null,
    'reason': 'no_student_id',
    'checkedAt': '2026-09-15T08:00:00.000Z',
    'offeredPlans': <Object>[],
    'defaultCampusId': null,
    'campuses': [
      {'id': '1', 'name': 'Oslo'},
    ],
  });

  test('fetches the overview with the student token', () async {
    final client = clientReturning(http.Response(overviewBody, 200));

    final overview = await client.fetchOverview();

    expect(sent.method, 'GET');
    expect(sent.url.toString(), 'https://api.biso.no/api/membership');
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(overview.state, MembershipGateState.needsBiLink);
  });

  test('asks the server to re-check when refreshing', () async {
    final client = clientReturning(http.Response(overviewBody, 200));

    await client.fetchOverview(refresh: true);

    expect(
      sent.url.toString(),
      'https://api.biso.no/api/membership?refresh=1',
    );
  });

  test('reports a missing session as unauthorized', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'message': 'Authentication required'}), 401),
    );

    await expectLater(
      client.fetchOverview(),
      throwsA(
        isA<MembershipApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('starts a membership checkout that returns to the app', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'checkoutUrl': 'https://vipps.example/checkout',
          'orderId': 'order-1',
        }),
        200,
      ),
    );

    final started = await client.startCheckout(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );

    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/payment/vipps/membership-checkout',
    );
    expect(jsonDecode(sent.body), {
      'campusId': '2',
      'client': 'app',
      'planId': '71',
    });
    expect(started.checkoutUrl, 'https://vipps.example/checkout');
    expect(started.orderId, 'order-1');
  });

  test("surfaces the server's reason when a purchase is refused", () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'message': 'Your membership already covers this period.'}),
        409,
      ),
    );

    await expectLater(
      client.startCheckout(
        provider: PaymentProvider.stripe,
        planId: '71',
        campusId: '1',
      ),
      throwsA(
        isA<MembershipApiException>()
            .having((e) => e.isAlreadyCovered, 'isAlreadyCovered', isTrue)
            .having(
              (e) => e.message,
              'message',
              'Your membership already covers this period.',
            ),
      ),
    );
  });

  test('refuses a checkout answer without a payment link', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'orderId': 'order-1'}), 200),
    );

    await expectLater(
      client.startCheckout(
        provider: PaymentProvider.vipps,
        planId: '71',
        campusId: '1',
      ),
      throwsA(isA<MembershipApiException>()),
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/models/membership_overview_test.dart test/data/services/membership_api_client_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Implement**

Create `lib/data/models/membership_overview.dart`:

```dart
import 'package:equatable/equatable.dart';

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String? _formatDate(DateTime? value) => value?.toIso8601String();

List<T> _parseList<T>(
  Object? value,
  T Function(Map<String, dynamic>) parse,
) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((entry) => parse(Map<String, dynamic>.from(entry)))
      .toList(growable: false);
}

/// Where a student stands on buying a membership. The server decides it with
/// the same gate biso.no's join page uses.
enum MembershipGateState {
  needsBiLink('needs_bi_link'),
  needsDirectoryRecord('needs_directory_record'),
  checkUnavailable('membership_check_unavailable'),
  alreadyMember('already_member'),
  noPlansAvailable('no_plans_available'),
  eligible('eligible');

  const MembershipGateState(this.value);

  final String value;

  /// An unknown state reads as "cannot tell right now", never as eligible.
  static MembershipGateState fromValue(String? value) {
    for (final state in MembershipGateState.values) {
      if (state.value == value) return state;
    }
    return MembershipGateState.checkUnavailable;
  }
}

/// One membership period a student holds, or held.
class MembershipPeriod extends Equatable {
  final String id;
  final String name;
  final String? category;
  final DateTime? startDate;
  final DateTime? expiryDate;

  const MembershipPeriod({
    required this.id,
    required this.name,
    this.category,
    this.startDate,
    this.expiryDate,
  });

  factory MembershipPeriod.fromJson(Map<String, dynamic> json) {
    return MembershipPeriod(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: json['category']?.toString(),
      startDate: _parseDate(json['startDate']),
      expiryDate: _parseDate(json['expiryDate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'startDate': _formatDate(startDate),
    'expiryDate': _formatDate(expiryDate),
  };

  @override
  List<Object?> get props => [id, name, category, startDate, expiryDate];
}

/// A membership plan the student may buy right now.
class MembershipPlanOption extends Equatable {
  final String id;
  final String name;
  final double price;
  final String duration;
  final int accrualMonths;
  final DateTime? startDate;
  final DateTime? expiryDate;

  const MembershipPlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.accrualMonths,
    this.startDate,
    this.expiryDate,
  });

  factory MembershipPlanOption.fromJson(Map<String, dynamic> json) {
    return MembershipPlanOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] ?? '').toString(),
      accrualMonths: (json['accrualMonths'] as num?)?.toInt() ?? 0,
      startDate: _parseDate(json['startDate']),
      expiryDate: _parseDate(json['expiryDate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'duration': duration,
    'accrualMonths': accrualMonths,
    'startDate': _formatDate(startDate),
    'expiryDate': _formatDate(expiryDate),
  };

  @override
  List<Object?> get props => [
    id,
    name,
    price,
    duration,
    accrualMonths,
    startDate,
    expiryDate,
  ];
}

/// A BI campus a membership can be booked to.
class MembershipCampus extends Equatable {
  final String id;
  final String name;

  const MembershipCampus({required this.id, required this.name});

  factory MembershipCampus.fromJson(Map<String, dynamic> json) =>
      MembershipCampus(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

/// The signed-in student's membership, as `GET /api/membership` reports it:
/// live 24SevenOffice status with expired memberships excluded, the purchase
/// gate, and the plans on offer.
class MembershipOverview extends Equatable {
  final MembershipGateState state;
  final String? studentId;
  final bool isMember;
  final List<MembershipPeriod> memberships;
  final List<MembershipPeriod> expiredMemberships;
  final DateTime? currentExpiry;
  final String? reason;
  final DateTime checkedAt;
  final List<MembershipPlanOption> offeredPlans;
  final String? defaultCampusId;
  final List<MembershipCampus> campuses;

  /// The last verified overview kept on this device, shown because a fresh
  /// check could not be made.
  final bool fromCache;

  const MembershipOverview({
    required this.state,
    required this.isMember,
    required this.checkedAt,
    this.studentId,
    this.memberships = const [],
    this.expiredMemberships = const [],
    this.currentExpiry,
    this.reason,
    this.offeredPlans = const [],
    this.defaultCampusId,
    this.campuses = const [],
    this.fromCache = false,
  });

  factory MembershipOverview.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) {
    return MembershipOverview(
      state: MembershipGateState.fromValue(json['state']?.toString()),
      studentId: json['studentId']?.toString(),
      isMember: json['isMember'] == true,
      memberships: _parseList(json['memberships'], MembershipPeriod.fromJson),
      expiredMemberships: _parseList(
        json['expiredMemberships'],
        MembershipPeriod.fromJson,
      ),
      currentExpiry: _parseDate(json['currentExpiry']),
      reason: json['reason']?.toString(),
      checkedAt: _parseDate(json['checkedAt']) ?? DateTime.now(),
      offeredPlans: _parseList(
        json['offeredPlans'],
        MembershipPlanOption.fromJson,
      ),
      defaultCampusId: json['defaultCampusId']?.toString(),
      campuses: _parseList(json['campuses'], MembershipCampus.fromJson),
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.value,
    'studentId': studentId,
    'isMember': isMember,
    'memberships': memberships.map((m) => m.toJson()).toList(),
    'expiredMemberships': expiredMemberships.map((m) => m.toJson()).toList(),
    'currentExpiry': _formatDate(currentExpiry),
    'reason': reason,
    'checkedAt': checkedAt.toIso8601String(),
    'offeredPlans': offeredPlans.map((p) => p.toJson()).toList(),
    'defaultCampusId': defaultCampusId,
    'campuses': campuses.map((c) => c.toJson()).toList(),
  };

  MembershipOverview asCached() => MembershipOverview(
    state: state,
    studentId: studentId,
    isMember: isMember,
    memberships: memberships,
    expiredMemberships: expiredMemberships,
    currentExpiry: currentExpiry,
    reason: reason,
    checkedAt: checkedAt,
    offeredPlans: offeredPlans,
    defaultCampusId: defaultCampusId,
    campuses: campuses,
    fromCache: true,
  );

  /// A BI student account is linked (or the link could not be checked).
  bool get isLinked => state != MembershipGateState.needsBiLink;

  bool get canPurchase =>
      state == MembershipGateState.eligible && offeredPlans.isNotEmpty;

  /// The active membership that runs longest.
  MembershipPeriod? get currentMembership {
    if (memberships.isEmpty) return null;
    final sorted = [...memberships]
      ..sort((a, b) {
        final left = a.expiryDate ?? DateTime(0);
        final right = b.expiryDate ?? DateTime(0);
        return right.compareTo(left);
      });
    return sorted.first;
  }

  /// The most recently expired membership (the server sends newest first).
  MembershipPeriod? get lastExpiredMembership =>
      expiredMemberships.isEmpty ? null : expiredMemberships.first;

  @override
  List<Object?> get props => [
    state,
    studentId,
    isMember,
    memberships,
    expiredMemberships,
    currentExpiry,
    reason,
    checkedAt,
    offeredPlans,
    defaultCampusId,
    campuses,
    fromCache,
  ];
}
```

Create `lib/data/services/membership_api_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/membership_overview.dart';
import '../models/payment_provider.dart';
import 'api_auth.dart';
import 'shop_api_client.dart' show StartedCheckout;

/// A membership request the server refused, with its message.
class MembershipApiException implements Exception {
  const MembershipApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  /// The payment provider has been switched off since the list was loaded.
  bool get isProviderDisabled => statusCode == 403;

  /// The student's cover already reaches the plan's end.
  bool get isAlreadyCovered => statusCode == 409;

  /// Membership could not be verified right now; nothing was charged.
  bool get isUnavailable => statusCode == 503;

  @override
  String toString() => message;
}

/// The app's client for membership on `apps/api`.
///
/// Membership is verified against 24SevenOffice on the server; the app only
/// asks. Purchases use the same trusted checkout as the website, marked
/// `client: "app"` so the payment provider returns the student to the app.
class MembershipApiClient {
  MembershipApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);

  /// The student's membership overview. [refresh] asks the server to re-check
  /// 24SevenOffice now (it does so at most once a minute).
  Future<MembershipOverview> fetchOverview({bool refresh = false}) async {
    final data = await _send(
      'GET',
      apiUri('/api/membership', refresh ? {'refresh': '1'} : null),
    );
    return MembershipOverview.fromJson(data);
  }

  /// Creates the membership order and payment session.
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    final data = await _send(
      'POST',
      apiUri('/api/payment/${provider.id}/membership-checkout'),
      body: {'campusId': campusId, 'client': 'app', 'planId': planId},
    );
    final checkoutUrl = data['checkoutUrl']?.toString() ?? '';
    final orderId = data['orderId']?.toString() ?? '';
    if (checkoutUrl.isEmpty || orderId.isEmpty) {
      throw const MembershipApiException('The payment could not be started.');
    }
    return StartedCheckout(checkoutUrl: checkoutUrl, orderId: orderId);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final request = http.Request(method, uri)
        ..headers.addAll({
          if (body != null) 'content-type': 'application/json',
          if (jwt != null) 'Authorization': 'Bearer $jwt',
        });
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await client.send(request).timeout(_timeout),
      );

      Map<String, dynamic> map;
      try {
        final decoded = jsonDecode(response.body);
        map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        map = <String, dynamic>{};
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MembershipApiException(
          (map['message'] ?? map['error'] ?? 'Something went wrong.')
              .toString(),
          statusCode: response.statusCode,
        );
      }
      return map;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/models/membership_overview_test.dart test/data/services/membership_api_client_test.dart && flutter analyze lib/data`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/membership_overview.dart lib/data/services/membership_api_client.dart test/data/models/membership_overview_test.dart test/data/services/membership_api_client_test.dart
git commit -m "Add the membership overview model and API client

The app reads its membership status, purchase gate and plans from
GET /api/membership and starts purchases through the trusted membership
checkout, marked as an app checkout so payment returns to the app.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 4: Verify membership at launch and on return, and retire the legacy membership code

**Files:**
- Create: `lib/providers/membership/membership_overview_provider.dart`
- Create: `test/providers/membership/membership_overview_provider_test.dart`
- Modify: `lib/providers/auth/auth_provider.dart`
- Modify: `lib/data/services/auth_service.dart`
- Modify: `lib/data/services/validator_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/presentation/screens/explore/webshop_product_detail_screen.dart` (import only)
- Modify: `test/presentation/screens/explore/webshop_product_detail_design_test.dart`, `test/presentation/screens/explore/webshop_product_detail_screen_test.dart` (imports only)
- Delete: `lib/data/services/membership_service.dart`, `lib/data/services/student_service.dart`, `lib/data/services/oauth_service.dart`, `lib/providers/membership/membership_provider.dart`, `lib/presentation/screens/profile/student_id_screen.dart`, `lib/presentation/widgets/membership_purchase_modal.dart`, `lib/presentation/widgets/show_membership_purchase_modal.dart`, `lib/data/models/membership_model.dart`, `lib/data/models/student_id_model.dart`

**Interfaces:**
- Consumes: `MembershipApiClient`, `MembershipOverview`, `MembershipGateState` (Task 3).
- Produces (`membership_overview_provider.dart`):
  - `final membershipApiClientProvider = Provider<MembershipApiClient>`
  - `final membershipUserIdProvider = Provider<String?>` (signed-in user id once auth has resolved; overridable in tests)
  - `final membershipOverviewProvider = AsyncNotifierProvider<MembershipOverviewNotifier, MembershipOverview?>` — `null` when signed out
  - `MembershipOverviewNotifier.refresh({bool force = true})`, `.noteLinkStarted()`, `static String cacheKey(String userId)`
  - `final hasValidMembershipProvider = Provider<bool>` (moved here from `auth_provider.dart`)
  - `const membershipRecheckAfter = Duration(minutes: 10)`, `const membershipCacheTrust = Duration(hours: 24)`

- [ ] **Step 1: Write the failing test**

Create `test/providers/membership/membership_overview_provider_test.dart`:

```dart
import 'dart:convert';

import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MembershipOverview overview({
  MembershipGateState state = MembershipGateState.eligible,
  bool isMember = true,
  DateTime? checkedAt,
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  studentId: 's1715738',
  checkedAt: checkedAt ?? DateTime.now(),
  memberships: isMember
      ? [
          MembershipPeriod(
            id: 'year',
            name: 'BISO Membership fall 2026 and spring 2027',
            expiryDate: DateTime(2027, 6, 30),
          ),
        ]
      : const [],
);

class _FakeMembershipApi extends MembershipApiClient {
  _FakeMembershipApi(this._answer);

  Future<MembershipOverview> Function() _answer;
  final List<bool> refreshes = [];

  set answer(Future<MembershipOverview> Function() value) => _answer = value;

  @override
  Future<MembershipOverview> fetchOverview({bool refresh = false}) {
    refreshes.add(refresh);
    return _answer();
  }

  @override
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(_FakeMembershipApi api, {String? userId = 'user-1'}) {
    final c = ProviderContainer(
      overrides: [
        membershipApiClientProvider.overrideWithValue(api),
        membershipUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('there is nothing to verify for a signed-out visitor', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api, userId: null);

    expect(await c.read(membershipOverviewProvider.future), isNull);
    expect(api.refreshes, isEmpty);
  });

  test('verifies at launch and keeps the result for this student', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.isMember, isTrue);
    expect(result?.fromCache, isFalse);
    expect(api.refreshes, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MembershipOverviewNotifier.cacheKey('user-1')),
      isNotNull,
    );
  });

  test('shows the last verified result, marked cached, when the check fails', () async {
    final saved = overview(checkedAt: DateTime.now().subtract(const Duration(hours: 3)));
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(saved.toJson()),
    });
    final api = _FakeMembershipApi(() async => throw Exception('offline'));
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.fromCache, isTrue);
    expect(result?.isMember, isTrue);
  });

  test("prefers the cached result over the server's 'cannot verify right now'", () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
        overview().toJson(),
      ),
    });
    final api = _FakeMembershipApi(
      () async => overview(
        state: MembershipGateState.checkUnavailable,
        isMember: false,
      ),
    );
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.fromCache, isTrue);
    expect(result?.isMember, isTrue);
  });

  test("shows 'cannot verify right now' when nothing is cached", () async {
    final api = _FakeMembershipApi(
      () async => overview(
        state: MembershipGateState.checkUnavailable,
        isMember: false,
      ),
    );
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.state, MembershipGateState.checkUnavailable);
    expect(result?.fromCache, isFalse);
  });

  test('a refresh asks the server to re-check', () async {
    final api = _FakeMembershipApi(() async => overview(isMember: false));
    final c = container(api);
    await c.read(membershipOverviewProvider.future);
    api.answer = () async => overview();

    await c.read(membershipOverviewProvider.notifier).refresh();

    expect(api.refreshes, [false, true]);
    expect(c.read(membershipOverviewProvider).valueOrNull?.isMember, isTrue);
  });

  test('member-only products trust a cached membership for a day only', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
        overview(checkedAt: DateTime.now().subtract(const Duration(hours: 30)))
            .toJson(),
      ),
    });
    final api = _FakeMembershipApi(() async => throw Exception('offline'));
    final c = container(api);

    await c.read(membershipOverviewProvider.future);

    expect(c.read(hasValidMembershipProvider), isFalse);
  });

  test('a freshly verified membership counts', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);

    await c.read(membershipOverviewProvider.future);

    expect(c.read(hasValidMembershipProvider), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/membership/membership_overview_provider_test.dart`
Expected: FAIL — `membership_overview_provider.dart` does not exist.

- [ ] **Step 3: Implement the provider**

Create `lib/providers/membership/membership_overview_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/membership_overview.dart';
import '../../data/services/membership_api_client.dart';
import '../auth/auth_provider.dart';

final membershipApiClientProvider = Provider<MembershipApiClient>(
  (ref) => MembershipApiClient(),
);

/// Whose membership to show: the signed-in account once the session has
/// resolved, or null. Separate so tests can pin a student.
final membershipUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authStateProvider.select(
      (state) => state.isLoading ? null : state.signedInUserId,
    ),
  );
});

/// How old a verification may get before returning to the app re-checks it.
const membershipRecheckAfter = Duration(minutes: 10);

/// How long a cached "member" still counts for member-only products when a
/// fresh check cannot be made.
const membershipCacheTrust = Duration(hours: 24);

/// The signed-in student's membership, verified against 24SevenOffice by the
/// server.
///
/// Verified when a student is known (so a cold launch checks without any
/// membership screen open), and again when the app returns to the foreground
/// after [membershipRecheckAfter], or immediately after the student went to
/// biso.no to link their BI account. The last verified overview is kept per
/// student so an offline launch can still show it, marked [MembershipOverview.fromCache].
class MembershipOverviewNotifier extends AsyncNotifier<MembershipOverview?> {
  static String cacheKey(String userId) => 'membership_overview_v1_$userId';

  bool _linkStarted = false;

  @override
  Future<MembershipOverview?> build() async {
    final userId = ref.watch(membershipUserIdProvider);

    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_onResume()),
    );
    ref.onDispose(lifecycle.dispose);

    if (userId == null) return null;
    return _load(userId, refresh: false);
  }

  /// Re-checks with the server. [force] asks it to bypass its own cache
  /// (it still re-checks 24SevenOffice at most once a minute).
  Future<void> refresh({bool force = true}) async {
    final userId = ref.read(membershipUserIdProvider);
    if (userId == null) return;
    state = const AsyncLoading<MembershipOverview?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _load(userId, refresh: force));
  }

  /// The student is leaving for biso.no to link their BI account; the next
  /// return to the app re-checks straight away.
  void noteLinkStarted() => _linkStarted = true;

  Future<void> _onResume() async {
    if (_linkStarted) {
      _linkStarted = false;
      await refresh(force: true);
      return;
    }
    if (state.isLoading) return;
    final current = state.valueOrNull;
    final stale =
        current == null ||
        current.fromCache ||
        DateTime.now().difference(current.checkedAt) > membershipRecheckAfter;
    if (stale) {
      await refresh(force: false);
    }
  }

  Future<MembershipOverview?> _load(
    String userId, {
    required bool refresh,
  }) async {
    try {
      final fresh = await ref
          .read(membershipApiClientProvider)
          .fetchOverview(refresh: refresh);
      if (fresh.state == MembershipGateState.checkUnavailable) {
        // The server could not verify right now. The last verified answer is
        // more useful to the student than "unavailable", as long as it is
        // shown as cached.
        return await _readCache(userId) ?? fresh;
      }
      await _writeCache(userId, fresh);
      return fresh;
    } catch (error) {
      logPrint('🎫 Membership check failed: $error');
      final cached = await _readCache(userId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<MembershipOverview?> _readCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey(userId));
      if (raw == null) return null;
      return MembershipOverview.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        fromCache: true,
      );
    } catch (error) {
      logPrint('🎫 Could not read the cached membership: $error');
      return null;
    }
  }

  Future<void> _writeCache(String userId, MembershipOverview overview) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey(userId), jsonEncode(overview.toJson()));
    } catch (error) {
      logPrint('🎫 Could not cache the membership: $error');
    }
  }
}

final membershipOverviewProvider =
    AsyncNotifierProvider<MembershipOverviewNotifier, MembershipOverview?>(
      MembershipOverviewNotifier.new,
    );

/// Whether the student has a valid membership, for presentation such as
/// member-only products. A cached answer counts for [membershipCacheTrust];
/// prices are always decided by the server.
final hasValidMembershipProvider = Provider<bool>((ref) {
  final overview = ref.watch(membershipOverviewProvider).valueOrNull;
  if (overview == null || !overview.isMember) return false;
  if (!overview.fromCache) return true;
  return DateTime.now().difference(overview.checkedAt) <= membershipCacheTrust;
});
```

- [ ] **Step 4: Retire the legacy membership stack**

Delete the legacy files:

```bash
git rm lib/data/services/membership_service.dart lib/data/services/student_service.dart lib/data/services/oauth_service.dart lib/providers/membership/membership_provider.dart lib/presentation/screens/profile/student_id_screen.dart lib/presentation/widgets/membership_purchase_modal.dart lib/presentation/widgets/show_membership_purchase_modal.dart lib/data/models/membership_model.dart lib/data/models/student_id_model.dart
```

In `lib/providers/auth/auth_provider.dart`:
1. Remove the imports of `student_id_model.dart`, `membership_model.dart` and `membership_service.dart`.
2. In `AuthState`, remove the `studentRecord` and `membershipVerification` fields, their constructor and `copyWith` parameters and assignments, and the getters `hasStudentId`, `studentNumber`, `isStudentVerified`, `isStudentMember`, `hasValidMembership`, `membershipDetails`, `membershipStatus` and `needsStudentId`.
3. In `AuthNotifier`, remove the `_membershipService` field; in `_loadCompleteProfile`, delete the block from the comment `// Check if user has student_id in their profile` through its closing `else { … No student ID found in user profile … }` (membership is now verified by `membershipOverviewProvider`, not on every profile load) and remove the `studentRecord:` and `membershipVerification:` arguments from the `state.copyWith` that follows; remove the methods `registerStudentIdViaOAuth`, `checkMembershipStatus`, `removeStudentId` and `launchMembershipPurchase`.
4. Delete the providers `hasStudentIdProvider`, `studentNumberProvider`, `studentRecordProvider`, `isStudentVerifiedProvider`, `isStudentMemberProvider`, `hasValidMembershipProvider` and `membershipStatusProvider`.

`grep -n "studentRecord\|membershipVerification\|_membershipService\|StudentIdModel\|MembershipModel" lib/providers/auth/auth_provider.dart` must print nothing.

In `lib/data/services/auth_service.dart`: remove the `import 'student_service.dart';` and `import 'membership_service.dart';` lines if present, the `_studentService` field, and the methods `registerStudentIdViaOAuth`, `checkMembershipStatus`, `removeStudentId` and `launchMembershipPurchase`.

In `lib/data/services/validator_service.dart`: remove `issuePassToken` and the `PassTokenResult` class (only the deleted Student ID screen used them). Keep `verifyPassToken`.

In `lib/presentation/screens/explore/webshop_product_detail_screen.dart`, `test/presentation/screens/explore/webshop_product_detail_design_test.dart` and `test/presentation/screens/explore/webshop_product_detail_screen_test.dart`, import `hasValidMembershipProvider` from `providers/membership/membership_overview_provider.dart` (relative path in `lib`, `package:biso/providers/membership/membership_overview_provider.dart` in tests), keeping the `auth_provider.dart` import only where something else from it is still used.

In `lib/main.dart`: import `providers/membership/membership_overview_provider.dart` and extend the resolved-session block in `BisoApp.build`:

```dart
    if (!ref.watch(authStateProvider.select((state) => state.isLoading))) {
      ref.watch(checkoutControllerProvider.notifier);
      // Verify the student's membership at launch, whether or not a
      // membership screen is ever opened. Listening (not watching) keeps the
      // overview alive without rebuilding the app on every check.
      ref.listen(membershipOverviewProvider, (_, _) {});
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/providers/membership test/presentation/screens/explore && flutter analyze`
Expected: PASS; `flutter analyze` reports no errors (fix any remaining reference to a deleted symbol by removing the dead code that used it — do not recreate the legacy classes).

Run: `flutter test`
Expected: the whole suite passes.

- [ ] **Step 6: Commit**

```bash
git add -A lib test
git commit -m "Verify membership against the API and retire the old membership code

The app called Appwrite Functions that no longer exist, so every student
showed as a non-member. Membership is now read from GET /api/membership at
launch and when the app returns, cached per student for offline use, and
drives member-only products. The unreachable Student ID screen and its
services are removed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 5: Follow a membership payment home

**Files:**
- Create: `lib/providers/membership/membership_checkout_provider.dart`
- Create: `test/providers/membership/membership_checkout_provider_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `membershipApiClientProvider`, `membershipOverviewProvider`, `membershipUserIdProvider` (Task 4); `shopApiClientProvider` (`lib/providers/shop/cart_provider.dart`), `paymentProvidersProvider` (`lib/providers/shop/checkout_provider.dart`), `ShopOrderStatus` (`lib/data/models/shop_order.dart`), `PaymentProvider`.
- Produces:
  - `enum MembershipPurchasePhase { idle, starting, awaitingPayment, activating, activated, activationDelayed, cancelled, failed }`
  - `class MembershipPurchaseState { MembershipPurchasePhase phase; String? orderId; String? message; }`
  - `typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);` and `final membershipUrlLauncherProvider = Provider<ExternalUrlLauncher>`
  - `final membershipCheckoutControllerProvider = StateNotifierProvider<MembershipCheckoutController, MembershipPurchaseState>` with `start({required PaymentProvider provider, required String planId, required String campusId})`, `resolvePending({String? orderId, bool cancelled = false})`, `dismissOutcome()`
  - SharedPreferences keys `membership_pending_order_id`, `membership_pending_started_at`

- [ ] **Step 1: Write the failing test**

Create `test/providers/membership/membership_checkout_provider_test.dart`:

```dart
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/shop_order.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShopApi extends ShopApiClient {
  _FakeShopApi(this.status);

  ShopOrderStatus status;
  final List<String> fetched = [];

  @override
  Future<ShopOrder> fetchOrder(String orderId) async {
    fetched.add(orderId);
    return ShopOrder(
      id: orderId,
      status: status,
      currency: 'NOK',
      subtotal: 550,
      discountTotal: 0,
      total: 550,
      membershipApplied: false,
      memberDiscountPercent: 0,
      items: const [],
    );
  }
}

class _FakeMembershipApi extends MembershipApiClient {
  bool isMember = false;
  MembershipApiException? refuseWith;
  final List<Map<String, String>> started = [];

  @override
  Future<MembershipOverview> fetchOverview({bool refresh = false}) async {
    return MembershipOverview(
      state: MembershipGateState.eligible,
      isMember: isMember,
      checkedAt: DateTime.now(),
    );
  }

  @override
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    final refusal = refuseWith;
    if (refusal != null) throw refusal;
    started.add({'provider': provider.id, 'planId': planId, 'campusId': campusId});
    return const StartedCheckout(
      checkoutUrl: 'https://vipps.example/checkout',
      orderId: 'order-1',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> launched;
  late bool launchSucceeds;

  ProviderContainer container(_FakeShopApi shop, _FakeMembershipApi membership) {
    final c = ProviderContainer(
      overrides: [
        shopApiClientProvider.overrideWithValue(shop),
        membershipApiClientProvider.overrideWithValue(membership),
        membershipUserIdProvider.overrideWithValue('user-1'),
        membershipUrlLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return launchSucceeds;
        }),
        membershipCheckoutControllerProvider.overrideWith(
          (ref) => MembershipCheckoutController(
            ref,
            activationPollInterval: Duration.zero,
            activationAttempts: 3,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    launched = [];
    launchSucceeds = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('starting a purchase remembers the order and opens the payment provider', () async {
    final membership = _FakeMembershipApi();
    final c = container(_FakeShopApi(ShopOrderStatus.pending), membership);

    await c
        .read(membershipCheckoutControllerProvider.notifier)
        .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

    expect(membership.started.single, {
      'provider': 'vipps',
      'planId': '71',
      'campusId': '2',
    });
    expect(launched.single.toString(), 'https://vipps.example/checkout');
    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.awaitingPayment,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), 'order-1');
  });

  test("a refused purchase shows the server's reason and remembers nothing", () async {
    final membership = _FakeMembershipApi()
      ..refuseWith = const MembershipApiException(
        'Your membership already covers this period.',
        statusCode: 409,
      );
    final c = container(_FakeShopApi(ShopOrderStatus.pending), membership);

    await c
        .read(membershipCheckoutControllerProvider.notifier)
        .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

    final state = c.read(membershipCheckoutControllerProvider);
    expect(state.phase, MembershipPurchasePhase.failed);
    expect(state.message, 'Your membership already covers this period.');
    expect(launched, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a payment completed while the app was closed is picked up at launch and activated', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
    });
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi()..isMember = true;
    final c = container(shop, membership);

    c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();

    expect(shop.fetched, ['order-1']);
    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.activated,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a paid order whose membership has not shown up yet says it is on its way', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
    });
    final c = container(_FakeShopApi(ShopOrderStatus.paid), _FakeMembershipApi());

    c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();

    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.activationDelayed,
    );
  });

  test('a stale marker is dropped without asking the server', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
    });
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final c = container(shop, _FakeMembershipApi());

    c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();

    expect(shop.fetched, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a cancelled return ends the attempt', () async {
    final c = container(_FakeShopApi(ShopOrderStatus.pending), _FakeMembershipApi());
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await controller.start(
      provider: PaymentProvider.stripe,
      planId: '71',
      campusId: '1',
    );

    await controller.resolvePending(orderId: 'order-1', cancelled: true);

    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.cancelled,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('an unopened payment provider is reported, and the order stays resumable', () async {
    launchSucceeds = false;
    final c = container(_FakeShopApi(ShopOrderStatus.pending), _FakeMembershipApi());

    await c
        .read(membershipCheckoutControllerProvider.notifier)
        .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

    final state = c.read(membershipCheckoutControllerProvider);
    expect(state.phase, MembershipPurchasePhase.failed);
    expect(state.message, 'We could not open your payment provider.');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), 'order-1');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/membership/membership_checkout_provider_test.dart`
Expected: FAIL — `membership_checkout_provider.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/providers/membership/membership_checkout_provider.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/payment_provider.dart';
import '../../data/models/shop_order.dart';
import '../../data/services/membership_api_client.dart';
import '../shop/cart_provider.dart';
import '../shop/checkout_provider.dart';
import 'membership_overview_provider.dart';

enum MembershipPurchasePhase {
  idle,
  starting,
  awaitingPayment,
  activating,
  activated,
  activationDelayed,
  cancelled,
  failed,
}

class MembershipPurchaseState extends Equatable {
  final MembershipPurchasePhase phase;
  final String? orderId;
  final String? message;

  const MembershipPurchaseState({
    this.phase = MembershipPurchasePhase.idle,
    this.orderId,
    this.message,
  });

  @override
  List<Object?> get props => [phase, orderId, message];
}

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Opens a payment page outside the app: Vipps needs to hand off to its own
/// app, and a card form belongs in a real browser with the buyer's autofill.
final membershipUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Drives a membership purchase and follows the payment home.
///
/// The student pays outside the app and the app may be evicted meanwhile, so
/// the order is remembered on disk and resolved on construction (a cold
/// launch), on every return to the foreground, and when the return deep link
/// arrives. The order is read through `GET /api/payment/orders/:id`, which
/// reconciles with the provider and runs fulfilment (24SevenOffice customer,
/// category and invoice) before answering, so a "paid" here is real.
class MembershipCheckoutController
    extends StateNotifier<MembershipPurchaseState> {
  MembershipCheckoutController(
    this._ref, {
    Duration activationPollInterval = const Duration(seconds: 10),
    int activationAttempts = 10,
  }) : _activationPollInterval = activationPollInterval,
       _activationAttempts = activationAttempts,
       super(const MembershipPurchaseState()) {
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(resolvePending()),
    );
    unawaited(_restorePending());
  }

  final Ref _ref;
  final Duration _activationPollInterval;

  /// Polls long enough (about 100 s by default) to outlast the server's
  /// once-a-minute refresh floor on the membership check.
  final int _activationAttempts;
  late final AppLifecycleListener _lifecycle;

  static const String _pendingOrderKey = 'membership_pending_order_id';
  static const String _pendingStartedKey = 'membership_pending_started_at';
  static const Duration _pendingMaxAge = Duration(hours: 2);

  String? _pendingOrderId;
  bool _resolving = false;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> start({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    state = const MembershipPurchaseState(
      phase: MembershipPurchasePhase.starting,
    );
    try {
      final started = await _ref
          .read(membershipApiClientProvider)
          .startCheckout(provider: provider, planId: planId, campusId: campusId);
      await _rememberPending(started.orderId);

      final opened = await _ref.read(membershipUrlLauncherProvider)(
        Uri.parse(started.checkoutUrl),
      );
      if (!mounted) return;
      if (!opened) {
        // The order stays payable: starting again reuses the same session
        // within the server's idempotency window.
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: started.orderId,
          message: 'We could not open your payment provider.',
        );
        return;
      }
      state = MembershipPurchaseState(
        phase: MembershipPurchasePhase.awaitingPayment,
        orderId: started.orderId,
      );
    } on MembershipApiException catch (error) {
      if (!mounted) return;
      state = MembershipPurchaseState(
        phase: MembershipPurchasePhase.failed,
        message: error.message,
      );
      if (error.isAlreadyCovered || error.isUnavailable) {
        unawaited(_ref.read(membershipOverviewProvider.notifier).refresh());
      }
      if (error.isProviderDisabled) {
        _ref.invalidate(paymentProvidersProvider);
      }
    } catch (error) {
      logPrint('🎫 Membership checkout failed to start: $error');
      if (!mounted) return;
      state = const MembershipPurchaseState(
        phase: MembershipPurchasePhase.failed,
        message: 'We could not start the payment. Please try again.',
      );
    }
  }

  /// Checks on the payment the student left to make.
  ///
  /// [orderId] and [cancelled] come from the return deep link; without them
  /// the remembered order is checked. Silent on network failure, so the
  /// marker stays for the next attempt.
  Future<void> resolvePending({String? orderId, bool cancelled = false}) async {
    final id = orderId ?? _pendingOrderId;
    if (id == null || _resolving) return;
    _resolving = true;
    try {
      final order = await _ref.read(shopApiClientProvider).fetchOrder(id);
      if (!mounted) return;

      if (order.status.isSuccessful) {
        await _clearPending();
        await _activate(id);
      } else if (order.status == ShopOrderStatus.failed) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: id,
          message: 'The payment did not go through. You have not been charged.',
        );
      } else if (order.status == ShopOrderStatus.refunded) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: id,
          message: 'This payment was refunded.',
        );
      } else if (order.status == ShopOrderStatus.cancelled || cancelled) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.cancelled,
          orderId: id,
        );
      } else {
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.awaitingPayment,
          orderId: id,
        );
      }
    } catch (error) {
      logPrint('🎫 Could not resolve the membership payment: $error');
    } finally {
      _resolving = false;
    }
  }

  /// Returns the screen to its normal state after an outcome was shown.
  void dismissOutcome() => state = const MembershipPurchaseState();

  /// Payment is in; fulfilment has run server-side. Re-verify until the new
  /// membership shows, which proves it reached 24SevenOffice.
  Future<void> _activate(String orderId) async {
    state = MembershipPurchaseState(
      phase: MembershipPurchasePhase.activating,
      orderId: orderId,
    );
    final overview = _ref.read(membershipOverviewProvider.notifier);
    for (var attempt = 0; attempt < _activationAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_activationPollInterval);
      }
      if (!mounted) return;
      await overview.refresh();
      if (_ref.read(membershipOverviewProvider).valueOrNull?.isMember == true) {
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.activated,
          orderId: orderId,
        );
        return;
      }
    }
    if (!mounted) return;
    state = MembershipPurchaseState(
      phase: MembershipPurchasePhase.activationDelayed,
      orderId: orderId,
      message:
          'Your payment is confirmed. Your membership can take a few minutes '
          'to show up here.',
    );
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderId = prefs.getString(_pendingOrderKey);
      final startedAt = prefs.getInt(_pendingStartedKey);
      if (orderId == null || orderId.isEmpty || startedAt == null) return;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(startedAt),
      );
      if (age > _pendingMaxAge) {
        await _clearPending();
        return;
      }
      _pendingOrderId = orderId;
      // A cold launch is not a resume, so resolve now rather than waiting for
      // the next time the app comes back to the foreground.
      await resolvePending();
    } catch (error) {
      logPrint('🎫 Failed to restore the membership payment: $error');
    }
  }

  Future<void> _rememberPending(String orderId) async {
    _pendingOrderId = orderId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingOrderKey, orderId);
      await prefs.setInt(
        _pendingStartedKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      logPrint('🎫 Failed to remember the membership payment: $error');
    }
  }

  /// Drops the marker, in memory first (synchronously) so a second resolution
  /// racing this one finds nothing to act on.
  Future<void> _clearPending() async {
    _pendingOrderId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingOrderKey);
      await prefs.remove(_pendingStartedKey);
    } catch (error) {
      logPrint('🎫 Failed to clear the membership payment: $error');
    }
  }
}

final membershipCheckoutControllerProvider =
    StateNotifierProvider<MembershipCheckoutController, MembershipPurchaseState>(
      MembershipCheckoutController.new,
    );
```

In `lib/main.dart`, import `providers/membership/membership_checkout_provider.dart` and add inside the resolved-session block in `BisoApp.build` (after the membership `ref.listen` from Task 4):

```dart
      // Like the shop's checkout controller: built at launch so a membership
      // paid while the app was evicted is resolved without visiting a screen.
      ref.watch(membershipCheckoutControllerProvider.notifier);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/providers/membership && flutter analyze lib/providers lib/main.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/membership/membership_checkout_provider.dart test/providers/membership/membership_checkout_provider_test.dart lib/main.dart
git commit -m "Follow a membership payment until the membership is active

The student pays outside the app, so the order is remembered and resolved at
launch, on return and from the return link. A paid order re-checks the
membership until 24SevenOffice shows it, and says so if it is slow.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 6: Membership screen, route, Profile row and deep links

**Files:**
- Create: `lib/presentation/screens/profile/membership_screen.dart`
- Create: `test/presentation/screens/profile/membership_screen_test.dart`
- Create: `test/data/services/deep_link_membership_route_test.dart`
- Modify: `lib/main.dart`
- Modify: `lib/data/services/deep_link_service.dart`
- Modify: `lib/presentation/screens/profile/profile_screen.dart`
- Modify: `test/presentation/screens/profile/profile_design_test.dart` (+ any other test that pumps `ProfileScreen`)
- Modify: `test/presentation/design_rules_test.dart`

**Interfaces:**
- Consumes: `membershipOverviewProvider`, `MembershipOverviewNotifier` (Task 4); `membershipCheckoutControllerProvider`, `MembershipCheckoutController`, `MembershipPurchasePhase`, `membershipUrlLauncherProvider` (Task 5); `availablePaymentProvidersProvider`, `paymentProvidersProvider` (`lib/providers/shop/checkout_provider.dart`); `formatNok` (`lib/core/utils/currency.dart`).
- Produces: `class MembershipScreen extends ConsumerStatefulWidget { const MembershipScreen({String? returnedOrderId, bool returnedCancelled = false, bool linked = false}) }`; route `/profile/membership` (name `membership`) reading query `orderId`, `cancelled=1`, `linked=1`; `String membershipRouteFor(Map<String, String> query)` in `deep_link_service.dart`; `final membershipLinkUrl = Uri.parse('https://biso.no/membership/link')`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/services/deep_link_membership_route_test.dart`:

```dart
import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a paid return opens the membership screen on that order', () {
    expect(
      membershipRouteFor({'orderId': 'order-1', 'status': 'paid'}),
      '/profile/membership?orderId=order-1',
    );
  });

  test('a cancelled return carries the cancellation', () {
    expect(
      membershipRouteFor({'orderId': 'order-1', 'cancelled': '1'}),
      '/profile/membership?orderId=order-1&cancelled=1',
    );
  });

  test('a finished BI link asks the screen to re-check', () {
    expect(
      membershipRouteFor({'linked': '1'}),
      '/profile/membership?linked=1',
    );
  });

  test('a bare link just opens the screen', () {
    expect(membershipRouteFor(const {}), '/profile/membership');
  });
}
```

Create `test/presentation/screens/profile/membership_screen_test.dart`:

```dart
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/membership_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(id: 'u1', name: 'Ola Nordmann', email: 'ola@example.com');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedOverview extends MembershipOverviewNotifier {
  _FixedOverview(this.value);

  final MembershipOverview? value;
  int refreshes = 0;
  bool linkNoted = false;

  @override
  Future<MembershipOverview?> build() async => value;

  @override
  Future<void> refresh({bool force = true}) async => refreshes++;

  @override
  void noteLinkStarted() => linkNoted = true;
}

class _RecordingCheckout extends MembershipCheckoutController {
  _RecordingCheckout(super.ref);

  final List<String> started = [];

  @override
  Future<void> start({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    started.add('${provider.id}:$planId:$campusId');
  }
}

final _plan = MembershipPlanOption(
  id: '71',
  name: 'BISO Membership fall 2026 and spring 2027',
  price: 550,
  duration: 'year',
  accrualMonths: 12,
  expiryDate: DateTime(2027, 6, 30),
);

MembershipOverview _overview({
  required MembershipGateState state,
  bool isMember = false,
  List<MembershipPlanOption> plans = const [],
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  studentId: state == MembershipGateState.needsBiLink ? null : 's1715738',
  checkedAt: DateTime.now(),
  memberships: isMember
      ? [
          MembershipPeriod(
            id: '71',
            name: 'BISO Membership fall 2026 and spring 2027',
            expiryDate: DateTime(2027, 6, 30),
          ),
        ]
      : const [],
  offeredPlans: plans,
  defaultCampusId: '2',
  campuses: const [
    MembershipCampus(id: '1', name: 'Oslo'),
    MembershipCampus(id: '2', name: 'Bergen'),
  ],
);

void main() {
  late _FixedOverview overview;
  late _RecordingCheckout checkout;
  late List<Uri> launched;

  List<Override> overrides(MembershipOverview? value) {
    overview = _FixedOverview(value);
    return [
      authStateProvider.overrideWith((_) => _Auth()),
      membershipOverviewProvider.overrideWith(() => overview),
      membershipCheckoutControllerProvider.overrideWith(
        (ref) => checkout = _RecordingCheckout(ref),
      ),
      membershipUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
      availablePaymentProvidersProvider.overrideWithValue(
        const AsyncData([PaymentProvider.vipps, PaymentProvider.stripe]),
      ),
    ];
  }

  setUp(() {
    launched = [];
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.eligible, plans: [_plan]),
      ),
    );
  });

  testWidgets('an unlinked student is sent to biso.no to link', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Link your BI student account'), findsOneWidget);
    await tester.tap(find.text('Link on biso.no'));
    await tester.pumpAndSettle();

    expect(launched.single.toString(), 'https://biso.no/membership/link');
    expect(overview.linkNoted, isTrue);
  });

  testWidgets('a member sees their membership and its expiry', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.alreadyMember, isMember: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active member'), findsOneWidget);
    expect(find.text('BISO Membership fall 2026 and spring 2027'), findsOneWidget);
    expect(find.text('Valid until'), findsOneWidget);
    expect(find.text('Pay NOK 550 with Vipps'), findsNothing);
  });

  testWidgets('an eligible student picks a plan and pays with an enabled provider', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.eligible, plans: [_plan]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bergen'), findsOneWidget);
    final pay = find.text('Pay NOK 550 with Vipps');
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();

    expect(checkout.started, ['vipps:71:2']);
  });

  testWidgets('an unverifiable check offers a retry', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.checkUnavailable),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(overview.refreshes, 1);
  });

  testWidgets('returning from biso.no re-checks straight away', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(linked: true),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(overview.refreshes, 1);
  });
}
```

(If `expectBuildsCleanly` or `pumpBisoScreen` need `routed: true` because the screen reads router state, pass it; the assertions stay as written.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/services/deep_link_membership_route_test.dart test/presentation/screens/profile/membership_screen_test.dart`
Expected: FAIL — `membershipRouteFor` and `membership_screen.dart` do not exist.

- [ ] **Step 3: Implement the screen**

Create `lib/presentation/screens/profile/membership_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/membership_overview.dart';
import '../../../data/models/payment_provider.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';

/// Where a student links their BI account. BI's tenant is reachable only
/// through Appwrite's OIDC provider, in a browser holding the student's own
/// biso.no session, so the app hands this step to the website.
final membershipLinkUrl = Uri.parse('https://biso.no/membership/link');

String _formatDate(DateTime? date) =>
    date == null ? '' : DateFormat.yMMMd().format(date);

/// The student's BISO membership: verified status, BI linking, and purchase.
///
/// Status comes from `GET /api/membership`, which reads 24SevenOffice. Buying
/// goes through the trusted membership checkout; the payment is followed home
/// by [MembershipCheckoutController].
class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({
    super.key,
    this.returnedOrderId,
    this.returnedCancelled = false,
    this.linked = false,
  });

  /// Set when the payment provider sent the student back here.
  final String? returnedOrderId;
  final bool returnedCancelled;

  /// Set when biso.no sent the student back after linking.
  final bool linked;

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  String? _planId;
  String? _campusId;
  PaymentProvider? _provider;

  @override
  void initState() {
    super.initState();
    _handleArrival();
  }

  @override
  void didUpdateWidget(covariant MembershipScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.returnedOrderId != widget.returnedOrderId ||
        oldWidget.returnedCancelled != widget.returnedCancelled ||
        oldWidget.linked != widget.linked) {
      _handleArrival();
    }
  }

  /// Acts on a return link: verify the payment it names, or re-check the
  /// membership after a BI link.
  void _handleArrival() {
    final orderId = widget.returnedOrderId;
    final cancelled = widget.returnedCancelled;
    final linked = widget.linked;
    if (orderId == null && !linked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (orderId != null) {
        ref
            .read(membershipCheckoutControllerProvider.notifier)
            .resolvePending(orderId: orderId, cancelled: cancelled);
      } else {
        ref.read(membershipOverviewProvider.notifier).refresh();
      }
    });
  }

  Future<void> _openLinkPage() async {
    ref.read(membershipOverviewProvider.notifier).noteLinkStarted();
    final opened = await ref.read(membershipUrlLauncherProvider)(
      membershipLinkUrl,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not open biso.no. Please try again.'),
        ),
      );
    }
  }

  Future<void> _refresh() =>
      ref.read(membershipOverviewProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final leading = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
    );
    final isAuthenticated = ref.watch(
      authStateProvider.select((state) => state.isAuthenticated),
    );

    if (!isAuthenticated) {
      return BisoPage(
        title: 'Membership',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.gold,
              title: 'Sign in to see your membership',
              message: 'Your BISO membership is tied to your BISO account.',
              action: FilledButton(
                onPressed: () => context.go('/auth/login'),
                child: const Text('Sign in'),
              ),
            ),
          ),
        ],
      );
    }

    final overviewAsync = ref.watch(membershipOverviewProvider);
    final overview = overviewAsync.valueOrNull;
    final purchase = ref.watch(membershipCheckoutControllerProvider);

    if (overview == null) {
      return BisoPage(
        title: 'Membership',
        leading: leading,
        onRefresh: _refresh,
        slivers: [
          if (overviewAsync.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: BisoEmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'We could not check your membership',
                message: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: BisoSkeleton.card()),
        ],
      );
    }

    final email = ref.watch(
      authStateProvider.select((state) => state.user?.email ?? ''),
    );
    final controller = ref.read(membershipCheckoutControllerProvider.notifier);

    return BisoPage(
      title: 'Membership',
      leading: leading,
      onRefresh: _refresh,
      slivers: [
        if (purchase.phase != MembershipPurchasePhase.idle)
          SliverToBoxAdapter(
            child: _PurchaseBanner(
              state: purchase,
              onCheckAgain: () => controller.resolvePending(),
              onDismiss: controller.dismissOutcome,
            ),
          ),
        SliverToBoxAdapter(
          child: overview.isMember
              ? _MembershipCard(overview: overview)
              : _NotMemberCard(
                  overview: overview,
                  email: email,
                  onLink: _openLinkPage,
                  onRetry: _refresh,
                ),
        ),
        if (overview.canPurchase) ..._purchaseSlivers(overview, purchase),
      ],
    );
  }

  List<Widget> _purchaseSlivers(
    MembershipOverview overview,
    MembershipPurchaseState purchase,
  ) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final plans = overview.offeredPlans;
    final plan =
        plans.where((option) => option.id == _planId).firstOrNull ??
        plans.firstOrNull;
    final campusId =
        _campusId ??
        overview.defaultCampusId ??
        overview.campuses.firstOrNull?.id;
    final providers = ref.watch(availablePaymentProvidersProvider);
    final available = providers.valueOrNull ?? const <PaymentProvider>[];
    final provider = available.contains(_provider)
        ? _provider
        : available.firstOrNull;
    final busy = const {
      MembershipPurchasePhase.starting,
      MembershipPurchasePhase.awaitingPayment,
      MembershipPurchasePhase.activating,
    }.contains(purchase.phase);

    final selectedPlan = plan;
    final selectedCampus = campusId;
    final selectedProvider = provider;
    VoidCallback? onPay;
    if (selectedPlan != null &&
        selectedCampus != null &&
        selectedProvider != null &&
        !busy) {
      onPay = () => ref
          .read(membershipCheckoutControllerProvider.notifier)
          .start(
            provider: selectedProvider,
            planId: selectedPlan.id,
            campusId: selectedCampus,
          );
    }

    return [
      SliverToBoxAdapter(
        child: RadioGroup<String>(
          groupValue: plan?.id,
          onChanged: (id) {
            if (id != null) setState(() => _planId = id);
          },
          child: BisoFormGroup(
            title: overview.isMember
                ? 'Extend your membership'
                : 'Choose a membership',
            children: [
              for (final option in plans)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.star,
                    accent: BisoAccent.gold,
                  ),
                  title: option.name,
                  subtitle:
                      '${formatNok(option.price)} · valid until '
                      '${_formatDate(option.expiryDate)}',
                  trailing: Radio<String>.adaptive(value: option.id),
                  onTap: () => setState(() => _planId = option.id),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: RadioGroup<String>(
          groupValue: campusId,
          onChanged: (id) {
            if (id != null) setState(() => _campusId = id);
          },
          child: BisoFormGroup(
            title: 'Your campus',
            footer: 'Your membership is booked to this campus.',
            children: [
              for (final campus in overview.campuses)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.location_solid,
                  ),
                  title: campus.name,
                  trailing: Radio<String>.adaptive(value: campus.id),
                  onTap: () => setState(() => _campusId = campus.id),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: RadioGroup<PaymentProvider>(
          groupValue: provider,
          onChanged: (value) {
            if (value != null) setState(() => _provider = value);
          },
          child: BisoFormGroup(
            title: 'How would you like to pay?',
            children: providers.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, _) => [
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.arrow_clockwise,
                  ),
                  title: 'We could not reach the payment service',
                  subtitle: 'Tap to try again.',
                  onTap: () => ref.invalidate(paymentProvidersProvider),
                ),
              ],
              data: (options) => options.isEmpty
                  ? const [
                      BisoListRow(
                        leading: BisoIconTile(icon: CupertinoIcons.pause),
                        title: 'Payments are temporarily unavailable',
                        subtitle: 'Please try again later.',
                      ),
                    ]
                  : [
                      for (final option in options)
                        BisoListRow(
                          leading: BisoIconTile(
                            icon: option == PaymentProvider.vipps
                                ? CupertinoIcons.device_phone_portrait
                                : CupertinoIcons.creditcard,
                            accent: BisoAccent.coral,
                          ),
                          title: option.displayName,
                          subtitle: option.description,
                          trailing: Radio<PaymentProvider>.adaptive(
                            value: option,
                          ),
                          onTap: () => setState(() => _provider = option),
                        ),
                    ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPay,
              icon: const Icon(CupertinoIcons.lock),
              label: Text(
                selectedPlan == null || selectedProvider == null
                    ? 'Payments unavailable'
                    : 'Pay ${formatNok(selectedPlan.price)} with '
                          '${selectedProvider.displayName}',
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Text(
            'You will be taken to your payment provider to pay, then brought '
            'back here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
      ),
    ];
  }
}

/// A compact titled card with an icon, a message and an optional action.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    this.message,
    this.accent = BisoAccent.neutral,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final BisoAccent accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final body = message;
    final button = action;
    return BisoSection(
      child: BisoListGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BisoIconTile(icon: icon, accent: accent),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: text.titleMedium?.copyWith(color: palette.ink),
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: text.bodyMedium?.copyWith(color: palette.muted),
                  ),
                ],
                if (button != null) ...[const SizedBox(height: 16), button],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.overview});

  final MembershipOverview overview;

  @override
  Widget build(BuildContext context) {
    final membership = overview.currentMembership;
    final expiry = membership?.expiryDate ?? overview.currentExpiry;
    final checked = DateFormat.yMMMd().add_Hm().format(
      overview.checkedAt.toLocal(),
    );
    return BisoSection(
      title: 'Your membership',
      footer: overview.fromCache
          ? 'Last verified $checked. We could not check again just now.'
          : 'Verified with BISO $checked.',
      child: BisoListGroup(
        children: [
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.checkmark_seal_fill,
              accent: BisoAccent.teal,
            ),
            title: 'Active member',
            subtitle: membership?.name,
          ),
          if (expiry != null)
            BisoListRow(
              leading: const BisoIconTile(icon: CupertinoIcons.calendar),
              title: 'Valid until',
              value: _formatDate(expiry),
            ),
          if (overview.studentId != null)
            BisoListRow(
              leading: const BisoIconTile(
                icon: CupertinoIcons.person_crop_rectangle,
              ),
              title: 'Student ID',
              value: overview.studentId,
            ),
        ],
      ),
    );
  }
}

class _NotMemberCard extends StatelessWidget {
  const _NotMemberCard({
    required this.overview,
    required this.email,
    required this.onLink,
    required this.onRetry,
  });

  final MembershipOverview overview;
  final String email;
  final VoidCallback onLink;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final expired = overview.lastExpiredMembership;
    final expiredNote = expired == null
        ? null
        : 'Your membership expired on ${_formatDate(expired.expiryDate)}.';

    return switch (overview.state) {
      MembershipGateState.needsBiLink => _InfoCard(
        icon: CupertinoIcons.link,
        accent: BisoAccent.blue,
        title: 'Link your BI student account',
        message:
            'BISO verifies memberships against your BI student record. You '
            'link your BI account once, on biso.no'
            '${email.isEmpty ? '' : ' — sign in there as $email'}.',
        action: FilledButton(
          onPressed: onLink,
          child: const Text('Link on biso.no'),
        ),
      ),
      MembershipGateState.needsDirectoryRecord => _InfoCard(
        icon: CupertinoIcons.person_crop_circle_badge_exclam,
        accent: BisoAccent.coral,
        title: "We couldn't find your BI record",
        message:
            'Your BI account is linked, but we could not read the student '
            'record BISO needs. Try again on biso.no, or contact BISO if it '
            'keeps failing.',
        action: FilledButton(
          onPressed: onLink,
          child: const Text('Try again on biso.no'),
        ),
      ),
      MembershipGateState.checkUnavailable => _InfoCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: "We couldn't verify your membership right now",
        message: 'Pull down to refresh, or try again in a moment.',
        action: FilledButton(
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ),
      MembershipGateState.noPlansAvailable => _InfoCard(
        icon: CupertinoIcons.star,
        accent: BisoAccent.gold,
        title: "You're not a member",
        message: [
          if (expiredNote != null) expiredNote,
          'No memberships are on sale in the app right now. You can still '
              'join through the BI student app.',
        ].join(' '),
      ),
      MembershipGateState.alreadyMember ||
      MembershipGateState.eligible => _InfoCard(
        icon: CupertinoIcons.star,
        accent: BisoAccent.gold,
        title: expired == null ? 'Become a member' : 'Renew your membership',
        message: expiredNote ?? 'Join BISO for member prices and benefits.',
      ),
    };
  }
}

class _PurchaseBanner extends StatelessWidget {
  const _PurchaseBanner({
    required this.state,
    required this.onCheckAgain,
    required this.onDismiss,
  });

  final MembershipPurchaseState state;
  final VoidCallback onCheckAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ok = TextButton(onPressed: onDismiss, child: const Text('OK'));
    return switch (state.phase) {
      MembershipPurchasePhase.idle => const SizedBox.shrink(),
      MembershipPurchasePhase.starting => const _InfoCard(
        icon: CupertinoIcons.hourglass,
        title: 'Starting payment…',
      ),
      MembershipPurchasePhase.awaitingPayment => _InfoCard(
        icon: CupertinoIcons.clock,
        accent: BisoAccent.gold,
        title: 'Waiting for your payment',
        message: 'Finish paying in Vipps or your browser, then come back here.',
        action: TextButton(
          onPressed: onCheckAgain,
          child: const Text('Check again'),
        ),
      ),
      MembershipPurchasePhase.activating => const _InfoCard(
        icon: CupertinoIcons.hourglass,
        accent: BisoAccent.teal,
        title: 'Payment received — activating your membership',
      ),
      MembershipPurchasePhase.activated => _InfoCard(
        icon: CupertinoIcons.checkmark_seal_fill,
        accent: BisoAccent.teal,
        title: 'Welcome to BISO!',
        message: 'Your membership is active.',
        action: TextButton(onPressed: onDismiss, child: const Text('Done')),
      ),
      MembershipPurchasePhase.activationDelayed => _InfoCard(
        icon: CupertinoIcons.clock,
        accent: BisoAccent.gold,
        title: 'Payment confirmed',
        message: state.message,
        action: ok,
      ),
      MembershipPurchasePhase.cancelled => _InfoCard(
        icon: CupertinoIcons.xmark_circle,
        title: 'Payment cancelled',
        message: 'You have not been charged.',
        action: ok,
      ),
      MembershipPurchasePhase.failed => _InfoCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        accent: BisoAccent.coral,
        title: 'The payment was not completed',
        message: state.message,
        action: ok,
      ),
    };
  }
}
```

- [ ] **Step 4: Wire the route, the Profile row and the deep links**

In `lib/main.dart`, import `presentation/screens/profile/membership_screen.dart` and give the `/profile` `GoRoute` a child route, in the same leading-slash style as `productRoutes()`:

```dart
        GoRoute(
          path: '/profile',
          name: 'profile',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _ProfilePage()),
          routes: [
            GoRoute(
              path: '/membership',
              name: 'membership',
              builder: (context, state) {
                final query = state.uri.queryParameters;
                return MembershipScreen(
                  returnedOrderId: query['orderId'],
                  returnedCancelled: query['cancelled'] == '1',
                  linked: query['linked'] == '1',
                );
              },
            ),
          ],
        ),
```

In `lib/data/services/deep_link_service.dart`:
1. Add a top-level function (with `import 'package:flutter/foundation.dart';` if `visibleForTesting` is not yet imported):

```dart
/// The in-app route for a `biso://membership` or `https://biso.no/app/membership`
/// link. A payment return carries `orderId` (and `cancelled=1` when the
/// student abandoned it); a finished BI link from biso.no carries `linked=1`.
/// The status a return link carries is not passed on: the screen verifies the
/// order itself.
@visibleForTesting
String membershipRouteFor(Map<String, String> query) {
  final orderId = query['orderId'] ?? '';
  final params = <String, String>{
    if (orderId.isNotEmpty) 'orderId': orderId,
    if (query['cancelled'] == '1') 'cancelled': '1',
    if (query['linked'] == '1') 'linked': '1',
  };
  return Uri(
    path: '/profile/membership',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}
```

2. In `_handleDeepLink`'s `biso` switch add:

```dart
        case 'membership':
          _go(membershipRouteFor(uri.queryParameters));
          break;
```

3. In `_handleUniversalLink`'s `switch (appSegments.first)` add:

```dart
      case 'membership':
        _go(membershipRouteFor(uri.queryParameters));
        break;
```

In `lib/presentation/screens/profile/profile_screen.dart`: import `package:intl/intl.dart`, `../../../data/models/membership_overview.dart` and `../../../providers/membership/membership_overview_provider.dart`; replace the static `'Student ID'` `BisoListRow` (the one with subtitle "We’re improving Student ID…") with `const _MembershipRow(),` and add at the end of the file:

```dart
class _MembershipRow extends ConsumerWidget {
  const _MembershipRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(membershipOverviewProvider).valueOrNull;
    final expiry = overview?.currentMembership?.expiryDate;
    final subtitle = switch (overview) {
      null => 'Check your BISO membership',
      final o when o.isMember =>
        expiry == null
            ? 'Active member'
            : 'Active until ${DateFormat.yMMMd().format(expiry)}',
      final o when o.state == MembershipGateState.needsBiLink =>
        'Link your BI student account',
      _ => 'Not a member',
    };
    return BisoListRow(
      leading: const BisoIconTile(
        icon: CupertinoIcons.checkmark_seal,
        accent: BisoAccent.gold,
      ),
      title: 'Membership',
      subtitle: subtitle,
      onTap: () => context.push('/profile/membership'),
    );
  }
}
```

Every test that builds `ProfileScreen` — directly or through the app's router/shell — must stop the row from reaching the network. Run `grep -rln "ProfileScreen\|_ProfilePage\|BisoApp" test` and add to each of those tests' overrides lists:

```dart
  membershipOverviewProvider.overrideWith(_NoMembership.new),
```

with, in that test file:

```dart
class _NoMembership extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}
```

(imports: `package:biso/data/models/membership_overview.dart`, `package:biso/providers/membership/membership_overview_provider.dart`).

Add `'lib/presentation/screens/profile/membership_screen.dart',` to `migratedFiles` in `test/presentation/design_rules_test.dart`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/data/services/deep_link_membership_route_test.dart test/presentation/screens/profile test/presentation/design_rules_test.dart && flutter analyze`
Expected: PASS; no analyzer issues.

Run: `flutter test`
Expected: the full suite passes.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/profile/membership_screen.dart lib/main.dart lib/data/services/deep_link_service.dart lib/presentation/screens/profile/profile_screen.dart test
git commit -m "Add the membership screen with BI linking and purchase

Profile now opens a membership screen that shows the verified membership,
sends unlinked students to biso.no to link their BI account, and sells
memberships with only the payment providers BISO has enabled. Payment and
link return deep links land back on it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 7: Remove `flutter_appauth` and document the new flows

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: generated plugin registrants if they are tracked (`git status` shows them)
- Modify: `CLAUDE.md`

**Interfaces:** none (no Dart API changes). After Task 4 nothing imports `package:flutter_appauth`.

- [ ] **Step 1: Confirm nothing uses the package**

Run: `grep -rn "flutter_appauth\|FlutterAppAuth\|AuthorizationTokenRequest" lib test`
Expected: no output. If anything prints, stop — Task 4 left a caller behind; remove that dead code first.

- [ ] **Step 2: Remove the dependency and its native registration**

1. In `pubspec.yaml`, delete the line `  flutter_appauth: ^9.0.1`. Run `flutter pub get`.
2. In `ios/Runner/Info.plist`, delete the second `CFBundleURLTypes` entry — exactly this dict (keep the `biso.deeplink` dict before it):

```xml
		<dict>
			<key>CFBundleURLName</key>
			<string>appauth.redirect</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>com.biso.no</string>
			</array>
		</dict>
```

3. In `android/app/build.gradle.kts`, delete the comment line `// Scheme must match the scheme part of the redirect URI used in the app (e.g. com.biso.no://oauth/callback)` and the line `manifestPlaceholders["appAuthRedirectScheme"] = "com.biso.no"`.
4. In `android/app/src/main/AndroidManifest.xml`, delete the whole block from `<!-- AppAuth redirect handler for OAuth callback -->` through the closing `</activity>` of `net.openid.appauth.RedirectUriReceiverActivity`.

- [ ] **Step 3: Build both platforms**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

Run: `flutter build ios --debug --no-codesign`
Expected: `✓ Built build/ios/iphoneos/Runner.app` (CocoaPods updates `ios/Podfile.lock` to drop AppAuth).

If either build fails because of this task's changes, revert Step 2 (`git checkout -- pubspec.yaml pubspec.lock ios android && flutter pub get`), keep the package, and record "flutter_appauth removal left as follow-up: <build error>" in the final report. If a build cannot run at all on this machine (no Android SDK / Xcode), say so in the report rather than claiming it passed.

- [ ] **Step 4: Document the flows in CLAUDE.md**

In `CLAUDE.md`, under "✅ FULLY IMPLEMENTED FEATURES", add after the "🛒 Webshop Checkout & Payments" section:

```markdown
#### 🎫 Membership (verification, BI link, purchase)
- **Source of truth is 24SevenOffice, read by the server.** `GET /api/membership` returns the
  live status (a 24SO customer category matched to a `memberships` row that has not expired —
  valid through its expiry day in Oslo), the same purchase gate as biso.no's join page, and the
  plans on offer. The app never decides membership itself.
- **Verified at launch and on return.** `membershipOverviewProvider` loads as soon as a signed-in
  user is known (`BisoApp.build` listens to it), re-verifies on resume after 10 minutes, and keeps
  the last verified overview per user for offline display (marked `fromCache`).
  `hasValidMembershipProvider` trusts a cached answer for 24 hours; prices are always server-side.
- **BI linking happens on biso.no.** BI's Azure tenant is reachable only through Appwrite's OIDC
  provider, so the app opens `https://biso.no/membership/link`, and the page returns with
  `biso://membership?linked=1`. Handing the app's session to a browser was rejected: such a link
  is forwardable and could attach someone else's BI identity to the sender's account.
  `student_id` and the `bi_*` columns are server-written only; profile rows are read-only to
  their owner and profile edits go through `PUT /api/profile`.
- **Purchase** uses `POST /api/payment/{provider}/membership-checkout` with `client: "app"`,
  offering only providers `GET /api/payment/providers` reports as available.
  `MembershipCheckoutController` (built in `BisoApp.build`) persists the order, resolves it at
  launch, on resume and from `biso://membership?orderId=…`, then re-checks the membership until
  24SevenOffice shows it.
- **Location**: `lib/providers/membership/`, `lib/data/services/membership_api_client.dart`,
  `lib/presentation/screens/profile/membership_screen.dart`. **Route**: `/profile/membership`.
```

In the "💰 Expense Reimbursement System" section, add the bullet:

```markdown
- **Every write goes through `apps/api`**: receipts upload to `POST /api/expenses/attachments`
  (PDF, PNG or JPEG; photos are re-encoded as JPEG), drafts save and submit through
  `/api/expenses/draft` and `/api/expenses/submit`, and drafts are deleted with
  `DELETE /api/expenses/draft`. Expense rows and the `expenses` bucket give students no write
  access. The screens follow `features.expenses` from `GET /api/config`, which is the admin's
  `expenses_module` switch.
```

- [ ] **Step 5: Run the checks**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A pubspec.yaml pubspec.lock ios android macos CLAUDE.md
git commit -m "Remove flutter_appauth and document membership and expenses

Nothing signs in to Microsoft from the app any more, since BI linking now
happens on biso.no, so the AppAuth plugin and its redirect scheme are gone.
CLAUDE.md describes how membership is verified, linked and bought, and how
reimbursements reach the API.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Full verification

**Files:** none.

- [ ] **Step 1: Run everything**

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

Expected: no analyzer issues; all tests pass (baseline was 721 before this plan — report the new total); formatting clean.

- [ ] **Step 2: Confirm the app no longer writes where it must not**

```bash
grep -rn "tableId: 'user'" lib | grep -E "updateRow|createRow"
grep -rn "bucketId: AppConstants.expensesBucketId" lib
grep -rn "vipps_checkout\|verify_biso_membership\|issue_pass_token\|biso_membership" lib
```

Expected: no output from any of the three (Task 2 removed `ExpenseServiceV2`'s direct-write methods, and Task 4 the legacy membership code).

```bash
grep -n "createRow\|updateRow\|deleteRow\|createFile" lib/data/services/expense_service_v2.dart
```

Expected: no output — the service only reads now.

- [ ] **Step 3: Report**

Report the test totals, the build results from Task 7, and the manual checks that need the deployed platform plan and a device (from the spec's Testing section): a real BI link started from the app on iOS and Android returning through `biso://membership`; a Vipps test-mode membership purchase end to end, including the 24SevenOffice customer (`Id` = student number, `ExternalId` = employee id) and invoice; a receipt upload and a submitted reimbursement with ledger posting on.
