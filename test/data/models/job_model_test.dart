import 'dart:convert';

import 'package:biso/data/models/job_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  Object? customQuestions,
  Map<String, dynamic> metadata = const {},
  List<Map<String, dynamic>>? translations,
  Map<String, dynamic>? department,
  Map<String, dynamic>? campus,
}) => {
  r'$id': 'job-1',
  'slug': 'event-crew',
  'status': 'published',
  'campus_id': '1',
  'department_id': 'dept-1',
  'metadata': jsonEncode(metadata),
  'custom_questions': ?customQuestions,
  'translations':
      translations ??
      [
        {'locale': 'en', 'title': 'Event crew', 'description': '<p>Help</p>'},
      ],
  'department': ?department,
  'campus': ?campus,
};

void main() {
  test('parses custom questions of every type', () {
    final job = JobModel.fromAppwriteRow(
      _row(
        customQuestions: jsonEncode([
          {'id': 'why', 'label': 'Why us?', 'type': 'text', 'required': true},
          {
            'id': 'story',
            'label': 'Tell us more',
            'type': 'long_text',
            'help_text': 'A few lines',
          },
          {
            'id': 'shirt',
            'label': 'Shirt size',
            'type': 'select',
            'options': ['S', 'M', 'L'],
          },
          {
            'id': 'days',
            'label': 'Which days?',
            'type': 'multi_select',
            'required': true,
            'options': ['Mon', 'Tue'],
          },
          {'id': 'licence', 'label': 'Driving licence?', 'type': 'boolean'},
          {'id': 'hours', 'label': 'Hours per week', 'type': 'number'},
        ]),
      ),
    );

    expect(job.customQuestions.map((q) => q.type), [
      JobQuestionType.text,
      JobQuestionType.longText,
      JobQuestionType.select,
      JobQuestionType.multiSelect,
      JobQuestionType.boolean,
      JobQuestionType.number,
    ]);
    final why = job.customQuestions.first;
    expect(why.id, 'why');
    expect(why.label, 'Why us?');
    expect(why.required, isTrue);
    expect(why.options, isEmpty);
    expect(job.customQuestions[1].required, isFalse);
    expect(job.customQuestions[1].helpText, 'A few lines');
    expect(job.customQuestions[2].options, ['S', 'M', 'L']);
    expect(job.customQuestions[3].options, ['Mon', 'Tue']);
    expect(job.customQuestions[3].required, isTrue);
    expect(JobQuestionType.multiSelect.wireName, 'multi_select');
    expect(JobQuestionType.longText.wireName, 'long_text');
  });

  test('bad custom_questions JSON gives no questions', () {
    expect(
      JobModel.fromAppwriteRow(
        _row(customQuestions: 'not json'),
      ).customQuestions,
      isEmpty,
    );
    expect(
      JobModel.fromAppwriteRow(
        _row(customQuestions: '{"id":"x"}'),
      ).customQuestions,
      isEmpty,
    );
    // The server reads the list all-or-nothing (a Zod array parse), so one
    // malformed entry means it enforces no questions. The app must not ask
    // questions the server ignores.
    expect(
      JobModel.fromAppwriteRow(
        _row(
          customQuestions: jsonEncode([
            {'id': 'ok', 'label': 'Fine', 'type': 'text'},
            {'id': 'bad', 'label': 'Unknown', 'type': 'date'},
          ]),
        ),
      ).customQuestions,
      isEmpty,
    );
    expect(JobModel.fromAppwriteRow(_row()).customQuestions, isEmpty);
  });

  test('members-only and cv_required come from metadata', () {
    final members = JobModel.fromAppwriteRow(
      _row(metadata: {'audience': 'members', 'cv_required': true}),
    );
    expect(members.membersOnly, isTrue);
    expect(members.cvRequired, isTrue);

    final open = JobModel.fromAppwriteRow(
      _row(metadata: {'audience': 'public', 'cv_required': false}),
    );
    expect(open.membersOnly, isFalse);
    expect(open.cvRequired, isFalse);

    final bare = JobModel.fromAppwriteRow(_row());
    expect(bare.membersOnly, isFalse);
    expect(bare.cvRequired, isFalse);
  });

  test('short description falls back to metadata', () {
    final job = JobModel.fromAppwriteRow(
      _row(metadata: {'short_description': 'Run the doors'}),
    );
    expect(job.shortDescription, 'Run the doors');

    final translated = JobModel.fromAppwriteRow(
      _row(
        metadata: {'short_description': 'Run the doors'},
        translations: [
          {
            'locale': 'en',
            'title': 'Event crew',
            'description': '<p>Help</p>',
            'short_description': 'Translated summary',
          },
        ],
      ),
    );
    expect(translated.shortDescription, 'Translated summary');
  });

  test('reads the vacancy details the web detail page shows', () {
    final job = JobModel.fromAppwriteRow(
      _row(
        metadata: {
          'paid': true,
          'employment_type': 'Part-time',
          'company': 'BISO Oslo',
          'location': 'Nydalen',
          'contact_name': 'Kari',
          'contact_email': 'kari@biso.no',
          'commitment': '5 h/week',
          'term': 'Autumn 2026',
          'start_date': '2026-11-01',
        },
        department: {'Name': 'OSL Marketing', 'type': 'staff'},
        campus: {'name': 'Oslo'},
      ),
    );

    expect(job.paid, isTrue);
    expect(job.employmentType, 'Part-time');
    expect(job.company, 'BISO Oslo');
    expect(job.location, 'Nydalen');
    expect(job.contactName, 'Kari');
    expect(job.contactEmail, 'kari@biso.no');
    expect(job.commitment, '5 h/week');
    expect(job.term, 'Autumn 2026');
    expect(job.startDate, DateTime(2026, 11, 1));
    expect(job.departmentName, 'OSL Marketing');
    expect(job.campusName, 'Oslo');

    final bare = JobModel.fromAppwriteRow(
      _row(metadata: {'company': '  ', 'paid': 'yes'}),
    );
    expect(bare.company, isNull, reason: 'a blank value is no value');
    expect(bare.paid, isFalse);
    expect(bare.departmentName, isNull);
    expect(bare.campusName, isNull);
    expect(bare.startDate, isNull);
  });
}
