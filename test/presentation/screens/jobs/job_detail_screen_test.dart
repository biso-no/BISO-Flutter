import 'package:biso/core/utils/oslo_time.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/services/job_service.dart';
import 'package:biso/presentation/screens/jobs/job_detail_screen.dart';
import 'package:biso/providers/jobs/jobs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

class _FakeJobService extends JobService {
  _FakeJobService(this.job);

  final JobModel? job;
  final List<String> asked = [];

  @override
  Future<JobModel?> getJob(String idOrSlug, {String locale = 'no'}) async {
    asked.add(idOrSlug);
    return job;
  }
}

final _deadline = DateTime.utc(2030, 6, 15, 12);

JobModel _job({DateTime? deadline}) => JobModel(
  id: 'job-1',
  slug: 'event-crew',
  title: 'Event crew',
  description: '<p>Help run campus events.</p>',
  departmentId: 'dept-1',
  campusId: '1',
  applicationDeadline: deadline,
  departmentName: 'OSL Marketing',
  campusName: 'Oslo',
  metadata: const {
    'audience': 'members',
    'paid': true,
    'employment_type': 'Part-time',
    'company': 'BISO Oslo',
    'location': 'Nydalen',
    'contact_name': 'Kari',
    'contact_email': 'kari@biso.no',
    'commitment': '5 h/week',
    'term': 'Autumn 2030',
  },
);

List<Override> _overrides(JobService service) => [
  jobServiceProvider.overrideWithValue(service),
];

void main() {
  testWidgets('Job detail builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const JobDetailScreen(idOrSlug: 'event-crew'),
      overrides: _overrides(_FakeJobService(_job(deadline: _deadline))),
    );
  });

  testWidgets('shows what the web detail page shows', (tester) async {
    final service = _FakeJobService(_job(deadline: _deadline));
    await pumpBisoScreen(
      tester,
      const JobDetailScreen(idOrSlug: 'event-crew'),
      overrides: _overrides(service),
    );
    await tester.pumpAndSettle();

    expect(service.asked, ['event-crew']);
    final deadline = formatOsloDate(_deadline, 'en');
    expect(deadline, contains('2030'), reason: 'the deadline shows its year');
    for (final text in [
      'Part-time',
      'Members only',
      'BISO Oslo · Marketing',
      'Nydalen',
      'Apply by $deadline',
      'Paid role',
      '5 h/week',
      'Autumn 2030',
      'Oslo',
      'Kari',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Apply Now'), findsOneWidget);
  });

  testWidgets('offers no Apply button once the deadline has passed', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const JobDetailScreen(idOrSlug: 'event-crew'),
      overrides: _overrides(
        _FakeJobService(_job(deadline: DateTime.utc(2020, 1, 1))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Event crew'), findsWidgets);
    expect(find.text('Apply Now'), findsNothing);
  });

  testWidgets('a vacancy that is gone says so', (tester) async {
    await pumpBisoScreen(
      tester,
      const JobDetailScreen(idOrSlug: 'old-job'),
      overrides: _overrides(_FakeJobService(null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('This position is no longer open'), findsOneWidget);
    expect(find.text('Apply Now'), findsNothing);
  });
}
