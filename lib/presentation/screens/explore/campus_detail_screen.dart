import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/biso/biso.dart';
import 'campus_detail_components.dart';

class CampusDetailScreen extends ConsumerWidget {
  final String campusId;

  const CampusDetailScreen({super.key, required this.campusId});

  void _navigateToExplore(BuildContext context, String category) {
    switch (category) {
      case 'events':
        context.push('/explore/events');
        break;
      case 'products':
        context.push('/explore/products');
        break;
      case 'jobs':
        context.push('/explore/volunteer');
        break;
      case 'units':
        context.push('/explore/units');
        break;
      default:
        context.push('/explore');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final campusAsync = ref.watch(campusProvider(campusId));
    final backLeading = BisoBackButton(
      onPressed: () => NavigationUtils.goBackSafely(context),
    );

    return campusAsync.when(
      loading: () => BisoPage(
        title: l10n.campusMessage,
        largeTitle: false,
        leading: backLeading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      ),
      error: (error, stack) => BisoPage(
        title: l10n.campusMessage,
        largeTitle: false,
        leading: backLeading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              message: 'Error loading campus: $error',
              onRetry: () => ref.invalidate(campusProvider(campusId)),
            ),
          ),
        ],
      ),
      data: (campus) {
        if (campus == null) {
          return BisoPage(
            title: l10n.campusMessage,
            largeTitle: false,
            leading: backLeading,
            slivers: const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.location_slash,
                  title: 'Campus not found',
                  message: 'The requested campus could not be found.',
                ),
              ),
            ],
          );
        }

        final theme = Theme.of(context);
        final palette = BisoPalette.of(context);

        return BisoPage(
          overImage: true,
          title: campus.name,
          largeTitle: false,
          leading: backLeading,
          slivers: [
            CampusCover(campus: campus),
            if (campus.description.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    campus.description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: CampusQuickActions(
                onActionTap: (category) =>
                    _navigateToExplore(context, category),
              ),
            ),
            SliverToBoxAdapter(
              child: CampusBenefitCard(
                title: l10n.forStudentsMessage,
                benefits: campus.studentBenefits,
                icon: CupertinoIcons.book,
              ),
            ),
            SliverToBoxAdapter(
              child: CampusBenefitCard(
                title: l10n.forBusinessMessage,
                benefits: campus.businessBenefits,
                icon: CupertinoIcons.building_2_fill,
              ),
            ),
            SliverToBoxAdapter(
              child: CampusBenefitCard(
                title: l10n.careerAdvantagesMessage,
                benefits: campus.careerAdvantages,
                icon: CupertinoIcons.chart_bar_alt_fill,
              ),
            ),
            SliverToBoxAdapter(
              child: CampusDepartmentShowcase(campusId: campus.id),
            ),
            SliverToBoxAdapter(child: CampusContactCard(campus: campus)),
          ],
        );
      },
    );
  }
}
