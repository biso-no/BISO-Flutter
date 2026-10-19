import 'dart:typed_data';

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/job_application.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/recruitment_api_client.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/jobs/job_application_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/jobs/jobs_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _user = UserModel(id: 'u1', name: 'Kari Nordmann', email: 'kari@bi.no');

const _consent =
    'I consent to BISO processing my application data for this recruitment '
    'process. Data is retained for 180 days. An AI tool may help screen '
    'applications, with your name and contact details removed first; all '
    'decisions are made by people.';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(UserModel? user)
    : super(AuthState(isAuthenticated: user != null, user: user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecruitmentApi extends RecruitmentApiClient {
  final List<JobApplicationDraft> submitted = [];
  ApplicationSubmitResult result = const ApplicationSubmitResult.submitted(
    'app-1',
  );

  @override
  Future<ApplicationSubmitResult> submit(JobApplicationDraft draft) async {
    submitted.add(draft);
    return result;
  }
}

JobModel _job({
  List<JobQuestion> questions = const [],
  Map<String, dynamic> metadata = const {},
}) => JobModel(
  id: 'job-1',
  slug: 'event-crew',
  title: 'Event crew',
  description: '<p>Help run events.</p>',
  departmentId: 'dept-1',
  campusId: '1',
  metadata: metadata,
  customQuestions: questions,
);

ApplicationDocument _pdf(String name, int size) =>
    ApplicationDocument(name: name, size: size, bytes: Uint8List(0));

void main() {
  late _FakeRecruitmentApi api;
  late List<ApplicationDocument?> picks;

  setUp(() {
    api = _FakeRecruitmentApi();
    picks = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    required JobModel job,
    UserModel? user = _user,
    bool isMember = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/apply',
      routes: [
        GoRoute(
          path: '/apply',
          builder: (_, _) => JobApplicationScreen(jobId: job.id, job: job),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (_, _) => const Scaffold(body: Text('Login page')),
        ),
        GoRoute(
          path: '/profile/membership',
          builder: (_, _) => const Scaffold(body: Text('Membership page')),
        ),
        GoRoute(
          path: '/profile/applications',
          builder: (_, _) => const Scaffold(body: Text('Applications page')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((_) => _Auth(user)),
          hasValidMembershipProvider.overrideWithValue(isMember),
          recruitmentApiClientProvider.overrideWithValue(api),
          applicationDocumentPickerProvider.overrideWithValue(
            () async => picks.removeAt(0),
          ),
        ],
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(button(label)).onPressed != null;

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(button(label));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String document) async {
    final picker = find.byKey(ValueKey('pick-$document'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out students are asked to sign in', (tester) async {
    await pump(tester, job: _job(), user: null);

    expect(
      find.text('You need a signed-in BISO account to apply.'),
      findsOneWidget,
    );
    expect(find.text('Full name'), findsNothing);

    await tapButton(tester, 'Sign in to apply');
    expect(find.text('Login page'), findsOneWidget);
  });

  testWidgets('members-only jobs ask non-members to join', (tester) async {
    final membersOnly = _job(metadata: {'audience': 'members'});
    await pump(tester, job: membersOnly);

    expect(
      find.text(
        'This position is open to BISO members only. Become a member to '
        'apply.',
      ),
      findsOneWidget,
    );
    expect(find.text('Full name'), findsNothing);

    await tapButton(tester, 'Become a member');
    expect(find.text('Membership page'), findsOneWidget);
  });

  testWidgets('members see the form for a members-only job', (tester) async {
    await pump(
      tester,
      job: _job(metadata: {'audience': 'members'}),
      isMember: true,
    );

    expect(find.text('Become a member'), findsNothing);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Kari Nordmann'), findsOneWidget);
  });

  testWidgets('continue stays disabled until required answers are filled', (
    tester,
  ) async {
    await pump(
      tester,
      job: _job(
        questions: const [
          JobQuestion(
            id: 'why',
            label: 'Why us?',
            type: JobQuestionType.text,
            required: true,
          ),
          JobQuestion(
            id: 'days',
            label: 'Which days?',
            type: JobQuestionType.multiSelect,
            required: true,
            options: ['Mon', 'Tue'],
          ),
          JobQuestion(
            id: 'extra',
            label: 'Anything else?',
            type: JobQuestionType.longText,
          ),
        ],
      ),
    );

    await tapButton(tester, 'Continue');
    expect(find.text('A few questions from the hiring team.'), findsOneWidget);
    expect(enabled(tester, 'Continue'), isFalse);

    await tester.enterText(find.byKey(const ValueKey('question-why')), '  ');
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Continue'), isFalse, reason: 'blank is no answer');

    await tester.enterText(
      find.byKey(const ValueKey('question-why')),
      'I like events',
    );
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Continue'), isFalse, reason: 'days is required');

    await tester.ensureVisible(find.text('Tue'));
    await tester.tap(find.text('Tue'));
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Continue'), isTrue);

    await tapButton(tester, 'Continue');
    expect(find.text('Cover letter (required, PDF)'), findsOneWidget);
  });

  testWidgets('rejects a non-PDF and a file over 5 MB', (tester) async {
    await pump(tester, job: _job());
    await tapButton(tester, 'Continue');
    expect(
      find.text('A few questions from the hiring team.'),
      findsNothing,
      reason: 'a job without questions skips the questions step',
    );
    expect(enabled(tester, 'Review application'), isFalse);

    picks.add(_pdf('letter.docx', 1000));
    await pick(tester, 'cover_letter');
    expect(find.text('Only PDF files are allowed.'), findsOneWidget);
    expect(enabled(tester, 'Review application'), isFalse);

    picks.add(_pdf('letter.pdf', 5 * 1024 * 1024 + 1));
    await pick(tester, 'cover_letter');
    expect(find.text('File exceeds 5MB limit.'), findsOneWidget);
    expect(enabled(tester, 'Review application'), isFalse);

    picks.add(_pdf('letter.pdf', 5 * 1024 * 1024));
    await pick(tester, 'cover_letter');
    expect(find.text('File exceeds 5MB limit.'), findsNothing);
    expect(find.text('Only PDF files are allowed.'), findsNothing);
    expect(enabled(tester, 'Review application'), isTrue);

    picks.add(_pdf('cv.PNG', 1000));
    await pick(tester, 'resume');
    expect(find.text('Only PDF files are allowed.'), findsOneWidget);
    expect(enabled(tester, 'Review application'), isFalse);
  });

  testWidgets('refuses a CV and cover letter over 9 MB together', (
    tester,
  ) async {
    await pump(tester, job: _job());
    await tapButton(tester, 'Continue');

    picks
      ..add(_pdf('letter.pdf', 5 * 1024 * 1024))
      ..add(_pdf('cv.pdf', 4 * 1024 * 1024 + 1));
    await pick(tester, 'cover_letter');
    await pick(tester, 'resume');

    expect(
      find.text(
        'Your CV and cover letter can be at most 9 MB together. Make one of '
        'them smaller and try again.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'Review application'), isFalse);
  });

  testWidgets('a CV is needed when the vacancy asks for one', (tester) async {
    await pump(tester, job: _job(metadata: {'cv_required': true}));
    await tapButton(tester, 'Continue');

    expect(find.text('CV / Résumé (required, PDF)'), findsOneWidget);
    picks.add(_pdf('letter.pdf', 1000));
    await pick(tester, 'cover_letter');
    expect(enabled(tester, 'Review application'), isFalse);

    picks.add(_pdf('cv.pdf', 1000));
    await pick(tester, 'resume');
    expect(enabled(tester, 'Review application'), isTrue);
  });

  testWidgets('the phone number may hold at most 20 characters', (
    tester,
  ) async {
    await pump(tester, job: _job());

    // +47 and 17 more characters is 20.
    await tester.enterText(
      find.byKey(const ValueKey('applicant-phone')),
      '1234567890 234567',
    );
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Continue'), isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('applicant-phone')),
      '1234567890 2345678',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The phone number can be at most 20 characters.'),
      findsOneWidget,
    );
    expect(enabled(tester, 'Continue'), isFalse);
  });

  testWidgets('submit needs consent', (tester) async {
    await pump(tester, job: _job());
    await tapButton(tester, 'Continue');
    picks.add(_pdf('letter.pdf', 1000));
    await pick(tester, 'cover_letter');
    await tapButton(tester, 'Review application');

    expect(find.text(_consent), findsOneWidget);
    expect(enabled(tester, 'Submit application'), isFalse);

    await tapButton(tester, 'Submit application');
    expect(api.submitted, isEmpty);

    await tester.ensureVisible(find.text(_consent));
    await tester.tap(find.text(_consent));
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Submit application'), isTrue);

    await tapButton(tester, 'Submit application');
    expect(api.submitted, hasLength(1));
    final draft = api.submitted.single;
    expect(draft.jobId, 'job-1');
    expect(draft.applicantName, 'Kari Nordmann');
    expect(draft.coverLetter.name, 'letter.pdf');
    expect(draft.resume, isNull);
    expect(find.text('Application submitted!'), findsOneWidget);
    expect(
      find.text("We'll review your application and be in touch at kari@bi.no."),
      findsOneWidget,
    );
  });

  testWidgets("shows the server's message when the application is refused", (
    tester,
  ) async {
    api.result = const ApplicationSubmitResult.rejected(
      ApplicationError.alreadyApplied,
      'You have already applied for this position.',
    );
    await pump(tester, job: _job());
    await tapButton(tester, 'Continue');
    picks.add(_pdf('letter.pdf', 1000));
    await pick(tester, 'cover_letter');
    await tapButton(tester, 'Review application');
    await tester.ensureVisible(find.text(_consent));
    await tester.tap(find.text(_consent));
    await tester.pumpAndSettle();

    await tapButton(tester, 'Submit application');

    expect(
      find.text('You have already applied for this position.'),
      findsOneWidget,
    );
    expect(find.text('Application submitted!'), findsNothing);
  });
}
