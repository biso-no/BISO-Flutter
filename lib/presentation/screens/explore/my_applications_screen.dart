import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/application_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/job/application_provider.dart';

class MyApplicationsScreen extends ConsumerWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Applications')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.defaultBlue,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in to see your applications',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push('/auth/login'),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final applicationsAsync = ref.watch(myApplicationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Applications'),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/explore/volunteer');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: applicationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              const Text('Could not load your applications'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(myApplicationsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (applications) {
          if (applications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.work_outline,
                    size: 48,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No applications yet',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Positions you apply for will show up here.'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.go('/explore/volunteer'),
                    child: const Text('Browse positions'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myApplicationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: applications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _ApplicationCard(application: applications[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final ApplicationModel application;

  const _ApplicationCard({required this.application});

  Color get _statusColor {
    switch (application.status) {
      case 'accepted':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'interview':
        return AppColors.defaultBlue;
      case 'reviewed':
        return AppColors.strongGold;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  String get _statusLabel {
    switch (application.status) {
      case 'submitted':
        return 'Submitted';
      case 'reviewed':
        return 'Under review';
      case 'interview':
        return 'Interview';
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Not selected';
      default:
        return application.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interview = application.nextInterview;

    return Card(
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
                    application.jobTitle ?? 'Vacancy',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (application.jobCampusName != null) ...[
                  const Icon(
                    Icons.location_city,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    application.jobCampusName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (application.createdAt != null) ...[
                  const Icon(
                    Icons.schedule,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Applied ${DateFormat('MMM dd, yyyy').format(application.createdAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (application.hrAssignedName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Contact: ${application.hrAssignedName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
            if (interview != null &&
                interview.status != 'cancelled' &&
                interview.startsAt != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.subtleBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upcoming interview',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.strongBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat(
                        'EEEE, MMM dd • HH:mm',
                      ).format(interview.startsAt!.toLocal()),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.strongBlue,
                      ),
                    ),
                    if (interview.location != null &&
                        interview.location!.isNotEmpty)
                      Text(
                        interview.location!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.strongBlue,
                        ),
                      ),
                    if (interview.meetingUrl != null &&
                        interview.meetingUrl!.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(interview.meetingUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.videocam, size: 16),
                        label: const Text('Join meeting'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
