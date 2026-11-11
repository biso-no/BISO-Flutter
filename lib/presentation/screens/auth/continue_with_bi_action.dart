import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/bi_sign_in_provider.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import 'bi_sign_in_messages.dart';

/// Confirms the student number with BI (signing in with BI when the account
/// has none), then reloads the pass. Callers keep their own busy state.
Future<void> runContinueWithBi(BuildContext context, WidgetRef ref) async {
  final outcome = await continueWithBi(ref);
  if (!context.mounted) return;
  unawaited(ref.read(memberPassProvider.notifier).retry());
  final message = biContinueMessage(AppLocalizations.of(context)!, outcome);
  final messenger = ScaffoldMessenger.of(context);
  goToOnboardingAfterBi(context, ref, outcome);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
