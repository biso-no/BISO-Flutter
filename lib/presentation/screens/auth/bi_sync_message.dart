import '../../../data/services/bi_sync_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';

/// What a student reads when the BI sync did not confirm their student
/// number, or null when there is nothing to tell them: it succeeded, the
/// student cancelled (no [result]), or `directory_unavailable`, which saved
/// the student number and leaves the rest to the membership screen's card.
String? biSyncMessage(AppLocalizations l10n, BiSyncResult? result) {
  if (result == null || result.success) return null;
  return switch (result.error) {
    BiSyncError.directoryUnavailable => null,
    BiSyncError.alreadyLinked => l10n.membershipNeedsBiLinkAlreadyLinked,
    BiSyncError.invalidBiEmail => l10n.membershipNeedsBiLinkInvalidBiEmail,
    _ => l10n.membershipNeedsBiLinkFailed,
  };
}
