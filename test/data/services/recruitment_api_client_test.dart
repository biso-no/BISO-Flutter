import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biso/data/models/job_application.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/services/recruitment_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

class _Part {
  _Part(this.headers, this.bytes);

  final Map<String, String> headers;
  final List<int> bytes;

  String get text => utf8.decode(bytes);
  String? get contentType => headers['content-type'];
  String? get filename =>
      RegExp(r'filename="([^"]*)"').firstMatch(_disposition)?.group(1);
  String get name =>
      RegExp(r'name="([^"]*)"').firstMatch(_disposition)!.group(1)!;
  String get _disposition => headers['content-disposition'] ?? '';
}

/// The multipart body [request] carried, by field name.
Future<Map<String, _Part>> _parts(http.Request request) async {
  final boundary = MediaType.parse(
    request.headers['content-type']!,
  ).parameters['boundary']!;
  final parts = <String, _Part>{};
  await for (final part in MimeMultipartTransformer(
    boundary,
  ).bind(Stream.value(request.bodyBytes))) {
    final bytes = await part.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final parsed = _Part(part.headers, bytes);
    parts[parsed.name] = parsed;
  }
  return parts;
}

const _questions = [
  JobQuestion(id: 'why', label: 'Why us?', type: JobQuestionType.text),
  JobQuestion(
    id: 'days',
    label: 'Which days?',
    type: JobQuestionType.multiSelect,
    options: ['Mon', 'Tue', 'Wed'],
  ),
  JobQuestion(id: 'car', label: 'Car?', type: JobQuestionType.boolean),
  JobQuestion(id: 'bike', label: 'Bike?', type: JobQuestionType.boolean),
];

final _coverLetter = ApplicationDocument(
  name: 'letter.pdf',
  size: 4,
  bytes: Uint8List.fromList([1, 2, 3, 4]),
);
final _resume = ApplicationDocument(
  name: 'cv.pdf',
  size: 3,
  bytes: Uint8List.fromList([5, 6, 7]),
);

JobApplicationDraft _draft() => JobApplicationDraft(
  jobId: 'job-1',
  applicantName: 'Kari Nordmann',
  applicantPhone: '+4712345678',
  linkedinUrl: 'https://linkedin.com/in/kari',
  currentRole: 'Student',
  currentEmployer: 'BI',
  availability: 'Mon 10-12\nTue 14-16',
  questions: _questions,
  answers: const {
    'why': 'I like events',
    'days': ['Mon', 'Wed'],
    'car': true,
    'bike': false,
  },
  coverLetter: _coverLetter,
  resume: _resume,
);

