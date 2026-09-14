import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/department_model.dart';
import '../../../data/services/department_service.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';

/// Injectable so tests can replace the Appwrite-backed service with a fake.
/// `_departmentsProvider` (and `unit_detail_screen.dart`'s providers) watch
/// this instead of constructing `DepartmentService()` directly.
final departmentServiceProvider = Provider<DepartmentService>(
  (ref) => DepartmentService(),
);

final _departmentsProvider =
    FutureProvider.family<List<DepartmentModel>, String>((ref, campusId) async {
      final service = ref.watch(departmentServiceProvider);
      final locale = ref.watch(localeProvider);
      return service.getActiveDepartmentsForCampus(
        campusId,
        locale: locale.languageCode,
      );
    });

class UnitsOverviewScreen extends ConsumerWidget {
  const UnitsOverviewScreen({super.key});

  static const _title = 'Units & Departments';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campus = ref.watch(filterCampusProvider);
    final campusId = campus.id;
    final asyncDepts = ref.watch(_departmentsProvider(campusId));

    return asyncDepts.when(
      loading: () => const BisoPage(
        title: _title,
        largeTitle: false,
        slivers: [SliverToBoxAdapter(child: BisoSkeleton.grid())],
      ),
      error: (_, _) => BisoPage(
        title: _title,
        largeTitle: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () => ref.invalidate(_departmentsProvider(campusId)),
            ),
          ),
        ],
      ),
      data: (depts) {
        final slivers = depts.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: BisoEmptyState(
                    icon: CupertinoIcons.person_2,
                    accent: BisoAccent.teal,
                    title: 'No active units here yet',
                    message: 'Check back later or switch campus',
                  ),
                ),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: depts.length,
                    itemBuilder: (context, index) =>
                        _DepartmentCard(dept: depts[index]),
                  ),
                ),
              ];
        return BisoPage(title: _title, slivers: slivers);
      },
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final DepartmentModel dept;
  const _DepartmentCard({required this.dept});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final hasLogo = dept.logo != null && dept.logo!.isNotEmpty;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/explore/units/${dept.id}',
          extra: {'id': dept.id, 'name': dept.name},
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: palette.surfaceRaised,
                child: hasLogo
                    ? Image.network(
                        dept.logo!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: BisoIconTile(
                            icon: CupertinoIcons.person_2,
                            accent: BisoAccent.teal,
                            size: 48,
                          ),
                        ),
                      )
                    : const Center(
                        child: BisoIconTile(
                          icon: CupertinoIcons.person_2,
                          accent: BisoAccent.teal,
                          size: 48,
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
                      style: theme.textTheme.titleMedium,
                    ),
                    if ((dept.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Flexible(
                        child: ClipRect(
                          child: dept.description!.toCompactHtml(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.muted,
                            ),
                            maxLines: 1,
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
