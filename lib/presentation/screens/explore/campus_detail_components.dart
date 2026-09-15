import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/campus_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/campus/campus_leadership_section.dart';

/// The pre-redesign rows in this file gave a selection-click on every tap;
/// kept identical (R9 — interaction behavior stays) even though the row
/// widgets that replaced the old custom rows don't do this themselves.
void _tap(VoidCallback action) {
  HapticFeedback.selectionClick();
  action();
}

/// The campus photo cover under the translucent header. Full-bleed image
/// with a bottom-to-top scrim, the campus name and a compact weather/stats
/// row, all inside a fixed-height sliver so it sits flush at scroll offset 0
/// on an `overImage` [BisoPage].
class CampusCover extends StatelessWidget {
  final CampusModel campus;

  const CampusCover({super.key, required this.campus});

  static String _imagePath(String campusId) {
    switch (campusId) {
      case '2': // Bergen
        return 'assets/images/campus/bergen.png';
      case '3': // Trondheim
        return 'assets/images/campus/trondheim.png';
      case '4': // Stavanger
        return 'assets/images/campus/stavanger.png';
      default: // Oslo, National and any unknown id
        return 'assets/images/campus/oslo.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final weather = campus.weather;
    final stats = campus.stats;

    return SliverToBoxAdapter(
      child: SizedBox(
        key: const ValueKey('campus-cover'),
        height: 320,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_imagePath(campus.id), fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campus.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // A Wrap rather than a strict Row: at large text scales the
                  // weather and stats flow onto another line inside the
                  // fixed-height cover instead of being clipped or truncated.
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (weather != null)
                        _CoverStat(
                          label:
                              '${weather.icon} ${weather.temperature.round()}° · ${weather.condition}',
                        ),
                      _CoverStat(
                        icon: CupertinoIcons.building_2_fill,
                        label: '${stats.departmentsCount} ${l10n.unitsMessage}',
                      ),
                      _CoverStat(
                        icon: CupertinoIcons.calendar,
                        label: '${stats.activeEvents} ${l10n.eventsMessage}',
                      ),
                      _CoverStat(
                        icon: CupertinoIcons.briefcase,
                        label: '${stats.availableJobs} ${l10n.jobsMessage}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverStat extends StatelessWidget {
  final IconData? icon;
  final String label;

  const _CoverStat({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 4),
        ],
        // Flexible rather than a plain Text: at a large text scale this
        // wraps onto another line inside the fixed-height cover instead of
        // overflowing the row's width.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class CampusQuickActions extends StatelessWidget {
  final ValueChanged<String> onActionTap;

  const CampusQuickActions({super.key, required this.onActionTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BisoSection(
      child: BisoListGroup(
        children: [
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.calendar,
              accent: BisoAccent.blue,
            ),
            title: l10n.eventMessage,
            onTap: () => _tap(() => onActionTap('events')),
          ),
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.bag,
              accent: BisoAccent.gold,
            ),
            title: l10n.productsMessage,
            onTap: () => _tap(() => onActionTap('products')),
          ),
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.briefcase,
              accent: BisoAccent.teal,
            ),
            title: l10n.jobsMessage,
            onTap: () => _tap(() => onActionTap('jobs')),
          ),
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.person_2,
              accent: BisoAccent.teal,
            ),
            title: l10n.unitsMessage,
            onTap: () => _tap(() => onActionTap('units')),
          ),
        ],
      ),
    );
  }
}

class CampusBenefitCard extends StatefulWidget {
  final String title;
  final List<String> benefits;
  final IconData icon;
  final BisoAccent accent;

  const CampusBenefitCard({
    super.key,
    required this.title,
    required this.benefits,
    required this.icon,
    this.accent = BisoAccent.neutral,
  });

  @override
  State<CampusBenefitCard> createState() => _CampusBenefitCardState();
}

class _CampusBenefitCardState extends State<CampusBenefitCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.benefits.isEmpty) return const SizedBox.shrink();

    final palette = BisoPalette.of(context);
    final theme = Theme.of(context);
    final displayBenefits = _isExpanded
        ? widget.benefits
        : widget.benefits.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BisoIconTile(icon: widget.icon, accent: widget.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final benefit in displayBenefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: widget.accent.fill(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          benefit,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.benefits.length > 3)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _isExpanded = !_isExpanded),
                    child: Text(
                      _isExpanded
                          ? 'Show Less'
                          : 'Show ${widget.benefits.length - 3} More',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Delegates to [CampusLeadershipSection] (board members loaded from the
/// leadership Appwrite function). There is no separate department-entity
/// data source behind this widget; see the deviations note in the task
/// report.
class CampusDepartmentShowcase extends ConsumerWidget {
  final String campusId;

  const CampusDepartmentShowcase({super.key, required this.campusId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CampusLeadershipSection(campusId: campusId);
  }
}

class CampusContactCard extends StatelessWidget {
  final CampusModel campus;

  const CampusContactCard({super.key, required this.campus});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final rows = <Widget>[
      if (campus.contactAddress != null)
        BisoListRow(
          leading: const BisoIconTile(icon: CupertinoIcons.location_solid),
          title: l10n.addressMessage,
          subtitle: campus.contactAddress,
          onTap: () => _tap(() => _launchMaps(campus.contactAddress!)),
        ),
      if (campus.contactEmail != null)
        BisoListRow(
          leading: const BisoIconTile(icon: CupertinoIcons.mail),
          title: l10n.emailMessage,
          subtitle: campus.contactEmail,
          onTap: () => _tap(() => _launchEmail(campus.contactEmail!)),
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return BisoSection(
      title: l10n.contactInformationMessage,
      child: BisoListGroup(children: rows),
    );
  }

  void _launchMaps(String address) async {
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('https://maps.google.com/search/$encodedAddress');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
