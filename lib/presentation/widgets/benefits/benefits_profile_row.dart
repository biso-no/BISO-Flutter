import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../screens/benefits/benefits_routes.dart';
import '../biso/biso.dart';

/// "Medlemsfordeler" on Profile: how many benefits the student's own campus
/// has, opening the benefits screen on that campus (all of BISO when the
/// profile has none).
///
/// Profile leaves the row out when [benefitsNotDeployedProvider] says the
/// API has no benefits yet, so no divider is left behind it.
class BenefitsProfileRow extends ConsumerWidget {
  const BenefitsProfileRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // The campus saved on the profile, not the one Home filters by.
    final campusId = ref.watch(
      authStateProvider.select((s) => s.user?.campusId),
    );
    final count = ref
        .watch(benefitShowcaseProvider(campusId))
        .valueOrNull
        ?.count;

    String? subtitle;
    if (count != null) {
      final name = ref.watch(benefitCampusNameProvider(campusId));
      subtitle = l10n.benefitsCountInCampus(
        count,
        name.isEmpty ? l10n.benefitsAllOfBiso : name,
      );
    }

    return BisoListRow(
      leading: const BisoIconTile(
        icon: CupertinoIcons.gift,
        accent: BisoAccent.gold,
      ),
      title: l10n.benefitsMemberBenefits,
      subtitle: subtitle,
      onTap: () => unawaited(
        context.push(benefitsRoute(campusParam: pinnedCampusParam(campusId))),
      ),
    );
  }
}
