import 'package:biso/data/models/application_model.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/models/job_model.dart';
import 'package:biso/data/models/news_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventModel.fromBisoApi', () {
    test('parses the BISO Sites events payload', () {
      final event = EventModel.fromBisoApi({
        'id': 'evt1',
        'slug': 'winter-games',
        'status': 'published',
        'campus_id': '1',
        'campus_name': 'Oslo',
        'department_id': 'dep1',
        'department_name': 'BISO Oslo',
        'title': 'Winter Games',
        'description': '<p>Fun in the snow</p>',
        'short_description': 'Fun!',
        'start_date': '2099-01-15T18:00:00.000+00:00',
        'end_date': '2099-01-15T22:00:00.000+00:00',
        'location': 'Campus Oslo',
        'price': 100,
        'ticket_url': 'https://tickets.example/e/1',
        'image': 'https://cdn.example/img.jpg',
        'category': 'social',
        'tags': ['ski', 'party'],
        'capacity': 50,
        'url': 'https://biso.no/events/winter-games',
        'created_at': '2098-12-01T10:00:00.000+00:00',
        'updated_at': '2098-12-02T10:00:00.000+00:00',
      });

      expect(event.id, 'evt1');
      expect(event.title, 'Winter Games');
      expect(event.campusId, '1');
      expect(event.organizerName, 'BISO Oslo');
      expect(event.venue, 'Campus Oslo');
      expect(event.price, 100.0);
      expect(event.registrationUrl, 'https://tickets.example/e/1');
      expect(event.images, ['https://cdn.example/img.jpg']);
      expect(event.categories, contains('social'));
      expect(event.categories, contains('ski'));
      expect(event.maxAttendees, 50);
      expect(event.status, 'upcoming');
    });

    test('derives completed status for past events', () {
      final event = EventModel.fromBisoApi({
        'id': 'evt2',
        'campus_id': '1',
        'title': 'Past event',
        'description': '',
        'start_date': '2020-01-01T10:00:00.000+00:00',
        'end_date': '2020-01-01T12:00:00.000+00:00',
      });
      expect(event.status, 'completed');
    });
  });

  group('JobModel.fromBisoApi', () {
    test('parses the BISO Sites jobs payload with custom questions', () {
      final job = JobModel.fromBisoApi({
        'id': 'job1',
        'slug': 'marketing-lead',
        'status': 'published',
        'campus_id': '2',
        'campus_name': 'Bergen',
        'department_id': 'dep2',
        'department_name': 'Marketing',
        'title': 'Marketing Lead',
        'description': '<p>Lead our marketing team</p>',
        'short_description': 'Lead role',
        'application_deadline': '2099-03-01T23:59:00.000+00:00',
        'employment_type': 'Volunteer',
        'paid': false,
        'commitment': '5 hours/week',
        'contact_name': 'Kari Nordmann',
        'contact_email': 'kari@biso.no',
        'cv_required': true,
        'tags': ['marketing'],
        'is_open': true,
        'custom_questions': [
          {
            'id': 'q1',
            'label': 'Why do you want this role?',
            'type': 'long_text',
            'required': true,
          },
          {
            'id': 'q2',
            'label': 'Preferred campus',
            'type': 'select',
            'required': false,
            'options': ['Oslo', 'Bergen'],
          },
        ],
        'url': 'https://biso.no/jobs/marketing-lead',
        'created_at': '2099-01-01T08:00:00.000+00:00',
      });

      expect(job.id, 'job1');
      expect(job.slug, 'marketing-lead');
      expect(job.department, 'Marketing');
      expect(job.campusId, '2');
      expect(job.applicationMethod, 'internal');
      expect(job.status, 'open');
      expect(job.cvRequired, true);
      expect(job.timeCommitment, '5 hours/week');
      expect(job.contactPersonEmail, 'kari@biso.no');
      expect(job.customQuestions, hasLength(2));
      expect(job.customQuestions.first.required, true);
      expect(job.customQuestions.last.options, ['Oslo', 'Bergen']);
      expect(job.canApply, true);
    });

    test('marks closed vacancies as not applicable', () {
      final job = JobModel.fromBisoApi({
        'id': 'job2',
        'campus_id': '1',
        'title': 'Closed role',
        'description': '',
        'is_open': false,
      });
      expect(job.status, 'closed');
      expect(job.canApply, false);
    });
  });

  group('NewsModel.fromBisoApi', () {
    test('parses the BISO Sites news payload', () {
      final article = NewsModel.fromBisoApi({
        'id': 'news1',
        'slug': 'welcome-week',
        'status': 'published',
        'campus_id': '1',
        'campus_name': 'Oslo',
        'department_name': 'BISO Oslo',
        'title': 'Welcome Week 2099',
        'content': '<p>Everything you need to know</p>',
        'short_description': 'Get ready',
        'sticky': true,
        'image': 'https://cdn.example/news.jpg',
        'author': 'BISO Comms',
        'url': 'https://biso.no/news/welcome-week',
        'created_at': '2099-08-01T09:00:00.000+00:00',
      });

      expect(article.id, 'news1');
      expect(article.title, 'Welcome Week 2099');
      expect(article.sticky, true);
      expect(article.author, 'BISO Comms');
      expect(article.url, 'https://biso.no/news/welcome-week');
      expect(article.campusId, '1');
    });
  });

  group('ApplicationModel.fromMap', () {
    test('parses the applications API payload', () {
      final application = ApplicationModel.fromMap({
        'id': 'app1',
        'created_at': '2099-02-01T12:00:00.000+00:00',
        'status': 'interview',
        'cover_letter': 'I am motivated',
        'resume_file_id': 'file1',
        'data_retention_until': '2099-09-01T00:00:00.000+00:00',
        'hr_assigned_name': 'Ola Nordmann',
        'answers': [
          {'question_label': 'Why?', 'answer': 'Because'},
        ],
        'job': {
          'id': 'job1',
          'slug': 'marketing-lead',
          'title': 'Marketing Lead',
          'campus_name': 'Bergen',
        },
        'next_interview': {
          'id': 'iv1',
          'title': 'First round',
          'starts_at': '2099-02-10T10:00:00.000+00:00',
          'ends_at': '2099-02-10T11:00:00.000+00:00',
          'location': 'Campus Bergen',
          'meeting_url': null,
          'status': 'scheduled',
        },
      });

      expect(application.id, 'app1');
      expect(application.status, 'interview');
      expect(application.isDecided, false);
      expect(application.jobTitle, 'Marketing Lead');
      expect(application.jobCampusName, 'Bergen');
      expect(application.answers.single.answer, 'Because');
      expect(application.nextInterview?.status, 'scheduled');
      expect(application.nextInterview?.location, 'Campus Bergen');
    });
  });
}
