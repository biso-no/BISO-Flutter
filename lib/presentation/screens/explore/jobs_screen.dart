import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../data/services/job_service.dart';
import '../../../data/models/job_model.dart';
import '../../widgets/premium/premium_html_renderer.dart';

// Providers
final _jobServiceProvider = Provider<JobService>((ref) => JobService());
// NOTE: Replaced one-shot provider with widget-managed pagination

class JobsScreen extends ConsumerStatefulWidget {
  final String? openJobId;
  const JobsScreen({super.key, this.openJobId});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  bool _pendingAutoOpen = true;

  // Paging state
  final ScrollController _scrollController = ScrollController();
  final List<JobModel> _jobs = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;
  String? _loadedForCampusId;
  String? _lastJobsLogKey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _ensureInitialLoad(String? campusId) async {
    if (_loadedForCampusId == campusId) return;
    AppLogger.info(
      '[JOBS_SCREEN] Initial load requested',
      extra: {
        'campus_id': campusId,
        'previous_campus_id': _loadedForCampusId,
        'existing_count': _jobs.length,
      },
    );
    _loadedForCampusId = campusId;
    _isLoading = true;
    _isLoadingMore = false;
    _jobs.clear();
    _currentPage = 1;
    _hasMore = true;
    if (mounted) setState(() {});
    await _fetchPage(page: 1, replace: true);
  }

