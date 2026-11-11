import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../screens/benefits/benefits_routes.dart';
import '../benefits/benefit_spotlight.dart';
import '../biso/biso.dart';

/// "Fordeler for deg" on Home: a compact Spotlight under a header, as a
/// sliver. Takes no height when loading fails, the API is old, or there are
/// no deals.
class HomeBenefitsSection extends ConsumerWidget {
  const HomeBenefitsSection({super.key, required this.campusId});

  final String campusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showcase = ref.watch(benefitShowcaseProvider(campusId));
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;

    final Widget body;
    if (showcase.hasError) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    } else if (showcase.value case final value?) {
      if (value.homeItems.isEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      body = BenefitSpotlight(
        items: value.homeItems,
        campusId: campusId,
        size: BenefitSpotlightSize.compact,
      );
    } else {
      body = const BisoSkeleton.card();
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.benefitsForYou,
                      style: text.headlineSmall?.copyWith(color: palette.ink),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(benefitsRoute()),
                  child: Text(l10n.viewAllMessage),
                ),
              ],
            ),
          ),
          body,
        ],
      ),
    );
  }
}
