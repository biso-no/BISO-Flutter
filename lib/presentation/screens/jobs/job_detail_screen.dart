import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/department_name.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../data/models/job_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/jobs/jobs_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';

/// One vacancy, as the web's job page shows it, with the way in to applying.
///
/// Reached by slug (`biso.no/jobs/<slug>`) or row id (`biso://job?id=`), so
/// [idOrSlug] may be either.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.idOrSlug});

  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(jobDetailProvider(idOrSlug));
    final job = detail.valueOrNull;

    return BisoPage(
      title: l10n.jobPosition,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () => NavigationUtils.safeGoBack(
          context,
          fallbackRoute: '/explore/volunteer',
        ),
      ),
      onRefresh: () => ref.refresh(jobDetailProvider(idOrSlug).future),
      slivers: detail.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.card())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () => ref.invalidate(jobDetailProvider(idOrSlug)),
            ),
          ),
        ],
        data: (job) => job == null
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: BisoEmptyState(
                    icon: CupertinoIcons.briefcase,
                    accent: BisoAccent.teal,
                    title: l10n.jobNotOpenTitle,
                    message: l10n.jobNotOpenBody,
                    action: FilledButton(
                      onPressed: () => context.go('/explore/volunteer'),
                      child: Text(l10n.jobBrowseOpenPositions),
                    ),
                  ),
                ),
              ]
            : _jobSlivers(context, job),
      ),
      bottomBar: job != null && _acceptsApplications(job)
          ? BisoBottomBar(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(
                    '/explore/volunteer/${Uri.encodeComponent(job.id)}/apply',
                    extra: job,
                  ),
                  child: Text(l10n.applyNowMessage),
                ),
              ),
            )
          : null,
    );
  }

  /// A vacancy stays open through its deadline; none means open-ended.
  static bool _acceptsApplications(JobModel job) {
    final deadline = job.applicationDeadline;
    return deadline == null || !deadline.isBefore(DateTime.now());
  }

  List<Widget> _jobSlivers(BuildContext context, JobModel job) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final locale = l10n.localeName;
    final company = job.company ?? 'BISO';
    final department = job.departmentName == null
        ? 'BISO'
        : displayDepartmentName(job.departmentName!);
    final deadline = job.applicationDeadline;
    final startDate = job.startDate;
    final contactEmail = job.contactEmail;
    final hasCommitment =
        job.commitment != null || job.term != null || startDate != null;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(label: job.employmentType ?? l10n.jobPosition),
                  if (job.membersOnly)
                    BisoMembersBadge(label: l10n.jobMembersOnly),
                ],
              ),
              const SizedBox(height: 12),
              job.title.toFullHtml(
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: palette.ink,
                ),
                fontSize: 24,
              ),
              const SizedBox(height: 4),
              Text(
                '$company · $department',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (job.location != null)
                    _Pill(icon: CupertinoIcons.location, label: job.location!),
                  if (deadline != null)
                    _Pill(
                      icon: CupertinoIcons.calendar,
                      label: l10n.jobApplyBy(formatOsloDate(deadline, locale)),
                    ),
                  _Pill(
                    icon: CupertinoIcons.clock,
                    label: job.paid ? l10n.jobPaidRole : l10n.jobVolunteerRole,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (job.description.isNotEmpty)
        SliverToBoxAdapter(
          child: BisoSection(
            title: l10n.jobAboutVacancy,
            child: _Surface(
              child: job.description.toFullHtml(
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.5,
                  color: palette.ink,
                ),
              ),
            ),
          ),
        ),
      if (hasCommitment)
        SliverToBoxAdapter(
          child: BisoSection(
            title: l10n.jobCommitment,
            child: BisoListGroup(
              dividerIndent: 16,
              children: [
                if (job.commitment != null)
                  _DetailRow(label: l10n.jobHours, value: job.commitment!),
                if (job.term != null)
                  _DetailRow(label: l10n.jobTerm, value: job.term!),
                if (startDate != null)
                  _DetailRow(
                    label: l10n.jobStartDate,
                    value: formatOsloDate(startDate, locale),
                  ),
              ],
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: BisoSection(
          title: l10n.jobVacancyDetails,
          child: BisoListGroup(
            dividerIndent: 16,
            children: [
              _DetailRow(label: l10n.jobEmployer, value: company),
              _DetailRow(label: l10n.jobDepartment, value: department),
              _DetailRow(
                label: l10n.deadlineMessage,
                value: deadline == null
                    ? l10n.jobRollingDeadline
                    : formatOsloDate(deadline, locale),
              ),
              if (job.location != null)
                _DetailRow(label: l10n.jobLocation, value: job.location!),
              if (job.campusName != null)
                _DetailRow(label: l10n.jobCampus, value: job.campusName!),
              if (contactEmail != null)
                _DetailRow(
                  label: l10n.jobContact,
                  value: job.contactName ?? contactEmail,
                  icon: CupertinoIcons.mail,
                  onTap: () =>
                      launchUrl(Uri(scheme: 'mailto', path: contactEmail)),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: BisoSection(
          title: l10n.jobYourData,
          child: _Surface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(CupertinoIcons.lock_shield, color: palette.link),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.jobYourDataBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }
}

/// A rounded label, optionally with a leading icon.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.hairline, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: palette.muted),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Content on the grouped-list surface.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: BisoPalette.of(context).surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

/// A label above its value, like the web's definition lists.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final valueColor = onTap == null ? palette.ink : palette.link;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.labelMedium?.copyWith(color: palette.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: text.bodyLarge?.copyWith(color: valueColor),
                    ),
                  ],
                ),
              ),
              if (icon != null) Icon(icon, size: 18, color: valueColor),
            ],
          ),
        ),
      ),
    );
  }
}