  Future<void> _fetchPage({required int page, bool replace = false}) async {
    final campusId = ref.read(filterCampusProvider).id;
    final service = ref.read(_jobServiceProvider);
    final locale = ref.read(localeProvider).languageCode;
    final stopwatch = Stopwatch()..start();
    try {
      AppLogger.info(
        '[JOBS_SCREEN] Fetching jobs page',
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
        },
      );
      final items = await service.listJobs(
        campusId: campusId,
        locale: locale,
        limit: _pageSize,
        offset: (page - 1) * _pageSize,
        includeExpired: false,
      );
      stopwatch.stop();

      // The campus may have changed while this request was in flight (the
      // user switched campus mid-fetch). A page fetched for the old campus
      // must never be appended to the newly reset list for the new one.
      //
      // Check `mounted` before touching `ref` at all: after dispose,
      // ConsumerStatefulElement.read throws StateError (not just a debug
      // assert), so reading providers here first would crash instead of
      // dropping silently.
      if (!mounted) return;
      final currentCampusId = ref.read(filterCampusProvider).id;
      if (currentCampusId != campusId) {
        AppLogger.info(
          '[JOBS_SCREEN] Dropping stale jobs page (campus changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. Only the campus axis resets it (_ensureInitialLoad),
        // so any entry point that changes the query without going
        // through it — as the search axis already does on
        // events_screen — would strand the trailing spinner and make
        // _onScroll refuse to page again for the life of the screen.
        if (!replace) {
          setState(() => _isLoadingMore = false);
        }
        return;
      }

      setState(() {
        if (replace) {
          _jobs
            ..clear()
            ..addAll(items);
          _isLoading = false;
        } else {
          _jobs.addAll(items);
          _isLoadingMore = false;
        }
        _hasMore = items.length >= _pageSize;
      });
      AppLogger.info(
        '[JOBS_SCREEN] Jobs page loaded',
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
          'returned_count': items.length,
          'accumulated_count': _jobs.length,
          'has_more': _hasMore,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'sample_ids': items.take(3).map((job) => job.id).toList(),
        },
      );
      // Auto-open after first batch
      if (_pendingAutoOpen && widget.openJobId != null && _jobs.isNotEmpty) {
        final matches = _jobs
            .where((j) => j.id.toString() == widget.openJobId)
            .toList(growable: false);
        if (matches.isNotEmpty) {
          _pendingAutoOpen = false;
          final jobToOpen = matches.first;
          AppLogger.info(
            '[JOBS_SCREEN] Auto-opening requested job',
            extra: {'job_id': widget.openJobId, 'campus_id': campusId},
          );
          Future.microtask(() {
            if (mounted) _showJobDetails(context, jobToOpen);
          });
        }
      }
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLogger.error(
        '[JOBS_SCREEN] Jobs page failed',
        error: error,
        stackTrace: stackTrace,
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      // A late failure belongs to whichever campus this fetch was for. If
      // the user has since switched campus, disabling paging now would
      // kill it for a campus that never failed.
      final currentCampusId = ref.read(filterCampusProvider).id;
      if (currentCampusId != campusId) {
        AppLogger.info(
          '[JOBS_SCREEN] Dropping stale jobs page failure (campus changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. Only the campus axis resets it (_ensureInitialLoad),
        // so any entry point that changes the query without going
        // through it — as the search axis already does on
        // events_screen — would strand the trailing spinner and make
        // _onScroll refuse to page again for the life of the screen.
        if (!replace) {
          setState(() => _isLoadingMore = false);
        }
        return;
      }
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _reload() async {
    AppLogger.info(
      '[JOBS_SCREEN] Reload requested',
      extra: {'loaded_for_campus_id': _loadedForCampusId},
    );
    _pendingAutoOpen = true;
    await _fetchPage(page: 1, replace: true);
    _currentPage = 1;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    AppLogger.info(
      '[JOBS_SCREEN] Loading more jobs',
      extra: {
        'current_page': _currentPage,
        'next_page': _currentPage + 1,
        'current_count': _jobs.length,
      },
    );
    setState(() => _isLoadingMore = true);
    _currentPage += 1;
    await _fetchPage(page: _currentPage);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final campusId = ref.watch(filterCampusProvider).id;
    final isCampusReady =
        ref.watch(campusInitializedProvider) && campusId.isNotEmpty;
    // Ensure initial load for current campus
    if (isCampusReady) {
      _ensureInitialLoad(campusId);
    } else {
      AppLogger.debug(
        '[JOBS_SCREEN] Waiting for campus before loading jobs',
        extra: {
          'campus_id': campusId,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.volunteerMessage),
        leading: IconButton(
          onPressed: () {
            // Navigate back to home screen (explore tab)
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          // IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          // IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark_border)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                _logJobsState(campusId: campusId);

                // Covers both "no open roles on this campus" (Trondheim has
                // none today) and a failed fetch: the catch in _fetchPage
                // logs and clears the list, so the two are indistinguishable
                // from the state this screen keeps. The copy is honest for
                // either, and the empty state is rendered inside the
                // RefreshIndicator below (via a CustomScrollView so it fills
                // the viewport and stays scrollable) so pull-to-refresh is
                // still reachable — exactly when a user staring at an empty
                // campus would want it.
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: _jobs.isEmpty
                      ? CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyState(
                                icon: Icons.work_off,
                                title: l10n.noItemsFoundMessage,
                                subtitle:
                                    l10n.checkBackLaterOrSwitchCampusMessage,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _jobs.length + (_isLoadingMore ? 1 : 0),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index >= _jobs.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final job = _jobs[index];
                            return _JobCard(
                              job: job,
                              onTap: () => _showJobDetails(context, job),
                            );
                          },
                        ),
                );
              },
            ),
    );
  }

  void _logJobsState({required String? campusId}) {
    final key = [campusId, _jobs.length, _hasMore, _isLoadingMore].join('|');
    if (_lastJobsLogKey == key) return;
    _lastJobsLogKey = key;

    final extra = {
      'campus_id': campusId,
      'loaded_count': _jobs.length,
      'has_more': _hasMore,
      'is_loading_more': _isLoadingMore,
    };

    if (_jobs.isEmpty) {
      AppLogger.warning('[JOBS_SCREEN] No jobs loaded for campus', extra: extra);
    } else {
      AppLogger.info('[JOBS_SCREEN] Rendering loaded jobs', extra: extra);
    }
  }

  void _showJobDetails(BuildContext context, JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) =>
            _JobDetailSheet(job: job, scrollController: scrollController),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final JobModel job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  /// Chips shown on the card: `tags`, de-duplicated case-insensitively so a
  /// repeated tag doesn't burn two of the three visible slots. Same pattern
  /// as `_EventCard._chipLabels` in events_screen.dart; jobs have no
  /// `category` field, so there is nothing to prepend ahead of the tags.
  List<String> get _chipLabels {
    final labels = <String>[];
    final seen = <String>{};

    void add(String label) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return;
      if (!seen.add(trimmed.toLowerCase())) return;
      labels.add(trimmed);
    }

    job.tags.forEach(add);

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shortDescription = job.shortDescription?.trim() ?? '';
    final chipLabels = _chipLabels;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              job.title.toCompactHtml(
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                fontSize: 16,
              ),

              // shortDescription is plain text (unlike title/description,
              // which are HTML) — render it as a plain Text, not through
              // toCompactHtml. Style matches the home job card's description
              // treatment (_PremiumJobCard in premium_home_screen.dart).
              if (shortDescription.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  shortDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.stoneGray,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (chipLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chipLabels.take(3).map((label) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gray200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(label, style: theme.textTheme.labelSmall),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 12),

              // Application Deadline
              Row(
                children: [
                  if (job.applicationDeadline != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      // job.applicationDeadline parses from an Appwrite
                      // UTC-offset timestamp, so it carries isUtc == true.
                      // DateFormat renders the object's own (UTC) fields, so
                      // without .toLocal() the deadline silently displays
                      // 1-2 hours early for a Norway-based user. Display
                      // only — do not add toLocal() to any deadline
                      // comparison used for filtering/expiry.
                      'Apply by ${DateFormat('MMM dd').format(job.applicationDeadline!.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    'View Details',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.defaultBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: AppColors.defaultBlue,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDetailSheet extends StatelessWidget {
  final JobModel job;
  final ScrollController scrollController;

  const _JobDetailSheet({required this.job, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                job.title.toFullHtml(
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.onSurfaceDark
                        : AppColors.onSurface,
                  ),
                  fontSize: 20,
                ),

                const SizedBox(height: 16),

                // Description
                if (job.description.isNotEmpty) ...[
                  Text(
                    'Description',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.onSurfaceDark
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  job.description.toFullHtml(
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      color: isDark
                          ? AppColors.onSurfaceVariantDark
                          : AppColors.onSurfaceVariant,
                    ),
                    fontSize: 16,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
