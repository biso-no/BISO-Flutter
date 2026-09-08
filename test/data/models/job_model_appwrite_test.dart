import 'package:biso/data/models/job_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> get realJobRow => {
  r'$id': 'job_hr_oslo',
  'slug': 'hr-advisors-for-biso-oslo-2',
  'status': 'published',
  'campus_id': '1',
  'department_id': null,
  'application_deadline': '2026-08-22T00:00:00.000+00:00',
  'metadata':
      '{"auto_screen":true,"auto_translate":false,"company":null,'
      '"employment_type":null,"location":null,'
      '"tags":["HR","Recruitement","teambuilding"]}',
  'translations': [
    {
      'locale': 'en',
      'title': 'HR Advisors for BISO Oslo',
      'description': '<p>Join BISO Oslo’s HR Team!</p>',
      'short_description': 'Join BISO Oslo’s HR Team!',
      'content_type': 'job',
    },
  ],
};

void main() {
  group('JobModel.fromAppwriteRow', () {
    test('parses scalar columns from a real row', () {
      final j = JobModel.fromAppwriteRow(realJobRow);

      expect(j.id, 'job_hr_oslo');
      expect(j.slug, 'hr-advisors-for-biso-oslo-2');
      expect(j.campusId, '1');
      expect(j.status, 'published');
      expect(
        j.applicationDeadline,
        DateTime.parse('2026-08-22T00:00:00.000+00:00'),
      );
    });

    test('parses tags out of the metadata JSON string', () {
      final j = JobModel.fromAppwriteRow(realJobRow);
      expect(j.tags, ['HR', 'Recruitement', 'teambuilding']);
    });

    test('resolves title and description from nested translations', () {
      final j = JobModel.fromAppwriteRow(realJobRow, locale: 'en');
      expect(j.title, 'HR Advisors for BISO Oslo');
      expect(j.description, '<p>Join BISO Oslo’s HR Team!</p>');
      expect(j.shortDescription, 'Join BISO Oslo’s HR Team!');
    });

    test('falls back to the only available locale', () {
      // 21% of live jobs are English-only and 73% Norwegian-only, so a
      // Norwegian reader must still see an English-only posting.
      final j = JobModel.fromAppwriteRow(realJobRow, locale: 'no');
      expect(j.title, 'HR Advisors for BISO Oslo');
    });

    test('tolerates absent metadata and translations', () {
      final row = {...realJobRow}
        ..remove('metadata')
        ..remove('translations');
      final j = JobModel.fromAppwriteRow(row);

      expect(j.title, '');
      expect(j.tags, isEmpty);
    });

    test('treats a missing deadline as open-ended, not expired', () {
      final row = {...realJobRow}..remove('application_deadline');
      final j = JobModel.fromAppwriteRow(row);

      // Must be far future, never the epoch: an open-ended job that reads as
      // long expired is worse than one with no deadline shown at all.
      expect(j.applicationDeadline.isAfter(DateTime.utc(2100)), isTrue);
    });

    test('tolerates unparseable metadata without throwing', () {
      final row = {...realJobRow, 'metadata': 'not json at all'};
      expect(JobModel.fromAppwriteRow(row).tags, isEmpty);
    });

    test('two jobs differing only in slug are not equal', () {
      // Only the `slug` row key changes; fromAppwriteRow maps it 1:1 onto
      // JobModel.slug with no other field derived from it, so this isolates
      // slug alone.
      final a = JobModel.fromAppwriteRow(realJobRow);
      final b = JobModel.fromAppwriteRow({
        ...realJobRow,
        'slug': 'a-different-slug',
      });
      expect(a, isNot(equals(b)));
    });

    test('two jobs differing only in shortDescription are not equal', () {
      // Only the nested translation's `short_description` changes; `title`
      // and `description` on the same translation stay identical, so
      // resolveLocalizedContent yields the same title/description and only
      // shortDescription differs.
      final originalTranslation =
          (realJobRow['translations'] as List).first as Map<String, dynamic>;
      final a = JobModel.fromAppwriteRow(realJobRow);
      final b = JobModel.fromAppwriteRow({
        ...realJobRow,
        'translations': [
          {
            ...originalTranslation,
            'short_description': 'A different short description',
          },
        ],
      });
      expect(a, isNot(equals(b)));
    });

    test('two jobs differing only in tags are not equal', () {
      // tags is derived from the `metadata` JSON string, so any row change
      // that varies tags necessarily varies the `metadata` field too and
      // cannot isolate tags on its own. Instead, build the second instance
      // via the constructor directly, copying every field from `a` except
      // tags (metadata included, unchanged) so only tags varies.
      final a = JobModel.fromAppwriteRow(realJobRow);
      final b = JobModel(
        id: a.id,
        slug: a.slug,
        title: a.title,
        description: a.description,
        shortDescription: a.shortDescription,
        department: a.department,
        departmentId: a.departmentId,
        departmentLogo: a.departmentLogo,
        campusId: a.campusId,
        tags: const ['Different'],
        type: a.type,
        category: a.category,
        requirements: a.requirements,
        responsibilities: a.responsibilities,
        skills: a.skills,
        salary: a.salary,
        timeCommitment: a.timeCommitment,
        startDate: a.startDate,
        url: a.url,
        endDate: a.endDate,
        applicationDeadline: a.applicationDeadline,
        applicationMethod: a.applicationMethod,
        applicationUrl: a.applicationUrl,
        applicationEmail: a.applicationEmail,
        contactPersonName: a.contactPersonName,
        contactPersonEmail: a.contactPersonEmail,
        contactPersonPhone: a.contactPersonPhone,
        maxApplicants: a.maxApplicants,
        currentApplicants: a.currentApplicants,
        status: a.status,
        isUrgent: a.isUrgent,
        isFeatured: a.isFeatured,
        benefits: a.benefits,
        metadata: a.metadata,
        createdAt: a.createdAt,
        updatedAt: a.updatedAt,
      );
      expect(a.metadata, equals(b.metadata));
      expect(a, isNot(equals(b)));
    });

    test('two jobs built from identical input are equal', () {
      final a = JobModel.fromAppwriteRow(realJobRow);
      final b = JobModel.fromAppwriteRow(realJobRow);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
