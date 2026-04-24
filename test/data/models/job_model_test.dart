import 'package:biso/data/models/job_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobModel.fromFunctionJob', () {
    test('parses raw WordPress REST job payloads', () {
      final job = JobModel.fromFunctionJob({
        'id': 36245,
        'date': '2026-04-20T12:00:00',
        'type': 'awsm_job_openings',
        'link':
            'https://biso.no/undergruppe/event-manager-ledelse-av-kreativ-naering/',
        'title': {'rendered': 'Event Manager &#8211; Oslo'},
        'content': {
          'rendered':
              '<p>Join the team.</p><p><strong>Søknadsfrist:</strong> 01.06.2026 kl. 23:59</p>',
        },
        'class_list': [
          'post-36245',
          'awsm_job_openings',
          'campus-oslo',
          'verv-event-manager',
          'interesser-academic-association',
        ],
      }, campusId: '1');

      expect(job.id, '36245');
      expect(job.title, 'Event Manager – Oslo');
      expect(job.campusId, '1');
      expect(job.department, 'Event Manager');
      expect(job.category, 'Event Manager');
      expect(job.requirements, ['Academic Association']);
      expect(job.url, contains('event-manager-ledelse-av-kreativ-naering'));
      expect(job.applicationDeadline, DateTime(2026, 6, 1, 23, 59));
      expect(job.metadata['sourceShape'], 'wordpress_rest');
    });

    test('keeps transformed function payload support', () {
      final job = JobModel.fromFunctionJob({
        'id': 'job-1',
        'title': 'Leader',
        'description': 'Description',
        'campus': ['Bergen'],
        'type': ['BISO Media'],
        'interests': ['Leader'],
        'expiry_date': '2026-06-01T23:59:00',
        'url': 'https://biso.no/job',
      }, campusId: '2');

      expect(job.id, 'job-1');
      expect(job.campusId, '2');
      expect(job.department, 'BISO Media');
      expect(job.requirements, ['Leader']);
      expect(job.skills, ['BISO Media']);
      expect(job.metadata['sourceShape'], 'function');
    });
  });
}
