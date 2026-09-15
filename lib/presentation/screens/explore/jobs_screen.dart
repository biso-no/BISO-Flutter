import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/job_model.dart';
import '../../../data/services/job_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';

// Injectable seam for tests (offline fakes), same runtime behavior as the
// inline `JobService()` construction it replaces. `_jobsProvider` (were one
// to exist) and this screen watch/read this instead of constructing the
// service directly.
final jobServiceProvider = Provider<JobService>((ref) => JobService());

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
  // Extends the campus-only tracking above: the locale is baked into every
  // fetched page's title/description (see JobService.listJobs), so a
  // locale change is a load-key change exactly like a campus change is.
  String? _loadedForLocale;
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

  Future<void> _ensureInitialLoad(String? campusId, String locale) async {
    if (_loadedForCampusId == campusId && _loadedForLocale == locale) return;
    AppLogger.info(
      '[JOBS_SCREEN] Initial load requested',
      extra: {
        'campus_id': campusId,
        'previous_campus_id': _loadedForCampusId,
        'locale': locale,
        'previous_locale': _loadedForLocale,
        'existing_count': _jobs.length,
      },
    );
    _loadedForCampusId = campusId;
    _loadedForLocale = locale;
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
    final service = ref.read(jobServiceProvider);
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

      // The campus or locale may have changed while this request was in
      // flight (the user switched campus, or the locale changed mid-fetch
      // — either because the saved preference finished loading
      // asynchronously or the user switched language while this screen was
      // mounted). A page fetched for the old campus/locale must never be
      // appended to the newly reset list for the new one — otherwise the
      // list can end up mixing languages page to page.
      //
      // Check `mounted` before touching `ref` at all: after dispose,
      // ConsumerStatefulElement.read throws StateError (not just a debug
      // assert), so reading providers here first would crash instead of
      // dropping silently.
      if (!mounted) return;
      final currentCampusId = ref.read(filterCampusProvider).id;
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampusId != campusId || currentLocale != locale) {
        AppLogger.info(
          '[JOBS_SCREEN] Dropping stale jobs page (campus/locale changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. The campus and locale axes reset it via
        // _ensureInitialLoad (build() calls it whenever campus or locale
        // changes, so a replacement page-1 fetch is always queued) — so
        // any entry point that changes the query without going through it
        // would strand the trailing spinner and make _onScroll refuse to
        // page again for the life of the screen.
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
      // A late failure belongs to whichever campus/locale this fetch was
      // for. If the user has since switched campus or locale, disabling
      // paging now would kill it for a query that never failed.
      final currentCampusId = ref.read(filterCampusProvider).id;
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampusId != campusId || currentLocale != locale) {
        AppLogger.info(
          '[JOBS_SCREEN] Dropping stale jobs page failure '
          '(campus/locale changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. The campus and locale axes reset it via
        // _ensureInitialLoad (build() calls it whenever campus or locale
        // changes, so a replacement page-1 fetch is always queued) — so
        // any entry point that changes the query without going through it
        // would strand the trailing spinner and make _onScroll refuse to
        // page again for the life of the screen.
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
    // Watched (not read) so that a locale change — including the saved
    // preference finishing its async load — triggers this build and
    // _ensureInitialLoad below, replacing page one instead of leaving
    // already-loaded titles/descriptions in the old language while later
    // pages fetch in the new one.
    final locale = ref.watch(localeProvider).languageCode;
    final isCampusReady =
        ref.watch(campusInitializedProvider) && campusId.isNotEmpty;
    // Ensure initial load for current campus/locale
    if (isCampusReady) {
      _ensureInitialLoad(campusId, locale);
    } else {
      AppLogger.debug(
        '[JOBS_SCREEN] Waiting for campus before loading jobs',
        extra: {
          'campus_id': campusId,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
    }

    final List<Widget> contentSlivers;
    if (_isLoading) {
      contentSlivers = const [SliverToBoxAdapter(child: BisoSkeleton.rows())];
    } else {
      // The empty state fills the viewport (via SliverFillRemaining) so a
      // user looking at an empty campus can still pull to refresh.
      _logJobsState(campusId: campusId);
      contentSlivers = _jobs.isEmpty
          ? [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.briefcase,
                  accent: BisoAccent.teal,
                  title: l10n.noItemsFoundMessage,
                  message: l10n.checkBackLaterOrSwitchCampusMessage,
                ),
              ),
            ]
          : [
              SliverBisoListGroup(
                dividerIndent: 60,
                itemCount: _jobs.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _jobs.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final job = _jobs[index];
                  return _JobRow(
                    job: job,
                    onTap: () => _showJobDetails(context, job),
                  );
                },
              ),
            ];
    }

    return BisoPage(
      title: l10n.volunteerMessage,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      onRefresh: _reload,
      controller: _scrollController,
      slivers: contentSlivers,
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
      AppLogger.warning(
        '[JOBS_SCREEN] No jobs loaded for campus',
        extra: extra,
      );
    } else {
      AppLogger.info('[JOBS_SCREEN] Rendering loaded jobs', extra: extra);
    }
  }

  void _showJobDetails(BuildContext context, JobModel job) {
    showBisoSheet(
      context: context,
      isScrollControlled: true,
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

/// One row in the jobs list group. Mirrors `BisoJobList`'s row shape in
/// `discovery_sections.dart` (title/description through the HTML renderer,
/// trailing chevron), plus a leading `BisoIconTile` as directed by the task
/// brief. `title`/`description` are HTML (see `JobModel.fromAppwriteRow`),
/// which is why this can't be a plain `BisoListRow` (string-only title and
/// subtitle).
class _JobRow extends StatelessWidget {
  final JobModel job;
  final VoidCallback onTap;

  const _JobRow({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
          child: Row(
            children: [
              const BisoIconTile(
                icon: CupertinoIcons.hand_raised,
                accent: BisoAccent.teal,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    job.title.toCompactHtml(
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                    ),
                    if (job.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      job.description.toCompactHtml(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.muted,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 17,
                color: palette.muted,
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

  /// Chips shown for this job: `tags`, de-duplicated case-insensitively so a
  /// repeated tag doesn't burn two of the three visible slots. Ported
  /// verbatim from the pre-migration `_JobCard._chipLabels` (the only place
  /// tags used to be shown at all).
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
    final palette = BisoPalette.of(context);
    final chipLabels = _chipLabels;

    return ListView(
      controller: scrollController,
      // Clears the tab bar; showBisoSheet restores this bottom safe area.
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        job.title.toFullHtml(
          style: theme.textTheme.headlineSmall?.copyWith(color: palette.ink),
          fontSize: 20,
        ),

        const SizedBox(height: 16),

        // Application deadline. `job.applicationDeadline` parses from an
        // Appwrite UTC-offset timestamp (isUtc == true); DateFormat renders
        // the object's own (UTC) fields, so without .toLocal() the deadline
        // would display 1-2 hours early for a Norway-based user. Display
        // only, ported verbatim from the pre-migration `_JobCard` — do not
        // add toLocal() to any deadline comparison used for
        // filtering/expiry.
        if (job.applicationDeadline != null) ...[
          BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(
                  icon: CupertinoIcons.clock,
                  accent: BisoAccent.teal,
                ),
                title: 'Apply by',
                value: DateFormat(
                  'MMM dd',
                ).format(job.applicationDeadline!.toLocal()),
                showChevron: false,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Tags
        if (chipLabels.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chipLabels
                .take(3)
                .map((label) => Chip(label: Text(label)))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Description
        if (job.description.isNotEmpty) ...[
          Text(
            'Description',
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 8),
          job.description.toFullHtml(
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: palette.muted,
            ),
            fontSize: 16,
          ),
        ],
      ],
    );
  }
}
