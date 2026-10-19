import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../data/models/job_application.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/jobs/jobs_provider.dart';
import '../../widgets/biso/biso.dart';

/// The student's applications with their status, the next interview and the
/// answers they gave, as the web's `/applications` page shows them.
class MyApplicationsScreen extends ConsumerWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final leading = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
    );
    final signedIn = ref.watch(
      authStateProvider.select((state) => state.isAuthenticated),
    );

    if (!signedIn) {
      return BisoPage(
        title: l10n.myApplicationsTitle,
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.teal,
              title: l10n.myApplicationsSignIn,
              action: FilledButton(
                onPressed: () => context.go('/auth/login'),
                child: Text(l10n.signInMessage),
              ),
            ),
          ),
        ],
      );
    }

    final applications = ref.watch(myApplicationsProvider);
    return BisoPage(
      title: l10n.myApplicationsTitle,
      leading: leading,
      onRefresh: () => ref.refresh(myApplicationsProvider.future),
      slivers: applications.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              message: l10n.myApplicationsLoadFailed,
              onRetry: () => ref.invalidate(myApplicationsProvider),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: BisoEmptyState(
                    icon: CupertinoIcons.tray,
                    accent: BisoAccent.teal,
                    title: l10n.myApplicationsEmptyTitle,
                    message: l10n.myApplicationsEmptyBody,
                    action: FilledButton(
                      onPressed: () => context.go('/explore/volunteer'),
                      child: Text(l10n.jobBrowseOpenPositions),
                    ),
                  ),
                ),
              ]
            : [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      l10n.myApplicationsIntro,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: BisoPalette.of(context).muted,
                      ),
                    ),
                  ),
                ),
                for (final application in list)
                  SliverToBoxAdapter(
                    child: _ApplicationCard(application: application),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
      ),
    );
  }
}

/// [value] as a date and time in Oslo, or the web's "TBD".
String _dateTime(AppLocalizations l10n, DateTime? value) => value == null
    ? l10n.myApplicationsTbd
    : DateFormat.yMMMd(l10n.localeName).add_Hm().format(osloWallClock(value));

class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.application});

  final MyApplication application;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  bool _showAnswers = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final application = widget.application;
    final job = application.job;
    final interview = application.nextInterview;
    final reviewer = application.hrAssignedName;
    final retainedUntil = application.dataRetentionUntil;
    final applied = l10n.myApplicationsApplied(
      _dateTime(l10n, application.createdAt),
    );
    final meetingUrl = interview?.meetingUrl;
    final meetingUri = meetingUrl == null ? null : Uri.tryParse(meetingUrl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      job?.title ?? l10n.myApplicationsVacancy,
                      style: text.titleMedium?.copyWith(color: palette.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: application.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                job?.campusName == null
                    ? applied
                    : '${job!.campusName} · $applied',
                style: text.bodyMedium?.copyWith(color: palette.muted),
              ),
              if (reviewer != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(CupertinoIcons.person, size: 14, color: palette.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        l10n.myApplicationsReviewer(reviewer),
                        style: text.bodyMedium?.copyWith(color: palette.muted),
                      ),
                    ),
                  ],
                ),
              ],
              if (interview != null) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.myApplicationsUpcomingInterview(interview.title),
                          style: text.titleSmall?.copyWith(color: palette.ink),
                        ),
                        const SizedBox(height: 8),
                        _IconLine(
                          icon: CupertinoIcons.calendar,
                          text: _dateTime(l10n, interview.startsAt),
                        ),
                        if (interview.location != null)
                          _IconLine(
                            icon: CupertinoIcons.location,
                            text: interview.location!,
                          ),
                        if (meetingUri != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => launchUrl(
                              meetingUri,
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(CupertinoIcons.videocam, size: 18),
                            label: Text(l10n.myApplicationsJoinMeeting),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (application.answers.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => setState(() => _showAnswers = !_showAnswers),
                  icon: Icon(
                    _showAnswers
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 14,
                  ),
                  label: Text(
                    l10n.myApplicationsYourAnswers(
                      application.answers.length.toString(),
                    ),
                  ),
                ),
                if (_showAnswers)
                  for (final answer in application.answers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            answer.questionLabel,
                            style: text.labelLarge?.copyWith(
                              color: palette.ink,
                            ),
                          ),
                          Text(
                            answer.answer ?? '—',
                            style: text.bodyMedium?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
              if (job != null && job.slug.isNotEmpty) ...[
                const SizedBox(height: 4),
                OutlinedButton(
                  onPressed: () => context.push(
                    '/explore/volunteer/${Uri.encodeComponent(job.slug)}',
                  ),
                  child: Text(l10n.myApplicationsViewVacancy),
                ),
              ],
              if (retainedUntil != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.myApplicationsStoredUntil(
                    formatOsloDate(retainedUntil, l10n.localeName),
                  ),
                  style: text.bodySmall?.copyWith(color: palette.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final (label, color) = switch (status) {
      ApplicationStatus.submitted => (
        l10n.applicationStatusSubmitted,
        palette.muted,
      ),
      ApplicationStatus.reviewed => (
        l10n.applicationStatusReviewed,
        palette.link,
      ),
      ApplicationStatus.interview => (
        l10n.applicationStatusInterview,
        palette.link,
      ),
      ApplicationStatus.accepted => (
        l10n.applicationStatusAccepted,
        palette.success,
      ),
      ApplicationStatus.rejected => (
        l10n.applicationStatusRejected,
        palette.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}
