import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/biso_glass.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/large_event/large_event_provider.dart';
import '../../../data/models/large_event_model.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/campus/campus_data_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../data/models/app_config.dart';
import '../../../providers/config/app_config_provider.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentLocale = ref.watch(localeProvider);

    Future<void> openDirections(String address) async {
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

    String resolveCampusEmail(String campusId) {
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

    Future<void> openEmail(String email) async {
      final uri = Uri(scheme: 'mailto', path: email);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    l10n.explore,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  _LanguageSwitcher(
                    currentLanguage: currentLocale.languageCode,
                    onLanguageChanged: (languageCode) {
                      ref.read(localeProvider.notifier).setLocale(languageCode);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.language,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Language changed to ${languageCode == 'en' ? 'English' : 'Norwegian'}.',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: AppColors.defaultBlue,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.all(16),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Featured Large Event banner
            Consumer(
              builder: (context, ref, _) {
                final LargeEventModel? event = ref.watch(
                  featuredLargeEventProvider,
                );
                if (event == null) return const SizedBox.shrink();
                return _LargeEventBanner(event: event);
              },
            ),

            const SizedBox(height: 16),
            Text(
              'Categories',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Main Categories Grid
            Consumer(
              builder: (context, ref, child) {
                final configAsync = ref.watch(appConfigProvider);
                final config = configAsync.valueOrNull ?? const AppConfig();

                List<Widget> buildGrid() {
                  final cards = <Widget>[
                    _CategoryCard(
                      icon: Icons.event,
                      title: l10n.eventsMessage,
                      subtitle: l10n.campusEventsActivitiesMessage,
                      color: AppColors.accentBlue,
                      onTap: () => context.go('/explore/events'),
                    ),
                    if (config.departuresEnabled)
                      _CategoryCard(
                        icon: Icons.departure_board,
                        title: l10n.departuresMessage,
                        subtitle: l10n.realtimeBusMetroMessage,
                        color: AppColors.defaultBlue,
                        onTap: () => context.go('/explore/departures'),
                      ),
                    if (config.marketplaceEnabled)
                      _CategoryCard(
                        icon: Icons.shopping_bag,
                        title: l10n.bisoShopMessage,
                        subtitle: l10n.buySellItemsMessage,
                        color: AppColors.green9,
                        onTap: () => context.go('/explore/products'),
                      ),
                    _CategoryCard(
                      icon: Icons.groups,
                      title: l10n.unitsMessage,
                      subtitle: l10n.studentOrganizationsMessage,
                      color: AppColors.purple9,
                      onTap: () => context.go('/explore/units'),
                    ),
                    if (config.expensesEnabled)
                      _CategoryCard(
                        icon: Icons.receipt_long,
                        title: l10n.expensesMessage,
                        subtitle: l10n.expenseReimbursementsMessage,
                        color: AppColors.orange9,
                        onTap: () => context.go('/explore/expenses'),
                      ),
                    _CategoryCard(
                      icon: Icons.volunteer_activism,
                      title: l10n.volunteerMessage,
                      subtitle: l10n.volunteerOpportunitiesMessage,
                      color: AppColors.pink9,
                      onTap: () => context.go('/explore/volunteer'),
                    ),
                    _CategoryCard(
                      icon: Icons.chat,
                      title: l10n.aiAssistantMessage,
                      subtitle: l10n.getHelpInformationMessage,
                      color: AppColors.defaultGold,
                      onTap: () => context.go('/explore/ai-chat'),
                    ),
                  ];
                  return cards;
                }

                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                  children: buildGrid(),
                );
              },
            ),

            const SizedBox(height: 32),

            // Quick Links Section
            Text(
              l10n.quickLinksMessage,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.midNavy.withValues(alpha: 0.5)
                          : AppColors.subtleBlue,
                      child: Icon(
                        Icons.web,
                        color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
                      ),
                    ),
                    title: Text(l10n.bisoWebsiteMessage),
                    subtitle: Text(l10n.visitOurWebsiteMessage),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      launchUrl(Uri.parse('https://biso.no'));
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.midNavy.withValues(alpha: 0.5)
                          : AppColors.subtleBlue,
                      child: Icon(
                        Icons.calendar_today,
                        color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
                      ),
                    ),
                    title: Text(l10n.academicCalendarMessage),
                    subtitle: Text(l10n.viewImportantDatesMessage),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          'https://www.bi.no/en/study-at-bi/international-students/practical-info/academic-calendar/',
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.midNavy.withValues(alpha: 0.5)
                          : AppColors.subtleBlue,
                      child: Icon(
                        Icons.library_books,
                        color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
                      ),
                    ),
                    title: Text(l10n.libraryServicesMessage),
                    subtitle: Text(l10n.bookRoomsResourcesMessage),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      launchUrl(
                        Uri.parse('https://www.bi.no/en/research/library'),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.midNavy.withValues(alpha: 0.5)
                          : AppColors.subtleBlue,
                      child: Icon(
                        Icons.support_agent,
                        color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
                      ),
                    ),
                    title: Text(l10n.studentSupportMessage),
                    subtitle: Text(l10n.getHelpGuidanceMessage),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Campus Information
            Text(
              l10n.campusInformationMessage,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Consumer(
              builder: (context, ref, _) {
                final campus = ref.watch(filterCampusProvider);
                final campusDataAsync = ref.watch(currentCampusDataProvider);

                return campusDataAsync.when(
                  data: (campusData) {
                    final contactEmail =
                        campusData?.location?.email ??
                        resolveCampusEmail(campus.id);
                    final campusAddress =
                        campusData?.location?.address ??
                        'Address not available';
                    final campusName = campus.name.isNotEmpty
                        ? campus.name
                        : 'Campus';

                    // Only show the card if we have valid data
                    if (campusData?.location?.address.isNotEmpty == true) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: AppColors.defaultBlue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    campusName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(campusAddress),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        openDirections(campusAddress),
                                    icon: const Icon(Icons.directions),
                                    label: Text(l10n.directionsMessage),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openEmail(contactEmail),
                                    icon: const Icon(Icons.mail),
                                    label: Text(l10n.contactMessage),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      // Fallback to basic campus info if no location data
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: AppColors.defaultBlue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    campusName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text('Address not available'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.directions),
                                    label: Text(l10n.directionsMessage),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openEmail(contactEmail),
                                    icon: const Icon(Icons.mail),
                                    label: Text(l10n.contactMessage),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  loading: () => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: AppColors.defaultBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Loading campus...',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Loading address...'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.directions),
                                label: Text(l10n.directionsMessage),
                              ),
                              TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.mail),
                                label: Text(l10n.contactMessage),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  error: (error, stackTrace) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: AppColors.defaultBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                campus.name.isNotEmpty ? campus.name : 'Campus',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Unable to load address'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.directions),
                                label: Text(l10n.directionsMessage),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    openEmail(resolveCampusEmail(campus.id)),
                                icon: const Icon(Icons.mail),
                                label: Text(l10n.contactMessage),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BisoGlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      quality: GlassQuality.minimal,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8), // Reduced from 12 to 8
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2), // Reduced from 4 to 2
              Flexible(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeEventBanner extends StatelessWidget {
  final LargeEventModel event;
  const _LargeEventBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final gradient = event.gradientColors;
    return GestureDetector(
      onTap: () => context.push('/events/large/${event.slug}', extra: event),
      child: BisoGlassCard(
        width: double.infinity,
        padding: EdgeInsets.zero,
        borderRadius: 18,
        quality: GlassQuality.standard,
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
                          ?.copyWith(
                            color: event.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: event.textColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSwitcher extends StatefulWidget {
  final String currentLanguage;
  final Function(String) onLanguageChanged;

  const _LanguageSwitcher({
    required this.currentLanguage,
    required this.onLanguageChanged,
  });

  @override
  State<_LanguageSwitcher> createState() => _LanguageSwitcherState();
}

class _LanguageSwitcherState extends State<_LanguageSwitcher> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLanguageMenu(context),
      child: BisoGlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 20,
        quality: GlassQuality.standard,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -5),
              child: Icon(
                Icons.language,
                size: 24,
                color: AppColors.defaultBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguageMenu(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: BisoGlassCard(
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.zero,
            borderRadius: 24,
            quality: GlassQuality.standard,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.subtleBlue.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.defaultBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.language,
                          color: AppColors.defaultBlue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Language',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.strongBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose your preferred language',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _LanguageOption(
                        code: 'en',
                        name: 'English',
                        nativeName: 'English',
                        isSelected: widget.currentLanguage == 'en',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onLanguageChanged('en');
                        },
                      ),
                      const SizedBox(height: 12),
                      _LanguageOption(
                        code: 'no',
                        name: 'Norwegian',
                        nativeName: 'Norsk',
                        isSelected: widget.currentLanguage == 'no',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onLanguageChanged('no');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOption extends StatefulWidget {
  final String code;
  final String name;
  final String nativeName;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LanguageOption> createState() => _LanguageOptionState();
}

class _LanguageOptionState extends State<_LanguageOption> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: widget.isSelected
            ? AppColors.defaultBlue.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? AppColors.defaultBlue.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.isSelected
                          ? [
                              AppColors.defaultBlue,
                              AppColors.defaultBlue.withValues(alpha: 0.8),
                            ]
                          : [
                              AppColors.subtleBlue,
                              AppColors.subtleBlue.withValues(alpha: 0.6),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.defaultBlue.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      widget.code.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: widget.isSelected
                            ? Colors.white
                            : AppColors.defaultBlue,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.isSelected
                              ? AppColors.defaultBlue
                              : theme.textTheme.titleMedium?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.nativeName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.defaultBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.defaultBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
