import 'dart:typed_data';

import 'job_model.dart';

/// The largest CV or cover letter the server accepts (5 MB each).
const int maxApplicationDocumentBytes = 5 * 1024 * 1024;

/// The most both documents may weigh together. `apps/api` refuses request
/// bodies over 10 MB, so two near-5 MB PDFs plus the form would never arrive.
const int maxApplicationDocumentsTotalBytes = 9 * 1024 * 1024;

/// The longest phone number, country code included, that
/// `job_applications.applicant_phone` holds.
const int maxApplicantPhoneLength = 20;

/// A PDF the student picked for their application.
class ApplicationDocument {
  const ApplicationDocument({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  }) : assert(path != null || bytes != null, 'A document needs its content.');

  final String name;

  /// In bytes.
  final int size;
  final String? path;
  final Uint8List? bytes;

  /// Why the server would refuse this document, or null when it would not.
  ApplicationDocumentProblem? get problem {
    if (!name.toLowerCase().endsWith('.pdf')) {
      return ApplicationDocumentProblem.notPdf;
    }
    if (size > maxApplicationDocumentBytes) {
      return ApplicationDocumentProblem.tooLarge;
    }
    return null;
  }
}

enum ApplicationDocumentProblem { notPdf, tooLarge }

/// Whether [coverLetter] and [resume] fit in one request together.
bool applicationDocumentsFitTogether(
  ApplicationDocument? coverLetter,
  ApplicationDocument? resume,
) =>
    (coverLetter?.size ?? 0) + (resume?.size ?? 0) <=
    maxApplicationDocumentsTotalBytes;

/// Everything one application sends.
class JobApplicationDraft {
  const JobApplicationDraft({
    required this.jobId,
    required this.applicantName,
    this.applicantPhone = '',
    this.linkedinUrl = '',
    this.currentRole = '',
    this.currentEmployer = '',
    this.availability = '',
    this.questions = const [],
    this.answers = const {},
    required this.coverLetter,
    this.resume,
  });

  final String jobId;
  final String applicantName;

  /// Country code and number together, or empty.
  final String applicantPhone;
  final String linkedinUrl;
  final String currentRole;
  final String currentEmployer;

  /// Times that suit an interview, one per line.
  final String availability;
  final List<JobQuestion> questions;

  /// By question id: a `String` for text, long text, select and number, a
  /// `List<String>` for multi-select, a `bool` for yes/no.
  final Map<String, Object?> answers;
  final ApplicationDocument coverLetter;
  final ApplicationDocument? resume;

  /// [question]'s answer as the web's form sends it.
  String formValue(JobQuestion question) {
    final value = answers[question.id];
    return switch (question.type) {
      JobQuestionType.multiSelect =>
        value is List ? value.join(', ') : (value?.toString() ?? ''),
      JobQuestionType.boolean => value == true ? 'true' : '',
      _ => value?.toString() ?? '',
    };
  }
}

/// Whether [value] (as [JobApplicationDraft.answers] holds it) answers a
/// required question: the server refuses a blank one.
bool isAnswerGiven(Object? value) => switch (value) {
  final String text => text.trim().isNotEmpty,
  final List<Object?> picks => picks.isNotEmpty,
  final bool yes => yes,
  _ => false,
};

/// Why the server refused an application: its codes, plus the two the app
/// finds out by itself.
enum ApplicationError {
  invalidData('invalid_data'),
  answerRequired('answer_required'),
  cvRequired('cv_required'),
  coverLetterRequired('cover_letter_required'),
  invalidFile('invalid_file'),
  membersOnly('members_only'),
  vacancyClosed('vacancy_closed'),
  alreadyApplied('already_applied'),
  submitFailed('submit_failed'),

  /// The session is gone (HTTP 401).
  notAuthenticated(null),

  /// The request never got an answer.
  network(null);

  const ApplicationError(this.code);

  final String? code;

  /// The error for a server [code]; an unknown one is a failed submit.
  static ApplicationError fromCode(String? code) {
    for (final error in values) {
      if (error.code != null && error.code == code) return error;
    }
    return submitFailed;
  }
}

sealed class ApplicationSubmitResult {
  const ApplicationSubmitResult();

  const factory ApplicationSubmitResult.submitted(String applicationId) =
      ApplicationSubmitted;

  const factory ApplicationSubmitResult.rejected(
    ApplicationError code,
    String message,
  ) = ApplicationRejected;
}

class ApplicationSubmitted extends ApplicationSubmitResult {
  const ApplicationSubmitted(this.applicationId);

  final String applicationId;
}

class ApplicationRejected extends ApplicationSubmitResult {
  const ApplicationRejected(this.code, this.message);

  final ApplicationError code;

  /// The server's own explanation, ready to show.
  final String message;
}

enum ApplicationStatus {
  submitted,
  reviewed,
  interview,
  accepted,
  rejected;

  static ApplicationStatus fromName(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => submitted,
  );
}

/// The vacancy an application was for.
class MyApplicationJob {
  const MyApplicationJob({
    required this.id,
    required this.slug,
    required this.title,
    this.campusName,
  });

  final String id;
  final String slug;
  final String title;
  final String? campusName;
}

/// The next interview booked for an application.
class ApplicationInterview {
  const ApplicationInterview({
    required this.id,
    required this.title,
    this.startsAt,
    this.endsAt,
    this.location,
    this.meetingUrl,
    this.status,
  });

  final String id;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? location;
  final String? meetingUrl;
  final String? status;
}

class ApplicationAnswer {
  const ApplicationAnswer({required this.questionLabel, this.answer});

  final String questionLabel;
  final String? answer;
}

/// One of the student's own applications, as `GET
/// /api/recruitment/applications` returns it (`MyApplicationView` on the
/// server).
class MyApplication {
  const MyApplication({
    required this.id,
    required this.status,
    this.createdAt,
    this.dataRetentionUntil,
    this.hrAssignedName,
    this.job,
    this.nextInterview,
    this.answers = const [],
  });

  factory MyApplication.fromJson(Map<String, dynamic> json) {
    final job = json['job'];
    final interview = json['next_interview'];
    final answers = json['answers'];
    return MyApplication(
      id: (json[r'$id'] ?? '').toString(),
      status: ApplicationStatus.fromName(json['status']),
      createdAt: _date(json[r'$createdAt']),
      dataRetentionUntil: _date(json['data_retention_until']),
      hrAssignedName: _text(json['hr_assigned_name']),
      job: job is Map
          ? MyApplicationJob(
              id: (job[r'$id'] ?? '').toString(),
              slug: (job['slug'] ?? '').toString(),
              title: (job['title'] ?? '').toString(),
              campusName: _text(job['campus_name']),
            )
          : null,
      nextInterview: interview is Map
          ? ApplicationInterview(
              id: (interview[r'$id'] ?? '').toString(),
              title: (interview['title'] ?? '').toString(),
              startsAt: _date(interview['starts_at']),
              endsAt: _date(interview['ends_at']),
              location: _text(interview['location']),
              meetingUrl: _text(interview['meeting_url']),
              status: _text(interview['status']),
            )
          : null,
      answers: answers is List
          ? [
              for (final answer in answers.whereType<Map>())
                ApplicationAnswer(
                  questionLabel: (answer['question_label'] ?? '').toString(),
                  answer: answer['answer']?.toString(),
                ),
            ]
          : const [],
    );
  }

  final String id;
  final ApplicationStatus status;
  final DateTime? createdAt;
  final DateTime? dataRetentionUntil;
  final String? hrAssignedName;
  final MyApplicationJob? job;
  final ApplicationInterview? nextInterview;
  final List<ApplicationAnswer> answers;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