void main() {
  late http.Request sent;

  RecruitmentApiClient clientReturning(
    http.Response response, {
    String? jwt = 'jwt-1',
  }) {
    return RecruitmentApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => jwt,
    );
  }

  test(
    "sends the web's field names and both PDFs with a bearer token",
    () async {
      final client = clientReturning(
        http.Response(
          jsonEncode({'success': true, 'applicationId': 'app-1'}),
          201,
        ),
      );

      final result = await client.submit(_draft());

      expect(result, isA<ApplicationSubmitted>());
      expect((result as ApplicationSubmitted).applicationId, 'app-1');
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://api.biso.no/api/recruitment/applications',
      );
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));

      final parts = await _parts(sent);
      final fields = {
        for (final p in parts.values)
          if (p.filename == null) p.name: p.text,
      };
      expect(fields, {
        'job_id': 'job-1',
        'applicant_name': 'Kari Nordmann',
        'applicant_phone': '+4712345678',
        'linkedin_url': 'https://linkedin.com/in/kari',
        'current_role': 'Student',
        'current_employer': 'BI',
        'availability': 'Mon 10-12\nTue 14-16',
        'gdpr_consent': 'true',
        'answer.why': 'I like events',
        'answer_label.why': 'Why us?',
        'answer_type.why': 'text',
        // The web's checkbox list stores the picks as one comma-separated
        // string, in the order they were ticked.
        'answer.days': 'Mon, Wed',
        'answer_label.days': 'Which days?',
        'answer_type.days': 'multi_select',
        'answer.car': 'true',
        'answer_label.car': 'Car?',
        'answer_type.car': 'boolean',
        // An unticked box is an empty answer, as on the web.
        'answer.bike': '',
        'answer_label.bike': 'Bike?',
        'answer_type.bike': 'boolean',
      });

      // The server reads each part's own Content-Type and refuses anything but
      // application/pdf with `invalid_file`.
      expect(parts['resume']!.contentType, 'application/pdf');
      expect(parts['resume']!.filename, 'cv.pdf');
      expect(parts['resume']!.bytes, [5, 6, 7]);
      expect(parts['cover_letter']!.contentType, 'application/pdf');
      expect(parts['cover_letter']!.filename, 'letter.pdf');
      expect(parts['cover_letter']!.bytes, [1, 2, 3, 4]);
    },
  );

  test('leaves the CV out when there is none', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'success': true, 'applicationId': 'a'}), 201),
    );
    final draft = _draft();
    await client.submit(
      JobApplicationDraft(
        jobId: draft.jobId,
        applicantName: draft.applicantName,
        coverLetter: draft.coverLetter,
      ),
    );

    final parts = await _parts(sent);
    expect(parts.containsKey('resume'), isFalse);
    expect(parts['cover_letter']!.contentType, 'application/pdf');
    expect(parts['applicant_phone']!.text, '');
  });

  test('maps 409 already_applied', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'code': 'already_applied',
          'error': 'You have already applied for this position.',
        }),
        409,
      ),
    );

    final result = await client.submit(_draft());

    expect(
      result,
      isA<ApplicationRejected>()
          .having((r) => r.code, 'code', ApplicationError.alreadyApplied)
          .having(
            (r) => r.message,
            'message',
            'You have already applied for this position.',
          ),
    );
  });

  test('maps 403 members_only', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'code': 'members_only',
          'error': 'This position is open to BISO members only.',
        }),
        403,
      ),
    );

    final result = await client.submit(_draft());

    expect(
      result,
      isA<ApplicationRejected>()
          .having((r) => r.code, 'code', ApplicationError.membersOnly)
          .having(
            (r) => r.message,
            'message',
            'This position is open to BISO members only.',
          ),
    );
  });

  test('a 401 means the session is gone', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Authentication required'}),
        401,
      ),
      jwt: null,
    );

    final result = await client.submit(_draft());

    expect(sent.headers.containsKey('Authorization'), isFalse);
    expect(
      result,
      isA<ApplicationRejected>()
          .having((r) => r.code, 'code', ApplicationError.notAuthenticated)
          .having((r) => r.message, 'message', 'Authentication required'),
    );
  });

  test('every server code has its own error', () {
    expect(
      {
        for (final code in [
          'invalid_data',
          'answer_required',
          'cv_required',
          'cover_letter_required',
          'invalid_file',
          'members_only',
          'vacancy_closed',
          'already_applied',
          'submit_failed',
        ])
          code: ApplicationError.fromCode(code),
      },
      {
        'invalid_data': ApplicationError.invalidData,
        'answer_required': ApplicationError.answerRequired,
        'cv_required': ApplicationError.cvRequired,
        'cover_letter_required': ApplicationError.coverLetterRequired,
        'invalid_file': ApplicationError.invalidFile,
        'members_only': ApplicationError.membersOnly,
        'vacancy_closed': ApplicationError.vacancyClosed,
        'already_applied': ApplicationError.alreadyApplied,
        'submit_failed': ApplicationError.submitFailed,
      },
    );
    expect(
      ApplicationError.fromCode('something_new'),
      ApplicationError.submitFailed,
    );
  });

  test(
    'a gateway page or a dropped connection is not a server message',
    () async {
      final gateway = await clientReturning(
        http.Response('<html>502</html>', 502),
      ).submit(_draft());
      expect(
        gateway,
        isA<ApplicationRejected>().having(
          (r) => r.code,
          'code',
          ApplicationError.submitFailed,
        ),
      );

      final offline = await RecruitmentApiClient(
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
        jwtProvider: () async => 'jwt-1',
      ).submit(_draft());
      expect(
        offline,
        isA<ApplicationRejected>().having(
          (r) => r.code,
          'code',
          ApplicationError.network,
        ),
      );
    },
  );

  test('lists my applications', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'applications': [
            {
              r'$createdAt': '2026-10-01T10:00:00.000+00:00',
              r'$id': 'app-1',
              'answers': [
                {'question_label': 'Why us?', 'answer': 'I like events'},
                {'question_label': 'Car?', 'answer': null},
              ],
              'cover_letter': 'Dear BISO',
              'data_retention_until': '2027-03-30T10:00:00.000+00:00',
              'hr_assigned_name': 'Ola HR',
              'job': {
                r'$id': 'job-1',
                'slug': 'event-crew',
                'title': 'Event crew',
                'campus_name': 'Oslo',
              },
              'next_interview': {
                r'$id': 'int-1',
                'starts_at': '2026-10-20T08:00:00.000+00:00',
                'ends_at': '2026-10-20T08:45:00.000+00:00',
                'title': 'First interview',
                'location': 'Nydalen A2',
                'meeting_url': 'https://teams.microsoft.com/l/abc',
                'status': 'scheduled',
              },
              'resume_file_id': 'file-1',
              'status': 'interview',
            },
            {
              r'$createdAt': '2026-09-01T10:00:00.000+00:00',
              r'$id': 'app-2',
              'answers': [],
              'cover_letter': null,
              'data_retention_until': '2027-02-28T10:00:00.000+00:00',
              'hr_assigned_name': null,
              'job': null,
              'next_interview': null,
              'resume_file_id': null,
              'status': 'rejected',
            },
          ],
        }),
        200,
      ),
    );

    final applications = await client.listMine();

    expect(sent.method, 'GET');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/recruitment/applications',
    );
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(applications, hasLength(2));

    final first = applications.first;
    expect(first.id, 'app-1');
    expect(first.status, ApplicationStatus.interview);
    expect(first.createdAt, DateTime.utc(2026, 10, 1, 10));
    expect(first.dataRetentionUntil, DateTime.utc(2027, 3, 30, 10));
    expect(first.hrAssignedName, 'Ola HR');
    expect(first.job!.id, 'job-1');
    expect(first.job!.slug, 'event-crew');
    expect(first.job!.title, 'Event crew');
    expect(first.job!.campusName, 'Oslo');
    expect(first.nextInterview!.title, 'First interview');
    expect(first.nextInterview!.startsAt, DateTime.utc(2026, 10, 20, 8));
    expect(first.nextInterview!.location, 'Nydalen A2');
    expect(
      first.nextInterview!.meetingUrl,
      'https://teams.microsoft.com/l/abc',
    );
    expect(first.answers.map((a) => a.questionLabel), ['Why us?', 'Car?']);
    expect(first.answers.last.answer, isNull);

    final second = applications.last;
    expect(second.status, ApplicationStatus.rejected);
    expect(second.job, isNull);
    expect(second.nextInterview, isNull);
    expect(second.answers, isEmpty);
  });

  test('listing without a session throws a not-authenticated error', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Authentication required'}),
        401,
      ),
    );

    await expectLater(
      client.listMine(),
      throwsA(
        isA<RecruitmentApiException>()
            .having((e) => e.code, 'code', ApplicationError.notAuthenticated)
            .having((e) => e.message, 'message', 'Authentication required'),
      ),
    );
  });

  test('a slow upload is reported as a network problem', () async {
    final client = RecruitmentApiClient(
      httpClient: MockClient((_) async => throw TimeoutException('slow')),
      jwtProvider: () async => 'jwt-1',
    );
    final result = await client.submit(_draft());
    expect(
      result,
      isA<ApplicationRejected>().having(
        (r) => r.code,
        'code',
        ApplicationError.network,
      ),
    );
  });
}
