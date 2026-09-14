import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/services/job_service.dart';
import 'package:biso/presentation/screens/explore/jobs_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets(
    'passing openJobId the way main.dart does opens the detail sheet for '
    'that job',
    (tester) async {
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

      await pumpBisoScreen(
        tester,
        const JobsScreen(openJobId: 'job-2'),
        routed: true,
        overrides: _overrides(_FixedJobService(jobs)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Marketing Assistant'),
        findsWidgets,
        reason: 'the detail sheet for job-2 should have auto-opened, '
            'showing its title alongside the list row behind it',
      );
      expect(
        find.textContaining('Help with social media.'),
        findsWidgets,
        reason: 'the description appears in both the list row and the '
            'detail sheet',
      );
    },
  );
}
