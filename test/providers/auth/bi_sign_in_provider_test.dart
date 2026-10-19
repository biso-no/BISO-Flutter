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
  Future<BiSignInOutcome> signIn() =>
      throw StateError('signing in goes through AuthNotifier');
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

  Future<BiSyncResult?> run(
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
      expect(linked?.studentId, 's1234567');

      log.clear();
      final signedIn = await run(
        tester,
        sync: _noBiIdentity,
        signIn: const BiSignedIn(
          BiSyncResult(success: true, studentId: 's7654321'),
        ),
      );

      expect(log, ['syncOnly', 'signInWithBi', 'refresh']);
      expect(signedIn?.studentId, 's7654321');
    },
  );

  testWidgets('a cancelled BI sign-in returns nothing to show', (tester) async {
    final result = await run(
      tester,
      sync: _noBiIdentity,
      signIn: const BiSignInCancelled(),
    );

    expect(result, isNull);
    expect(log, ['syncOnly', 'signInWithBi', 'refresh']);
  });

  testWidgets('a failed BI sign-in reads as a failed sync', (tester) async {
    final result = await run(
      tester,
      sync: _noBiIdentity,
      signIn: const BiSignInFailed(BiSignInFailure.failed),
    );

    expect(result?.error, BiSyncError.syncFailed);
  });

  testWidgets('another sync error is returned without a sign-in', (
    tester,
  ) async {
    final result = await run(
      tester,
      sync: const BiSyncResult(
        success: false,
        error: BiSyncError.alreadyLinked,
      ),
    );

    expect(result?.error, BiSyncError.alreadyLinked);
    expect(log, ['syncOnly', 'refresh']);
  });
}
