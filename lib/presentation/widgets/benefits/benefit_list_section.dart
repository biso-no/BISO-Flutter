import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/campus_benefit.dart';
import '../../../data/services/benefits_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../screens/benefits/benefits_routes.dart';
import '../biso/biso.dart';

/// "Dine fordeler": the member benefits for the student's campus, on the
/// member pass screen. A box widget; put it in a SliverToBoxAdapter.
class BenefitListSection extends ConsumerWidget {
  const BenefitListSection({super.key});

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(16, 16, 16, 32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // No campus on the profile (or no user at all): national benefits only.
    final campusId = ref.watch(
      authStateProvider.select((s) => s.user?.campusId),
    );
    final benefits = ref.watch(campusBenefitsProvider(campusId));
    // The benefits screen on the same campus, all of BISO included.
    final viewAll = TextButton(
      onPressed: () => unawaited(
        context.push(benefitsRoute(campusParam: pinnedCampusParam(campusId))),
      ),
      child: Text(l10n.viewAllMessage),
    );
    Widget frame(Widget child) => BisoSection(
      title: l10n.benefitsYourBenefits,
      action: viewAll,
      padding: _padding,
      child: child,
    );

    return benefits.when(
      loading: () => frame(const BisoSkeleton.rows(count: 3)),
      error: (error, _) {
        // An older API without the route: the section simply isn't there.
        if (error is BenefitsApiException &&
            error.kind == BenefitsApiErrorKind.notDeployed) {
          return const SizedBox.shrink();
        }
        return frame(
          BisoErrorState(
            onRetry: () => ref.invalidate(campusBenefitsProvider(campusId)),
          ),
        );
      },
      data: (all) {
        final member = [
          for (final b in all)
            if (b.section == BenefitSection.member) b,
        ];
        if (member.isEmpty) {
          return frame(
            BisoEmptyState(
              icon: CupertinoIcons.gift,
              title: l10n.benefitsEmpty,
            ),
          );
        }
        final language = Localizations.localeOf(context).languageCode;
        return frame(
          BisoListGroup(
            dividerIndent: 68,
            children: [
              for (final benefit in member)
                BisoListRow(
                  leading: _PartnerTile(benefit: benefit),
                  title: benefit.title.resolve(language) ?? '',
                  subtitle: benefit.partner?.name,
                  onTap: () => unawaited(
                    context.push(
                      benefitRoute(benefit.id, campusId: campusId),
                      extra: benefit,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The partner's logo, or its initials when there is none (or it won't load).
class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.benefit});

  static const double _size = 44;

  final CampusBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final name = benefit.partner?.name ?? '';
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final fallback = Center(
      child: Text(
        initials,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: palette.muted),
      ),
    );
    final logo = benefit.partner?.logoUrl;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: _size,
          child: ColoredBox(
            color: palette.surfaceRaised,
            child: logo == null
                ? fallback
                : Image.network(
                    logo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
