import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/department_model.dart';
import '../../../data/services/department_service.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/premium/premium_html_renderer.dart';

final _departmentProvider = FutureProvider.family<DepartmentModel?, String>((
  ref,
  id,
) async {
  final locale = ref.watch(localeProvider);
  final service = DepartmentService();
  return await service.getDepartmentById(id, locale: locale.languageCode);
});

final _socialsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      final service = DepartmentService();
      return await service.getDepartmentSocials(id);
    });

class UnitDetailScreen extends ConsumerWidget {
  final String departmentId;
  final String departmentName;
  const UnitDetailScreen({super.key, required this.departmentId, required this.departmentName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDept = ref.watch(_departmentProvider(departmentId));
    final asyncSocials = ref.watch(_socialsProvider(departmentId));
    final theme = Theme.of(context);

    //Department name

    return Scaffold(
      appBar: AppBar(title: Text(departmentName)),
      body: asyncDept.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (dept) {
          if (dept == null) {
            return const Center(child: Text('Not found'));
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: AppColors.subtleBlue,
                    child: (dept.logo != null && dept.logo!.isNotEmpty)
                        ? Image.network(
                            dept.logo!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.defaultBlue,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.apartment_rounded,
                              color: AppColors.defaultBlue,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dept.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if ((dept.type ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Chip(label: Text(dept.type!)),
                      ],
                      const SizedBox(height: 12),
                      if ((dept.description ?? '').isNotEmpty)
                        PremiumHtmlRenderer.full(
                          htmlContent: dept.description!,
                          padding: const EdgeInsets.only(top: 4),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Find us online',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      asyncSocials.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: LinearProgressIndicator(),
                        ),
                        error: (e, _) => Text('Failed to load socials: $e'),
                        data: (socials) {
                          if (socials.isEmpty) {
                            return const Text('No social links yet');
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: socials.map((s) {
                              final platform = (s['platform'] ?? '').toString();
                              final link = (s['url'] ?? '').toString();
                              return ActionChip(
                                avatar: Icon(_iconForPlatform(platform)),
                                label: Text(_labelForPlatform(platform)),
                                onPressed: () {
                                  if (link.isNotEmpty) {
                                    launchUrl(
                                      Uri.parse(link),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

IconData _iconForPlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'instagram':
      return Icons.camera_alt_outlined;
    case 'facebook':
      return Icons.facebook;
    case 'linkedin':
      return Icons.linked_camera_outlined;
    case 'tiktok':
      return Icons.play_circle_outline;
    case 'x':
    case 'twitter':
      return Icons.alternate_email;
    case 'website':
    default:
      return Icons.link;
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
    case 'website':
    default:
      return 'Website';
  }
}
