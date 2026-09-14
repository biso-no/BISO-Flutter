import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/event_model.dart';
import '../../../data/services/event_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';
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

    final List<Widget> contentSlivers;
    if (_isLoading) {
      contentSlivers = [
        const SliverToBoxAdapter(
          child: Column(
            children: [BisoSkeleton.card(), BisoSkeleton.card()],
          ),
        ),
      ];
    } else {
      // The empty state fills the viewport (via SliverFillRemaining) so a
      // user looking at an empty campus can still pull to refresh.
      _logEventsState(campusId: campusId);
      contentSlivers = _events.isEmpty
          ? [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.calendar,
                  accent: BisoAccent.blue,
                  title: 'No Events Found',
                  message: 'There are no events matching your criteria.',
                ),
              ),
            ]
          : [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: _events.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index >= _events.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
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
              ),
            ];
    }

    return BisoPage(
      title: l10n.eventsMessage,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      search: BisoHeaderSearch(
        hintText: l10n.searchEventsMessage,
        initialQuery: ref.read(eventsSearchTermProvider) ?? '',
        onChanged: _applySearch,
      ),
      onRefresh: _reload,
      controller: _scrollController,
      slivers: contentSlivers,
    );
  }

  void _showEventDetails(BuildContext context, EventModel event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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

  Future<void> _applySearch(String value) async {
    final trimmed = value.trim();
    // Preserve the API's minimum query length without a dialog per keystroke.
    if (trimmed.isNotEmpty && trimmed.length < 2) return;
    final query = trimmed.isEmpty ? null : trimmed;
    if (ref.read(eventsSearchTermProvider) == query) return;
    ref.read(eventsSearchTermProvider.notifier).state = query;
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

/// One color per lifecycle, shared by the card and the detail sheet.
Color _statusColor(_EventLifecycle lifecycle, BisoPalette palette) {
  switch (lifecycle) {
    case _EventLifecycle.upcoming:
    case _EventLifecycle.completed:
      return palette.link;
    case _EventLifecycle.ongoing:
      return palette.success;
    case _EventLifecycle.cancelled:
      return palette.error;
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
      add(category[0].toUpperCase() + category.substring(1).toLowerCase());
    }
    event.tags.forEach(add);

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final lifecycle = _lifecycleOf(event);
    final statusColor = _statusColor(lifecycle, palette);

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: event.images.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: event.images.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 640,
                      errorWidget: (_, _, _) =>
                          _EventImagePlaceholder(palette: palette),
                    )
                  : _EventImagePlaceholder(palette: palette),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Render Appwrite UTC instants in the user's local
                    // timezone.
                    DateFormat(
                      'MMM dd, HH:mm',
                    ).format(event.startDate.toLocal()),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.link,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (event.location?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.location!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                  if (event.contactName?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.contactName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(
                        label: _lifecycleLabel(lifecycle, l10n),
                        foreground: statusColor,
                        background: statusColor.withValues(alpha: 0.12),
                      ),
                      for (final label in _chipLabels.take(3))
                        _Chip(
                          label: label,
                          foreground: palette.muted,
                          background: palette.surfaceRaised,
                        ),
                    ],
                  ),
                  if (event.price != null && event.price! > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'NOK ${event.price!.toStringAsFixed(0)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventImagePlaceholder extends StatelessWidget {
  const _EventImagePlaceholder({required this.palette});

  final BisoPalette palette;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.surfaceRaised,
    child: Center(
      child: Icon(CupertinoIcons.calendar, color: palette.link, size: 32),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
    ),
  );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final lifecycle = _lifecycleOf(event);
    final statusColor = _statusColor(lifecycle, palette);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Text(
          event.title,
          style: theme.textTheme.headlineSmall?.copyWith(color: palette.ink),
        ),

        const SizedBox(height: 16),

        // Event Info Row
        Row(
          children: [
            Icon(CupertinoIcons.calendar, size: 20, color: palette.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatEventDate(event.startDate, event.endDate),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
              ),
            ),
          ],
        ),

        if (event.location != null && event.location!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                CupertinoIcons.location_solid,
                size: 20,
                color: palette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.location!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // Status Badge
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _Chip(
            label: _lifecycleLabel(lifecycle, l10n),
            foreground: statusColor,
            background: statusColor.withValues(alpha: 0.12),
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
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 8),
          // `content_translations.description` is HTML — render it,
          // don't print the tags. Same helper jobs_screen uses.
          event.description.toFullHtml(
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: palette.muted,
            ),
            fontSize: 16,
          ),
          const SizedBox(height: 24),
        ],

        // Organizer Info
        if (event.contactName != null && event.contactName!.isNotEmpty)
          Text(
            'Organized by ${event.contactName}',
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
      ],
    );
  }
}
