import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../data/services/department_service.dart';
import '../../../data/models/department_model.dart';
import '../../widgets/premium/premium_html_renderer.dart';

final _departmentsProvider =
    FutureProvider.family<List<DepartmentModel>, String>((ref, campusId) async {
      final locale = ref.watch(localeProvider);
      final service = DepartmentService();
      return await service.getActiveDepartmentsForCampus(
        campusId,
        locale: locale.languageCode,
      );
    });

class UnitsOverviewScreen extends ConsumerWidget {
  const UnitsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campus = ref.watch(filterCampusProvider);
    final campusId = campus.id;
    final asyncDepts = ref.watch(_departmentsProvider(campusId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Units & Departments')),
      body: asyncDepts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (depts) {
          if (depts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'No active units here yet',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Check back later or switch campus',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Discover student-driven organizations at ${campus.name}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final d = depts[index];
                    return _DepartmentCard(dept: d);
                  }, childCount: depts.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final DepartmentModel dept;
  const _DepartmentCard({required this.dept});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/explore/units/${dept.id}', extra: {'id': dept.id, 'name': dept.name}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: AppColors.subtleBlue,
                child: dept.logo != null && dept.logo!.isNotEmpty
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dept.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((dept.type ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dept.type!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if ((dept.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Flexible(
                        child: ClipRect(
                          child: PremiumHtmlRenderer.compact(
                            htmlContent: dept.description!,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
