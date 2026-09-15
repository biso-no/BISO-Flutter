import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

import '../../../data/models/app_config.dart';
import '../../../data/models/large_event_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_data_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/config/app_config_provider.dart';
import '../../../providers/large_event/large_event_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _query = '';

  Future<void> _openDirections(String address) async {
    final encoded = Uri.encodeComponent(address);
    Uri uri;
    if (Platform.isIOS) {
      uri = Uri.parse('http://maps.apple.com/?q=$encoded');
    } else if (Platform.isAndroid) {
      uri = Uri.parse('geo:0,0?q=$encoded');
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _resolveCampusEmail(String campusId) {
    switch (campusId.toLowerCase()) {
      case '1':
      case 'oslo':
        return 'president.oslo@biso.no';
      case '2':
      case 'bergen':
        return 'president.bergen@biso.no';
      case '3':
      case 'trondheim':
        return 'president.trondheim@biso.no';
      case '4':
      case 'stavanger':
        return 'president.stavanger@biso.no';
      default:
        return 'contact@biso.no';
    }
  }

  Future<void> _openEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showLanguageSheet() {
    showBisoSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer(
            builder: (context, ref, _) {
              final palette = BisoPalette.of(context);
              final currentLanguage = ref.watch(localeProvider).languageCode;
              void select(String code) {
                ref.read(localeProvider.notifier).setLocale(code);
                Navigator.pop(sheetContext);
              }

              return BisoListGroup(
                children: [
                  BisoListRow(
                    title: 'English',
                    trailing: currentLanguage == 'en'
                        ? Icon(CupertinoIcons.checkmark, color: palette.link)
                        : null,
                    onTap: () => select('en'),
                  ),
                  BisoListRow(
                    title: 'Norsk',
                    trailing: currentLanguage == 'no'
                        ? Icon(CupertinoIcons.checkmark, color: palette.link)
                        : null,
                    onTap: () => select('no'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final configAsync = ref.watch(appConfigProvider);
    final config = configAsync.valueOrNull ?? const AppConfig();
    final event = ref.watch(featuredLargeEventProvider);

    final categories = <_CategoryData>[
      _CategoryData(
        icon: CupertinoIcons.calendar,
        accent: BisoAccent.blue,
        title: l10n.eventsMessage,
        subtitle: l10n.campusEventsActivitiesMessage,
        onTap: () => context.go('/explore/events'),
      ),
      if (config.departuresEnabled)
        _CategoryData(
          icon: CupertinoIcons.tram_fill,
          accent: BisoAccent.blue,
          title: l10n.departuresMessage,
          subtitle: l10n.realtimeBusMetroMessage,
          onTap: () => context.go('/explore/departures'),
        ),
      if (config.marketplaceEnabled)
        _CategoryData(
          icon: CupertinoIcons.bag,
          accent: BisoAccent.gold,
          title: l10n.bisoShopMessage,
          subtitle: l10n.buySellItemsMessage,
          onTap: () => context.go('/explore/products'),
        ),
      _CategoryData(
        icon: CupertinoIcons.person_2,
        accent: BisoAccent.teal,
        title: l10n.unitsMessage,
        subtitle: l10n.studentOrganizationsMessage,
        onTap: () => context.go('/explore/units'),
      ),
      if (config.expensesEnabled)
        _CategoryData(
          icon: CupertinoIcons.doc_plaintext,
          accent: BisoAccent.coral,
          title: l10n.expensesMessage,
          subtitle: l10n.expenseReimbursementsMessage,
          onTap: () => context.go('/explore/expenses'),
        ),
      _CategoryData(
        icon: CupertinoIcons.briefcase,
        accent: BisoAccent.teal,
        title: l10n.volunteerMessage,
        subtitle: l10n.volunteerOpportunitiesMessage,
        onTap: () => context.go('/explore/volunteer'),
      ),
      _CategoryData(
        icon: CupertinoIcons.bubble_left_bubble_right,
        accent: BisoAccent.violet,
        title: l10n.aiAssistantMessage,
        subtitle: l10n.getHelpInformationMessage,
        onTap: () => context.go('/explore/ai-chat'),
      ),
    ];

    final matches = _query.isEmpty
        ? categories
        : categories
              .where(
                (category) => '${category.title} ${category.subtitle}'
                    .toLowerCase()
                    .contains(_query),
              )
              .toList();

    return BisoPage(
      title: l10n.explore,
      search: BisoHeaderSearch(
        hintText: l10n.searchExploreMessage,
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
      ),
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.globe,
          tooltip: l10n.languageMessage,
          onPressed: _showLanguageSheet,
        ),
      ],
      slivers: [
        if (_query.isEmpty && event != null)
          SliverToBoxAdapter(child: _LargeEventBanner(event: event)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              l10n.discoverEventsAndOpportunitiesMessage,
              style: theme.textTheme.bodyLarge?.copyWith(color: palette.muted),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: matches.isEmpty
              ? BisoEmptyState(
                  icon: CupertinoIcons.search,
                  title: l10n.noSearchResultsMessage,
                )
              : BisoSection(
                  child: BisoListGroup(
                    children: [
                      for (final category in matches)
                        BisoListRow(
                          leading: BisoIconTile(
                            icon: category.icon,
                            accent: category.accent,
                          ),
                          title: category.title,
                          subtitle: category.subtitle,
                          onTap: category.onTap,
                        ),
                    ],
                  ),
                ),
        ),
        if (_query.isEmpty) ...[
          SliverToBoxAdapter(
            child: BisoSection(
              title: l10n.quickLinksMessage,
              child: BisoListGroup(
                children: [
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.globe),
                    title: l10n.bisoWebsiteMessage,
                    subtitle: l10n.visitOurWebsiteMessage,
                    onTap: () => launchUrl(Uri.parse('https://biso.no')),
                  ),
                  BisoListRow(
                    leading: const BisoIconTile(
                      icon: CupertinoIcons.calendar,
                      accent: BisoAccent.blue,
                    ),
                    title: l10n.academicCalendarMessage,
                    subtitle: l10n.viewImportantDatesMessage,
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://www.bi.no/en/study-at-bi/international-students/practical-info/academic-calendar/',
                      ),
                    ),
                  ),
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.book),
                    title: l10n.libraryServicesMessage,
                    subtitle: l10n.bookRoomsResourcesMessage,
                    onTap: () => launchUrl(
                      Uri.parse('https://www.bi.no/en/research/library'),
                    ),
                  ),
                  BisoListRow(
                    leading: const BisoIconTile(
                      icon: CupertinoIcons.question_circle,
                    ),
                    title: l10n.studentSupportMessage,
                    subtitle: l10n.getHelpGuidanceMessage,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _CampusContactSection(
              openDirections: _openDirections,
              openEmail: _openEmail,
              resolveCampusEmail: _resolveCampusEmail,
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryData {
  const _CategoryData({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final BisoAccent accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _LargeEventBanner extends StatelessWidget {
  final LargeEventModel event;
  const _LargeEventBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final gradient = event.gradientColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/events/large/${event.slug}', extra: event),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: event.textColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(
                              color: event.textColor.withValues(alpha: 0.9),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(CupertinoIcons.chevron_forward, color: event.textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The campus name, address and contact actions shown at the bottom of
/// Explore. Kept as one widget (instead of the four near-duplicate branches
/// the pre-migration screen inlined per `AsyncValue` state) since every
/// branch renders the same shape and only its text and button availability
/// change.
class _CampusContactSection extends ConsumerWidget {
  const _CampusContactSection({
    required this.openDirections,
    required this.openEmail,
    required this.resolveCampusEmail,
  });

  final Future<void> Function(String address) openDirections;
  final Future<void> Function(String email) openEmail;
  final String Function(String campusId) resolveCampusEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final campus = ref.watch(filterCampusProvider);
    final campusDataAsync = ref.watch(currentCampusDataProvider);

    late final String name;
    late final String address;
    late final void Function()? onDirections;
    late final void Function()? onContact;

    campusDataAsync.when(
      data: (campusData) {
        final hasAddress = campusData?.location?.address.isNotEmpty == true;
        name = campus.name.isNotEmpty ? campus.name : 'Campus';
        final contactEmail =
            campusData?.location?.email ?? resolveCampusEmail(campus.id);
        if (hasAddress) {
          final campusAddress = campusData!.location!.address;
          address = campusAddress;
          onDirections = () => openDirections(campusAddress);
        } else {
          address = 'Address not available';
          onDirections = null;
        }
        onContact = () => openEmail(contactEmail);
      },
      loading: () {
        name = 'Loading campus...';
        address = 'Loading address...';
        onDirections = null;
        onContact = null;
      },
      error: (error, stackTrace) {
        name = campus.name.isNotEmpty ? campus.name : 'Campus';
        address = 'Unable to load address';
        onDirections = null;
        onContact = () => openEmail(resolveCampusEmail(campus.id));
      },
    );

    return BisoSection(
      title: l10n.campusInformationMessage,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BisoIconTile(
                    icon: CupertinoIcons.location_solid,
                    accent: BisoAccent.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: palette.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                address,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDirections,
                      icon: const Icon(CupertinoIcons.location_north_line),
                      label: Text(l10n.directionsMessage),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onContact,
                      icon: const Icon(CupertinoIcons.mail),
                      label: Text(l10n.contactMessage),
                    ),
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
