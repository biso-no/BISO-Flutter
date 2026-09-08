import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/event_model.dart';
import '../../../data/services/event_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/event/your_trip_card.dart';
import '../../widgets/premium/premium_html_renderer.dart';

// Provider for EventService
final eventServiceProvider = Provider<EventService>((ref) => EventService());

// Search term for events (server-backed)
final eventsSearchTermProvider = StateProvider<String?>((ref) => null);

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  // Paging state
  final ScrollController _scrollController = ScrollController();
  final List<EventModel> _events = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;
  String? _loadedForCampusId;
  // Extends the campus-only tracking above: the locale is baked into every
  // fetched page's title/description (see EventService.listEvents), so a
  // locale change is a load-key change exactly like a campus change is.
  String? _loadedForLocale;
  String? _lastEventsLogKey;

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
      '[EVENTS_SCREEN] Initial load requested',
      extra: {
        'campus_id': campusId,
        'previous_campus_id': _loadedForCampusId,
        'locale': locale,
        'previous_locale': _loadedForLocale,
        'existing_count': _events.length,
      },
    );
    _loadedForCampusId = campusId;
    _loadedForLocale = locale;
    _isLoading = true;
    _isLoadingMore = false;
    _events.clear();
    _currentPage = 1;
    _hasMore = true;
    if (mounted) setState(() {});
    await _fetchPage(page: 1, replace: true);
  }

  Future<void> _fetchPage({required int page, bool replace = false}) async {
    final campusId = ref.read(filterCampusProvider).id;
    final service = ref.read(eventServiceProvider);
    final searchTerm = ref.read(eventsSearchTermProvider);
    final locale = ref.read(localeProvider).languageCode;
    final stopwatch = Stopwatch()..start();
    try {
      AppLogger.info(
        '[EVENTS_SCREEN] Fetching events page',
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
          'search': searchTerm,
          'include_past': false,
        },
      );
      final items = await service.listEvents(
        campusId: campusId,
        locale: locale,
        limit: _pageSize,
        offset: (page - 1) * _pageSize,
        includePast: false,
        search: searchTerm,
      );
      stopwatch.stop();

      // The campus, search term, or locale may have changed while this
      // request was in flight (the user switched campus, edited the
      // search, or the locale changed mid-fetch — either because the saved
      // preference finished loading asynchronously or the user switched
      // language while this screen was mounted). A page fetched for the
      // old campus/search/locale must never be appended to the newly reset
      // list for the new one — otherwise the list can end up mixing
      // languages page to page.
      //
      // Check `mounted` before touching `ref` at all: after dispose,
      // ConsumerStatefulElement.read throws StateError (not just a debug
      // assert), so reading providers here first would crash instead of
      // dropping silently.
      if (!mounted) return;
      final currentCampusId = ref.read(filterCampusProvider).id;
      final currentSearch = ref.read(eventsSearchTermProvider);
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampusId != campusId ||
          currentSearch != searchTerm ||
          currentLocale != locale) {
        AppLogger.info(
          '[EVENTS_SCREEN] Dropping stale events page '
          '(campus/search/locale changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'requested_search': searchTerm,
            'current_search': currentSearch,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. The campus and locale axes reset it via
        // _ensureInitialLoad (build() calls it whenever campus or locale
        // changes, so a replacement page-1 fetch is always queued); the
        // search axis reaches _fetchPage through _reload(), whose replace
        // branch never touches it. A bare `return` here would therefore
        // strand the trailing spinner and make _onScroll refuse to page
        // again for the life of the screen.
        if (!replace) {
          setState(() => _isLoadingMore = false);
        }
        return;
      }

      setState(() {
        if (replace) {
          _events
            ..clear()
            ..addAll(items);
          _isLoading = false;
        } else {
          _events.addAll(items);
          _isLoadingMore = false;
        }
        _hasMore = items.length >= _pageSize;
      });
      AppLogger.info(
        '[EVENTS_SCREEN] Events page loaded',
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
          'search': searchTerm,
          'returned_count': items.length,
          'accumulated_count': _events.length,
          'has_more': _hasMore,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'sample_ids': items.take(3).map((event) => event.id).toList(),
        },
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLogger.error(
        '[EVENTS_SCREEN] Events page failed',
        error: error,
        stackTrace: stackTrace,
        extra: {
          'campus_id': campusId,
          'page': page,
          'page_size': _pageSize,
          'replace': replace,
          'search': searchTerm,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      // A late failure belongs to whichever campus/search/locale this fetch
      // was for. If the user has since switched campus, search, or locale,
      // disabling paging now would kill it for a query that never failed.
      final currentCampusId = ref.read(filterCampusProvider).id;
      final currentSearch = ref.read(eventsSearchTermProvider);
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampusId != campusId ||
          currentSearch != searchTerm ||
          currentLocale != locale) {
        AppLogger.info(
          '[EVENTS_SCREEN] Dropping stale events page failure '
          '(campus/search/locale changed)',
          extra: {
            'requested_campus_id': campusId,
            'current_campus_id': currentCampusId,
            'requested_search': searchTerm,
            'current_search': currentSearch,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'page': page,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched. The campus and locale axes reset it via
        // _ensureInitialLoad (build() calls it whenever campus or locale
        // changes, so a replacement page-1 fetch is always queued); the
        // search axis reaches _fetchPage through _reload(), whose replace
        // branch never touches it. A bare `return` here would therefore
        // strand the trailing spinner and make _onScroll refuse to page
        // again for the life of the screen.
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
      '[EVENTS_SCREEN] Reload requested',
      extra: {
        'loaded_for_campus_id': _loadedForCampusId,
        'search': ref.read(eventsSearchTermProvider),
      },
    );
    await _fetchPage(page: 1, replace: true);
    _currentPage = 1;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    AppLogger.info(
      '[EVENTS_SCREEN] Loading more events',
      extra: {
        'current_page': _currentPage,
        'next_page': _currentPage + 1,
        'current_count': _events.length,
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
    if (isCampusReady) {
      _ensureInitialLoad(campusId, locale);
    } else {
      AppLogger.debug(
        '[EVENTS_SCREEN] Waiting for campus before loading events',
        extra: {
          'campus_id': campusId,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.eventsMessage),
        leading: NavigationUtils.buildBackButton(context),
        actions: [
          IconButton(
            onPressed: () {
              _promptSearch(context);
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),

          // Events List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      _logEventsState(campusId: campusId);

                      // The empty state is rendered inside the
                      // RefreshIndicator (via a CustomScrollView so it fills
                      // the viewport and stays scrollable) so a user looking
                      // at an empty campus can still pull to refresh.
                      return RefreshIndicator(
                        onRefresh: _reload,
                        child: _events.isEmpty
                            ? CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyState(
                                      icon: Icons.event_busy,
                                      title: 'No Events Found',
                                      subtitle:
                                          'There are no events matching your criteria.',
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount:
                                    _events.length + (_isLoadingMore ? 1 : 0),
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  if (index >= _events.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final event = _events[index];
                                  return _EventCard(
                                    event: event,
                                    onTap: () {
                                      _showEventDetails(context, event);
                                    },
                                  );
                                },
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showEventDetails(BuildContext context, EventModel event) {
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
            _EventDetailSheet(event: event, scrollController: scrollController),
      ),
    );
  }

  Future<void> _promptSearch(BuildContext context) async {
    final current = ref.read(eventsSearchTermProvider);
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search events'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Type at least 2 characters',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            if ((current ?? '').isNotEmpty)
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Clear'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (result == null) return; // cancelled

    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      // clear search
      AppLogger.info('[EVENTS_SCREEN] Search cleared');
      ref.read(eventsSearchTermProvider.notifier).state = null;
    } else if (trimmed.length >= 2) {
      AppLogger.info(
        '[EVENTS_SCREEN] Search applied',
        extra: {'search': trimmed},
      );
      ref.read(eventsSearchTermProvider.notifier).state = trimmed;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Search must be at least 2 characters')),
        );
      }
      return;
    }

    // reload with new search param
    await _reload();
  }

  void _logEventsState({required String? campusId}) {
    final search = ref.read(eventsSearchTermProvider);
    final key = [
      campusId,
      search,
      _events.length,
      _hasMore,
      _isLoadingMore,
    ].join('|');
    if (_lastEventsLogKey == key) return;
    _lastEventsLogKey = key;

    final extra = {
      'campus_id': campusId,
      'search': search,
      'loaded_count': _events.length,
      'has_more': _hasMore,
      'is_loading_more': _isLoadingMore,
    };

    if (_events.isEmpty) {
      AppLogger.warning(
        '[EVENTS_SCREEN] No events loaded for campus',
        extra: extra,
      );
    } else {
      AppLogger.info('[EVENTS_SCREEN] Rendering loaded events', extra: extra);
    }
  }
}

/// What the status badge actually communicates to a reader.
///
/// Derived from the event's dates, NOT from the Appwrite `status` column:
/// `status` is the editorial enum `draft`/`published`/`cancelled`, and every
/// row that reaches this screen is `published` (see
/// [EventService.buildEventQueries]), so a status-derived badge would print
/// the constant string "published". `cancelled` is a real enum value and is
/// still honoured.
enum _EventLifecycle { cancelled, upcoming, ongoing, completed }

_EventLifecycle _lifecycleOf(EventModel event) {
  if (event.isCancelled) return _EventLifecycle.cancelled;
  if (event.isOngoing) return _EventLifecycle.ongoing;
  if (event.isCompleted) return _EventLifecycle.completed;
  return _EventLifecycle.upcoming;
}

String _lifecycleLabel(_EventLifecycle lifecycle, AppLocalizations l10n) {
  switch (lifecycle) {
    case _EventLifecycle.cancelled:
      return l10n.cancelledMessage;
    case _EventLifecycle.ongoing:
      return l10n.liveMessage;
    case _EventLifecycle.completed:
      return l10n.endedMessage;
    case _EventLifecycle.upcoming:
      return l10n.upcomingMessage;
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  /// Chips shown on the card: the single `category`, if any, followed by
  /// `tags` — the schema-backed replacement for the old multi-value
  /// `categories` list.
  ///
  /// `category` is a raw lowercase enum token (`social`, `career`, `workshop`,
  /// `talk`, `party`, `sport`, `academic`, `trip`), so it is capitalised for
  /// display. Tags are author-written and are shown verbatim. A tag that
  /// merely repeats the category is dropped case-insensitively — otherwise
  /// `career` + `Career` burn two of the three visible slots on one value.
  List<String> get _chipLabels {
    final labels = <String>[];
    final seen = <String>{};

    void add(String label) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return;
      if (!seen.add(trimmed.toLowerCase())) return;
      labels.add(trimmed);
    }

    final category = event.category?.trim() ?? '';
    if (category.isNotEmpty) {
      add(
        category[0].toUpperCase() + category.substring(1).toLowerCase(),
      );
    }
    event.tags.forEach(add);

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final lifecycle = _lifecycleOf(event);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Image or Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.subtleBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: event.images.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              event.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.event,
                                    color: AppColors.defaultBlue,
                                  ),
                            ),
                          )
                        : const Icon(Icons.event, color: AppColors.defaultBlue),
                  ),

                  const SizedBox(width: 12),

                  // Event Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        if (event.contactName != null &&
                            event.contactName!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            event.contactName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              // Appwrite returns start_date with an explicit
                              // UTC offset (e.g. "...T10:00:00.000+00:00"),
                              // so DateTime.parse produces a DateTime with
                              // isUtc == true. DateFormat renders the
                              // object's own (UTC) fields, so without
                              // .toLocal() this silently shows the event
                              // 1-2 hours early for a Norway-based user.
                              // Display-only: do not add toLocal() to the
                              // isUpcoming/isOngoing/isCompleted comparisons
                              // in event_model.dart — those compare absolute
                              // instants and are already correct.
                              DateFormat(
                                'MMM dd, HH:mm',
                              ).format(event.startDate.toLocal()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                        if (event.location != null &&
                            event.location!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  event.location!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(lifecycle).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _lifecycleLabel(lifecycle, l10n),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _getStatusColor(lifecycle),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              if (_chipLabels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _chipLabels.take(3).map((label) {
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

              if (event.price != null && event.price! > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'NOK ${event.price!.toStringAsFixed(0)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.defaultBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(_EventLifecycle lifecycle) {
    switch (lifecycle) {
      case _EventLifecycle.upcoming:
        return AppColors.accentBlue;
      case _EventLifecycle.ongoing:
        return AppColors.success;
      case _EventLifecycle.completed:
        return AppColors.onSurfaceVariant;
      case _EventLifecycle.cancelled:
        return AppColors.error;
    }
  }
}

class _EventDetailSheet extends StatelessWidget {
  final EventModel event;
  final ScrollController scrollController;

  const _EventDetailSheet({
    required this.event,
    required this.scrollController,
  });

  String _formatEventDate(DateTime startDate, DateTime? endDate) {
    // Appwrite's start_date/end_date parse as UTC DateTimes (isUtc == true).
    // Convert to the device's local time zone before formatting — and
    // before the same-day comparison below, so a start/end pair that spans
    // midnight only in UTC (or only locally) is judged by the calendar day
    // actually shown to the user. This is display-only: it must not be
    // backported to any comparison that decides event lifecycle/filtering.
    final localStart = startDate.toLocal();
    final localEnd = endDate?.toLocal();
    final formatter = DateFormat('EEEE, MMM dd, yyyy • HH:mm');
    final formattedStartDate = formatter.format(localStart);
    if (localEnd != null &&
        localStart.day == localEnd.day &&
        localStart.month == localEnd.month &&
        localStart.year == localEnd.year) {
      return '$formattedStartDate - ${DateFormat('HH:mm').format(localEnd)}';
    }
    return formattedStartDate;
  }

  Color _getStatusColor(_EventLifecycle lifecycle) {
    switch (lifecycle) {
      case _EventLifecycle.upcoming:
        return AppColors.accentBlue;
      case _EventLifecycle.ongoing:
        return AppColors.success;
      case _EventLifecycle.completed:
        return AppColors.gray400;
      case _EventLifecycle.cancelled:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final lifecycle = _lifecycleOf(event);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
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
                Text(
                  event.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.onSurfaceDark
                        : AppColors.onSurface,
                  ),
                ),

                const SizedBox(height: 16),

                // Event Info Row
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: isDark
                          ? AppColors.onSurfaceVariantDark
                          : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatEventDate(event.startDate, event.endDate),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.onSurfaceVariantDark
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                if (event.location != null && event.location!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 20,
                        color: isDark
                            ? AppColors.onSurfaceVariantDark
                            : AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.location!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.onSurfaceVariantDark
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(lifecycle).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor(lifecycle),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _lifecycleLabel(lifecycle, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _getStatusColor(lifecycle),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Personalized "Your trip" logistics for the signed-in user.
                // Renders nothing when signed out or with no assigned segments.
                YourTripCard(eventId: event.id),

                // Description
                if (event.description.isNotEmpty) ...[
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
                  // `content_translations.description` is HTML — render it,
                  // don't print the tags. Same helper jobs_screen uses.
                  event.description.toFullHtml(
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      color: isDark
                          ? AppColors.onSurfaceVariantDark
                          : AppColors.onSurfaceVariant,
                    ),
                    fontSize: 16,
                  ),
                  const SizedBox(height: 24),
                ],

                // Organizer Info
                if (event.contactName != null &&
                    event.contactName!.isNotEmpty)
                  Text(
                    'Organized by ${event.contactName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.onSurfaceVariantDark
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
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

// Removed old _ErrorState (not used with widget-managed pagination)
