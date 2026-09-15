import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/department_model.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';
import 'units_overview_screen.dart' show departmentServiceProvider;

final _departmentProvider = FutureProvider.family<DepartmentModel?, String>((
  ref,
  id,
) async {
  final service = ref.watch(departmentServiceProvider);
  final locale = ref.watch(localeProvider);
  return service.getDepartmentById(id, locale: locale.languageCode);
});

final _socialsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      final service = ref.watch(departmentServiceProvider);
      return service.getDepartmentSocials(id);
    });

class UnitDetailScreen extends ConsumerWidget {
  final String departmentId;
  final String departmentName;
  const UnitDetailScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDept = ref.watch(_departmentProvider(departmentId));
    final asyncSocials = ref.watch(_socialsProvider(departmentId));
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return asyncDept.when(
      loading: () => BisoPage(
        title: departmentName,
        largeTitle: false,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      ),
      error: (_, _) => BisoPage(
        title: departmentName,
        largeTitle: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () =>
                  ref.invalidate(_departmentProvider(departmentId)),
            ),
          ),
        ],
      ),
      data: (dept) {
        if (dept == null) {
          return BisoPage(
            title: departmentName,
            largeTitle: false,
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.person_2,
                  accent: BisoAccent.teal,
                  title: 'Not found',
                ),
              ),
            ],
          );
        }

        final hasLogo = dept.logo != null && dept.logo!.isNotEmpty;
        final hasType = (dept.type ?? '').isNotEmpty;
        final hasDescription = (dept.description ?? '').isNotEmpty;

        return BisoPage(
          title: departmentName,
          largeTitle: false,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: hasLogo
                          ? Image.network(
                              dept.logo!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const BisoIconTile(
                                icon: CupertinoIcons.person_2,
                                accent: BisoAccent.teal,
                                size: 64,
                              ),
                            )
                          : const BisoIconTile(
                              icon: CupertinoIcons.person_2,
                              accent: BisoAccent.teal,
                              size: 64,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        dept.name,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasType)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dept.type!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (hasDescription)
              SliverToBoxAdapter(
                child: BisoSection(
                  child: Material(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: dept.description!.toFullHtml(),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: BisoSection(
                title: 'Find us online',
                child: asyncSocials.when(
                  loading: () => const BisoSkeleton.rows(count: 2),
                  error: (_, _) => Text(
                    'Failed to load socials',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                  data: (socials) {
                    if (socials.isEmpty) {
                      return Text(
                        'No social links yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.muted,
                        ),
                      );
                    }
                    return BisoListGroup(
                      children: [
                        for (final social in socials)
                          BisoListRow(
                            leading: BisoIconTile(
                              icon: _iconForPlatform(
                                (social['platform'] ?? '').toString(),
                              ),
                            ),
                            title: _labelForPlatform(
                              (social['platform'] ?? '').toString(),
                            ),
                            onTap: () {
                              final link = (social['url'] ?? '').toString();
                              if (link.isNotEmpty) {
                                launchUrl(
                                  Uri.parse(link),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// R7 has no brand-logo equivalents in `CupertinoIcons`, so each platform
/// maps to the nearest generic glyph:
/// - instagram -> `photo` (R7: photo, image -> photo)
/// - facebook -> `link` (no Cupertino analog; generic external link)
/// - linkedin -> `briefcase` (R7: work -> briefcase; professional network)
/// - tiktok -> `play_rectangle` (video sharing)
/// - x/twitter -> `at` (R7: matches the "@" glyph the old alternate_email
///   icon stood for)
/// - website/default -> `globe` (brief: "globe for web")
/// - email -> `mail` (brief: "mail for email"; not in the original switch)
IconData _iconForPlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'instagram':
      return CupertinoIcons.photo;
    case 'facebook':
      return CupertinoIcons.link;
    case 'linkedin':
      return CupertinoIcons.briefcase;
    case 'tiktok':
      return CupertinoIcons.play_rectangle;
    case 'x':
    case 'twitter':
      return CupertinoIcons.at;
    case 'email':
      return CupertinoIcons.mail;
    case 'website':
    default:
      return CupertinoIcons.globe;
  }
}

String _labelForPlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'instagram':
      return 'Instagram';
    case 'facebook':
      return 'Facebook';
    case 'linkedin':
      return 'LinkedIn';
    case 'tiktok':
      return 'TikTok';
    case 'x':
    case 'twitter':
      return 'X';
    case 'email':
      return 'Email';
    case 'website':
    default:
      return 'Website';
  }
}
