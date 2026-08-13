import 'package:equatable/equatable.dart';

/// One answer the applicant gave to a vacancy's custom question.
class ApplicationAnswerModel extends Equatable {
  final String questionLabel;
  final String? answer;

  const ApplicationAnswerModel({required this.questionLabel, this.answer});

  factory ApplicationAnswerModel.fromMap(Map<String, dynamic> map) {
    return ApplicationAnswerModel(
      questionLabel: (map['question_label'] ?? '').toString(),
      answer: map['answer']?.toString(),
    );
  }

  @override
  List<Object?> get props => [questionLabel, answer];
}

/// The next scheduled interview for an application, if any.
class ApplicationInterviewModel extends Equatable {
  final String id;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? location;
  final String? meetingUrl;
  final String status; // 'proposed', 'scheduled', 'completed', 'cancelled', 'no_show'

  const ApplicationInterviewModel({
    required this.id,
    required this.title,
    this.startsAt,
    this.endsAt,
    this.location,
    this.meetingUrl,
    this.status = 'proposed',
  });

  factory ApplicationInterviewModel.fromMap(Map<String, dynamic> map) {
    return ApplicationInterviewModel(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startsAt: DateTime.tryParse((map['starts_at'] ?? '').toString()),
      endsAt: DateTime.tryParse((map['ends_at'] ?? '').toString()),
      location: map['location']?.toString(),
      meetingUrl: map['meeting_url']?.toString(),
      status: (map['status'] ?? 'proposed').toString(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    startsAt,
    endsAt,
    location,
    meetingUrl,
    status,
  ];
}

/// A job application submitted by the signed-in user.
class ApplicationModel extends Equatable {
  final String id;
  final DateTime? createdAt;
  final String status; // 'submitted', 'reviewed', 'interview', 'accepted', 'rejected'
  final String? coverLetter;
  final String? resumeFileId;
  final DateTime? dataRetentionUntil;
  final String? hrAssignedName;
  final List<ApplicationAnswerModel> answers;
  final String? jobId;
  final String? jobSlug;
  final String? jobTitle;
  final String? jobCampusName;
  final ApplicationInterviewModel? nextInterview;

  const ApplicationModel({
    required this.id,
    this.createdAt,
    required this.status,
    this.coverLetter,
    this.resumeFileId,
    this.dataRetentionUntil,
    this.hrAssignedName,
    this.answers = const [],
    this.jobId,
    this.jobSlug,
    this.jobTitle,
    this.jobCampusName,
    this.nextInterview,
  });

  factory ApplicationModel.fromMap(Map<String, dynamic> map) {
    final job = map['job'];
    final interview = map['next_interview'];
    return ApplicationModel(
      id: (map['id'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
      status: (map['status'] ?? 'submitted').toString(),
      coverLetter: map['cover_letter']?.toString(),
      resumeFileId: map['resume_file_id']?.toString(),
      dataRetentionUntil: DateTime.tryParse(
        (map['data_retention_until'] ?? '').toString(),
      ),
      hrAssignedName: map['hr_assigned_name']?.toString(),
      answers: (map['answers'] is List)
          ? (map['answers'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ApplicationAnswerModel.fromMap)
                .toList()
          : const [],
      jobId: job is Map<String, dynamic> ? job['id']?.toString() : null,
      jobSlug: job is Map<String, dynamic> ? job['slug']?.toString() : null,
      jobTitle: job is Map<String, dynamic> ? job['title']?.toString() : null,
      jobCampusName: job is Map<String, dynamic>
          ? job['campus_name']?.toString()
          : null,
      nextInterview: interview is Map<String, dynamic>
          ? ApplicationInterviewModel.fromMap(interview)
          : null,
    );
  }

  bool get isDecided => status == 'accepted' || status == 'rejected';

  @override
  List<Object?> get props => [
    id,
    createdAt,
    status,
    coverLetter,
    resumeFileId,
    dataRetentionUntil,
    hrAssignedName,
    answers,
    jobId,
    jobSlug,
    jobTitle,
    jobCampusName,
    nextInterview,
  ];
}
