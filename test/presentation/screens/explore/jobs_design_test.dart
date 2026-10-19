import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/services/job_service.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/jobs_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/jobs/jobs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

/// One page worth of jobs, so `_hasMore` stays true for offset 0
/// (`items.length >= _pageSize`, and `_pageSize` is 20).
List<JobModel> _page(String label, int count) => List.generate(
  count,
  (i) => JobModel(
    id: '$label-$i',
    title: '$label Title $i',
    description: '$label Description $i',
    departmentId: 'dept-1',
    campusId: _campus.id,
  ),
);

/// Replaces the real Appwrite-backed service. Deterministic and offline:
/// page one (offset 0) and page two (offset 20) each return a full page,
/// every later offset returns nothing so `_hasMore` settles to false.
/// Mirrors `_FakeEventService` in events_design_test.dart — every call
/// resolves immediately, so the test ends with no pending timers or
/// futures.
class _FakeJobService extends JobService {
  final List<int> offsets = [];

  @override
  Future<List<JobModel>> listJobs({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
  }) async {
    offsets.add(offset);
    if (offset >= 40) return const [];
    return _page('p$offset', 20);
  }
}

/// Serves one fixed list of jobs, regardless of paging. Offline and
/// deterministic, mirroring `_FixedEventService` in events_design_test.dart.
class _FixedJobService extends JobService {
  _FixedJobService(this._jobs);

  final List<JobModel> _jobs;

  @override
  Future<List<JobModel>> listJobs({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
  }) async {
    if (offset > 0) return const [];
    return _jobs;
  }
}

List<Override> _overrides(JobService service) => [
  jobServiceProvider.overrideWithValue(service),
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
];

void main() {
  testWidgets('Volunteer builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const JobsScreen(),
      routed: true,
      overrides: _overrides(_FakeJobService()),
    );
  });

  testWidgets('scrolling to the bottom of the list loads the next page', (
    tester,
  ) async {
    final service = _FakeJobService();
    await pumpBisoScreen(
      tester,
      const JobsScreen(),
      routed: true,
      overrides: _overrides(service),
    );

    expect(find.textContaining('p0 Title 0'), findsOneWidget);
    expect(service.offsets, [0], reason: 'only page one is fetched at rest');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(
      service.offsets,
      [0, 20],
      reason: 'scrolling to the bottom must request the next page',
    );
    expect(find.textContaining('p20 Title 0'), findsOneWidget);
  });

  testWidgets("tapping a job opens that job's page", (tester) async {
    final jobs = [
      JobModel(
        id: 'job-1',
        title: 'Event Crew Volunteer',
        description: 'Help run campus events.',
        departmentId: 'dept-1',
        campusId: _campus.id,
      ),
      JobModel(
        id: 'job-2',
        title: 'Marketing Assistant',
        description: 'Help with social media.',
        departmentId: 'dept-1',
        campusId: _campus.id,
      ),
    ];
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/explore/volunteer',
      routes: [
        GoRoute(
          path: '/explore/volunteer',
          builder: (_, _) => const JobsScreen(),
          routes: [
            GoRoute(
              path: ':jobId',
              builder: (_, state) => Scaffold(
                body: Text('Job page ${state.pathParameters['jobId']}'),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(_FixedJobService(jobs)),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Marketing Assistant'));
    await tester.pumpAndSettle();

    expect(find.text('Job page job-2'), findsOneWidget);
  });
}
