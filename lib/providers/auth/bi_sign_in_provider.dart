import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/bi_sign_in_service.dart';
import '../../data/services/bi_sync_api_client.dart';
import '../membership/membership_overview_provider.dart';
import 'auth_provider.dart';

final biSignInServiceProvider = Provider<BiSignInService>(
  (ref) => BiSignInService(),
);

/// The membership and member-pass "Sign in with BI" action.
///
/// Syncs first: a student who signed in with BI before the app could sync
/// (it was closed, or offline) is linked without another sign-in. Only a
/// student without a BI identity is sent through the BI sign-in, which ends
/// their current session. The membership is re-checked either way.
///
/// Returns null when the student cancelled the BI sign-in; a failed sign-in
/// reads as [BiSyncError.syncFailed].
Future<BiSyncResult?> continueWithBi(WidgetRef ref) async {
  // Read before any await: the screen holding [ref] may be gone by the end.
  final service = ref.read(biSignInServiceProvider);
  final auth = ref.read(authStateProvider.notifier);
  final membership = ref.read(membershipOverviewProvider.notifier);

  BiSyncResult? result = await service.syncOnly();
  if (result.error == BiSyncError.noBiIdentity) {
    result = switch (await auth.signInWithBi()) {
      BiSignedIn(:final sync) => sync,
      BiSignInCancelled() => null,
      BiSignInFailed() => const BiSyncResult.failed(BiSyncError.syncFailed),
    };
  }
  await membership.refresh();
  return result;
}
