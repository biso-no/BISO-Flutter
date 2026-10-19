import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/auth/bi_sign_in_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers [syncOnly] with [answer] and records it in [log].
class _FakeBiSignIn extends BiSignInService {
  _FakeBiSignIn(this.log, this.answer);

  final List<String> log;
  final BiSyncResult answer;

  @override
  Future<BiSyncResult> syncOnly() async {
    log.add('syncOnly');
    return answer;
  }

  @override
  Future<BiSignInOutcome> signIn({
    Future<void> Function()? beforeSessionSwitch,
  }) => throw StateError('signing in goes through AuthNotifier');
}

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(this.log, this.outcome) : super(const AuthState(isAuthenticated: true));

  final List<String> log;
  final BiSignInOutcome outcome;

  @override
  Future<BiSignInOutcome> signInWithBi() async {
    log.add('signInWithBi');
    return outcome;
  }

  @override
  Future<void> refreshAuthState() async => log.add('refreshAuthState');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Overview extends MembershipOverviewNotifier {
  _Overview(this.log);

  final List<String> log;

  @override
  Future<MembershipOverview?> build() async => null;

  @override
  Future<void> refresh({bool force = true}) async => log.add('refresh');
}

const _synced = BiSyncResult(success: true, studentId: 's1234567');
const _noBiIdentity = BiSyncResult(
  success: false,
  error: BiSyncError.noBiIdentity,
);

void main() {
  late List<String> log;

  Future<BiContinueOutcome> run(
    WidgetTester tester, {
    required BiSyncResult sync,
    BiSignInOutcome signIn = const BiSignedIn(_synced),
  }) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope per run, so each run's overrides apply.
        key: UniqueKey(),
        overrides: [
          biSignInServiceProvider.overrideWithValue(_FakeBiSignIn(log, sync)),
          authStateProvider.overrideWith((_) => _Auth(log, signIn)),
          membershipOverviewProvider.overrideWith(() => _Overview(log)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    return continueWithBi(captured);
  }

  setUp(() => log = []);

  testWidgets(
    'continueWithBi syncs first and only signs in again without a BI identity',
    (tester) async {
      final linked = await run(tester, sync: _synced);

      expect(log, ['syncOnly', 'refresh']);
      expect(
        linked,
        isA<BiContinueSynced>()
            .having((o) => o.sync.studentId, 'studentId', 's1234567')
            .having((o) => o.signedIn, 'signedIn', isFalse),
      );

      log.clear();
      final signedIn = await run(
        tester,
        sync: _noBiIdentity,
        signIn: const BiSignedIn(
          BiSyncResult(success: true, studentId: 's7654321'),
        ),
      );

      expect(log, ['syncOnly', 'signInWithBi', 'refresh']);
      expect(
        signedIn,
        isA<BiContinueSynced>()
            .having((o) => o.sync.studentId, 'studentId', 's7654321')
            .having((o) => o.signedIn, 'signedIn', isTrue),
      );
    },
  );

  testWidgets('a cancelled BI sign-in says so', (tester) async {
    final result = await run(
      tester,
      sync: _noBiIdentity,
      signIn: const BiSignInCancelled(),
    );

    expect(result, isA<BiContinueCancelled>());
    expect(log, ['syncOnly', 'signInWithBi', 'refresh']);
  });

  testWidgets('a failed BI sign-in keeps its reason, apart from sync errors', (
    tester,
  ) async {
    final result = await run(
      tester,
      sync: _noBiIdentity,
      signIn: const BiSignInFailed(BiSignInFailure.existingAccount),
    );

    expect(
      result,
      isA<BiContinueSignInFailed>().having(
        (o) => o.reason,
        'reason',
        BiSignInFailure.existingAccount,
      ),
    );
  });

  testWidgets('another sync error is returned without a sign-in', (
    tester,
  ) async {
    final result = await run(
      tester,
      sync: const BiSyncResult.failed(BiSyncError.alreadyLinked),
    );

    expect(
      result,
      isA<BiContinueSynced>().having(
        (o) => o.sync.error,
        'error',
        BiSyncError.alreadyLinked,
      ),
    );
    expect(log, ['syncOnly', 'refresh']);
  });

  testWidgets('a 401 from the sync re-reads the session instead of showing a '
      'sync error', (tester) async {
    final result = await run(
      tester,
      sync: const BiSyncResult.failed(BiSyncError.notAuthenticated),
    );

    expect(result, isA<BiContinueSignedOut>());
    expect(log, ['syncOnly', 'refreshAuthState', 'refresh']);
  });
}
