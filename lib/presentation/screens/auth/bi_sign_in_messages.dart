import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/bi_sign_in_service.dart';
import '../../../data/services/bi_sync_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/auth/bi_sign_in_provider.dart';

/// What a student reads when the BI sync did not confirm their student
/// number, or null when there is nothing to tell them: it succeeded, or
/// `directory_unavailable`, which saved the student number and leaves the
/// rest to the membership screen's card.
String? biSyncMessage(AppLocalizations l10n, BiSyncResult result) {
  if (result.success) return null;
  return switch (result.error) {
    BiSyncError.directoryUnavailable => null,
    BiSyncError.alreadyLinked => l10n.membershipNeedsBiLinkAlreadyLinked,
    BiSyncError.invalidBiEmail => l10n.membershipNeedsBiLinkInvalidBiEmail,
    _ => l10n.membershipNeedsBiLinkFailed,
  };
}

/// The web login page's copy for a BI sign-in that failed.
String biSignInFailureMessage(AppLocalizations l10n, BiSignInFailure reason) =>
    switch (reason) {
      BiSignInFailure.existingAccount => l10n.biSignInExistingAccount,
      BiSignInFailure.failed => l10n.biSignInFailed,
    };

/// What the membership card or member pass says after "Sign in with BI", or
/// null when there is nothing to say (cancelled, or signed out, which the
/// screen itself then shows).
String? biContinueMessage(AppLocalizations l10n, BiContinueOutcome outcome) =>
    switch (outcome) {
      BiContinueSynced(:final sync) => biSyncMessage(l10n, sync),
      BiContinueSignInFailed(:final reason) => biSignInFailureMessage(
        l10n,
        reason,
      ),
      BiContinueCancelled() || BiContinueSignedOut() => null,
    };

/// After "Sign in with BI" on the membership card or member pass: when the
/// BI sign-in landed in an account that has not been onboarded yet, goes to
/// `/onboarding` as the login screen does, and returns true.
bool goToOnboardingAfterBi(
  BuildContext context,
  WidgetRef ref,
  BiContinueOutcome outcome,
) {
  final switched = outcome is BiContinueSynced && outcome.signedIn;
  if (!switched || !ref.read(authStateProvider).needsOnboarding) return false;
  context.go('/onboarding');
  return true;
}
