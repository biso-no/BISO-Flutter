import 'package:biso/data/models/job_application.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/recruitment_api_client.dart';
import 'package:biso/presentation/screens/jobs/my_applications_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/jobs/jobs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(id: 'u1', name: 'Kari Nordmann', email: 'kari@bi.no');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(UserModel? user)
    : super(AuthState(isAuthenticated: user != null, user: user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecruitmentApi extends RecruitmentApiClient {
  _FakeRecruitmentApi(this.applications);

  final List<MyApplication> applications;

  @override
  Future<List<MyApplication>> listMine() async => applications;
}

final _applications = [
  MyApplication(
    id: 'app-1',
    status: ApplicationStatus.interview,
    createdAt: DateTime.utc(2026, 10, 1, 10),
    dataRetentionUntil: DateTime.utc(2027, 3, 30, 10),
    hrAssignedName: 'Ola HR',
    job: const MyApplicationJob(
      id: 'job-1',
      slug: 'event-crew',
      title: 'Event crew',
      campusName: 'Oslo',
    ),
    nextInterview: ApplicationInterview(
      id: 'int-1',
      title: 'First interview',
      startsAt: DateTime.utc(2026, 10, 20, 8),
      location: 'Nydalen A2',
      meetingUrl: 'https://teams.microsoft.com/l/abc',
    ),
    answers: const [
      ApplicationAnswer(questionLabel: 'Why us?', answer: 'I like events'),
    ],
  ),
  const MyApplication(id: 'app-2', status: ApplicationStatus.rejected),
];

List<Override> _overrides({
  UserModel? user = _user,
  List<MyApplication> applications = const [],
}) => [
  authStateProvider.overrideWith((_) => _Auth(user)),
  recruitmentApiClientProvider.overrideWithValue(
    _FakeRecruitmentApi(applications),
  ),
];

void main() {
  testWidgets('My applications builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const MyApplicationsScreen(),
      overrides: _overrides(applications: _applications),
    );
  });

  testWidgets('shows each status, the next interview and the answers', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MyApplicationsScreen(),
      overrides: _overrides(applications: _applications),
    );
    await tester.pumpAndSettle();

    expect(find.text('Event crew'), findsOneWidget);
    expect(find.text('Interview'), findsOneWidget);
    expect(find.text('Not selected'), findsOneWidget);
    expect(find.text('Vacancy'), findsOneWidget);
    expect(find.textContaining('Oslo · Applied'), findsOneWidget);
    expect(find.text('Reviewer: Ola HR'), findsOneWidget);
    expect(find.text('Upcoming interview · First interview'), findsOneWidget);
    expect(find.text('Nydalen A2'), findsOneWidget);
    expect(find.text('Join meeting'), findsOneWidget);
    expect(find.textContaining('Stored until'), findsOneWidget);

    expect(find.text('I like events'), findsNothing);
    await tester.tap(find.text('Your answers (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Why us?'), findsOneWidget);
    expect(find.text('I like events'), findsOneWidget);
  });

  testWidgets('no applications yet points to the open positions', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MyApplicationsScreen(),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();

    expect(find.text('No applications yet'), findsOneWidget);
    expect(find.text('Browse open positions'), findsOneWidget);
  });

  testWidgets('signed out asks to sign in', (tester) async {
    await pumpBisoScreen(
      tester,
      const MyApplicationsScreen(),
      overrides: _overrides(user: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to see your applications'), findsOneWidget);
  });
}
