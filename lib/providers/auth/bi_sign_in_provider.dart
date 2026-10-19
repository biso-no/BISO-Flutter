import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/bi_sign_in_service.dart';
import '../../data/services/bi_sync_api_client.dart';
import '../membership/membership_overview_provider.dart';
import 'auth_provider.dart';
import 'bi_sign_in_service_provider.dart';

export 'bi_sign_in_service_provider.dart';

/// How the membership and member-pass "Sign in with BI" action ended.
sealed class BiContinueOutcome {
  const BiContinueOutcome();
}

/// The server answered the BI sync, after a BI sign-in when one was needed.
final class BiContinueSynced extends BiContinueOutcome {
  const BiContinueSynced(this.sync, {this.signedIn = false});

  final BiSyncResult sync;

  /// A BI sign-in replaced the session first, possibly with another account.
  final bool signedIn;
}

/// The BI sign-in itself failed (not the sync after it).
final class BiContinueSignInFailed extends BiContinueOutcome {
  const BiContinueSignInFailed(this.reason);

  final BiSignInFailure reason;
}

/// The student closed the BI sheet.
final class BiContinueCancelled extends BiContinueOutcome {
  const BiContinueCancelled();
}

/// The server saw no session. The auth state has been re-read, so the screen
/// now offers sign-in.
final class BiContinueSignedOut extends BiContinueOutcome {
  const BiContinueSignedOut();
}

/// The membership and member-pass "Sign in with BI" action.
///
/// Syncs first: a student who signed in with BI before the app could sync
/// (it was closed, or offline) is linked without another sign-in. Only a
/// student without a BI identity is sent through the BI sign-in, which
/// replaces their current session once BI answers. A 401 from the sync
/// re-reads the auth state instead. The membership is re-checked either way.
Future<BiContinueOutcome> continueWithBi(WidgetRef ref) async {
  // Read before any await: the screen holding [ref] may be gone by the end.
  final service = ref.read(biSignInServiceProvider);
  final auth = ref.read(authStateProvider.notifier);
  final membership = ref.read(membershipOverviewProvider.notifier);

  final outcome = await _syncOrSignIn(service, auth);
  await membership.refresh();
  return outcome;
}

Future<BiContinueOutcome> _syncOrSignIn(
  BiSignInService service,
  AuthNotifier auth,
) async {
  var sync = await service.syncOnly();
  var signedIn = false;
  if (sync.error == BiSyncError.noBiIdentity) {
    switch (await auth.signInWithBi()) {
      case BiSignInCancelled():
        return const BiContinueCancelled();
      case BiSignInFailed(:final reason):
        return BiContinueSignInFailed(reason);
      case BiSignedIn(sync: final afterSignIn):
        sync = afterSignIn;
        signedIn = true;
    }
  }
  if (sync.error == BiSyncError.notAuthenticated) {
    await auth.refreshAuthState();
    return const BiContinueSignedOut();
  }
  return BiContinueSynced(sync, signedIn: signedIn);
}
