# Jobs Appwrite Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate jobs off the failing `api.biso.no` HTTP API onto direct Appwrite reads, reusing the shared content layer unchanged.

**Architecture:** Mirrors the events migration exactly. `JobService` reads `jobs` in one round trip with translations nested via `Query.select(['*','translations.*'])`, resolves locale client-side, searches server-side with `contains`, and filters to jobs whose application deadline has not passed. Model reshaping is staged across two tasks so the app compiles and runs after every task.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, `appwrite` Dart SDK (`TablesDB`), `flutter_riverpod`, `equatable`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-07-appwrite-content-migration-design.md`

**Plan 2 of 4.** Plan 1 (shared content layer + events) is complete and merged into this branch. The shared layer is reused **unchanged** — do not modify it.

## Live data facts (verified 2026-09-08, not assumed)

| Fact | Value | Consequence |
|---|---|---|
| Published jobs | 252 | |
| Published **and still open** | **27** (16 on campus 1) | Deadline filtering is essential — without it users see 225 expired jobs |
| Nested `translations` returned | 100/100 sampled | `Query.select(['*','translations.*'])` works |
| **Locale coverage** | **73 `no`-only, 21 `en`-only, 6 both** | See below — this is the most important fact in this plan |
| `metadata.company` / `employment_type` / `location` | **null on all 100** | Do not surface as fields |
| `metadata.tags` | populated on 99/100 | The only useful metadata |
| `department_id` | **null on all 100** | No department linkage in practice |
| `additional_fields` | null everywhere | Ignore |
| `application_deadline` | present on all 100 | Safe to filter on, but nullable in schema |
| `description` | HTML | `jobs_screen.dart:780` already uses `toFullHtml` |

**The locale finding is decisive.** Only 6 of 100 sampled jobs have both locales. Filtering server-side by `translations.locale` would hide 73 jobs from an English user and 21 from a Norwegian one. The events corpus (3 events, all bilingual) could never have revealed this. Locale resolution stays client-side, and the resolver's fallback chain is load-bearing here in a way it was not for events.

## Global Constraints

- Database id via `AppConstants.databaseId`, never a literal.
- Public reads only; never require a session to browse.
- Always filter `Query.equal('status', 'published')`. The `jobs` status enum is `['draft','published','closed']`.
- Nested relationships require explicit selection: `Query.select(['*','translations.*'])`. Note jobs use **`translations`**, not `translation_refs`.
- **Never** filter by `translations.locale` — it narrows parent rows, not the nested array, and would hide most of the corpus (see above).
- Locale values are exactly `'en'` and `'no'`. Reuse `resolveLocalizedContent`; do not reimplement the fallback.
- **Never render a raw Appwrite enum value in the UI.** Plan 1 shipped a `published` badge to users this way; do not repeat it.
- `description` is HTML — render via `toFullHtml`, never a bare `Text`.
- **Every field added to a model must be added to `props`.** Plan 1 shipped an Equatable gap that silently suppressed Riverpod rebuilds; check deliberately.
- Reuse `ContentTranslation`, `resolveLocalizedContent`, `rowData` from `lib/core/utils/` and `lib/data/models/` **unchanged**.
- Never `git add -A` / `git add .` / `git commit -a` — the working tree carries unrelated WIP. Stage explicit paths.
- Run `flutter analyze` and `flutter test` before each commit.

---

### Task 1: JobModel.fromAppwriteRow

Additive only. Do NOT delete existing constructors or fields — Task 4 does that after callers are repointed.

**Files:**
- Modify: `lib/data/models/job_model.dart`
- Test: `test/data/models/job_model_appwrite_test.dart`

**Interfaces:**
- Consumes: `ContentTranslation.listFrom`, `resolveLocalizedContent` (shared layer, unchanged).
- Produces: `factory JobModel.fromAppwriteRow(Map<String, dynamic> row, {String locale = 'no'})`, plus new fields `final String? slug, shortDescription; final List<String> tags;`

- [ ] **Step 1: Write the failing test**

Payload is a real published `jobs` row captured from live Appwrite.

```dart
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

    test('two jobs differing only in a new field are not equal', () {
      final a = JobModel.fromAppwriteRow(realJobRow);
      final b = JobModel.fromAppwriteRow({
        ...realJobRow,
        'metadata': '{"tags":["Different"]}',
      });
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/job_model_appwrite_test.dart`
Expected: FAIL — `The method 'fromAppwriteRow' isn't defined for the type 'JobModel'`

- [ ] **Step 3: Write minimal implementation**

Add `slug`, `shortDescription` and `tags` to the field list, constructor and **`props`**, then add this factory.

`department`, `departmentId`, `campusId`, `category`, `startDate`, `url`, `applicationDeadline` and `contactPersonName` are still `required` on the current constructor but have no Appwrite column. Pass the interim values shown; Task 4 removes them.

```dart
  factory JobModel.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translations']);
    final content = resolveLocalizedContent(translations, locale);

    Map<String, dynamic> metadata = const {};
    final rawMetadata = row['metadata'];
    if (rawMetadata is String && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Malformed metadata must not sink the whole row.
        metadata = const {};
      }
    }

    final rawTags = metadata['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    DateTime? parseDate(Object? v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    // A missing deadline means "open-ended", NOT "expired". This is the
    // opposite of the events case, so the epoch sentinel used there would be
    // exactly wrong here — it would render an open-ended job as long expired.
    // Use a far-future sentinel until Task 4 makes the field nullable.
    final deadline = parseDate(row['application_deadline']);

    return JobModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      description: content.description,
      shortDescription: content.shortDescription,
      campusId: (row['campus_id'] ?? '').toString(),
      tags: tags,
      status: (row['status'] ?? 'published').toString(),
      applicationDeadline: deadline ?? _noDeadlineSentinel,
      metadata: metadata,
      // No Appwrite column; removed in Task 4.
      department: '',
      departmentId: (row['department_id'] ?? '').toString(),
      category: '',
      startDate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      url: '',
      contactPersonName: '',
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
    );
  }
```

Also add the sentinel as a private top-level constant in `job_model.dart`:

```dart
/// Stands in for "no application deadline" while [JobModel.applicationDeadline]
/// is still non-nullable. Far future, never the epoch: an open-ended job must
/// not read as long expired. Task 4 makes the field nullable and removes this.
final _noDeadlineSentinel = DateTime.utc(9999, 12, 31);
```

Add imports to `job_model.dart`:

```dart
import 'dart:convert';

import '../../core/utils/localized_content.dart';
import 'content_translation.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/job_model_appwrite_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter analyze && flutter test`
Expected: no new errors; all pre-existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/job_model.dart test/data/models/job_model_appwrite_test.dart
git commit -m "feat: parse jobs from Appwrite rows with nested translations"
```

---

### Task 2: JobService reads from Appwrite

**Files:**
- Modify: `lib/data/services/job_service.dart`
- Test: `test/data/services/job_service_query_test.dart`

**Interfaces:**
- Consumes: `JobModel.fromAppwriteRow` (Task 1), `rowData` from `lib/core/utils/appwrite_row.dart`.
- Produces: `static List<String> JobService.buildJobQueries({String? campusId, int limit, int offset, bool includeExpired, String? search, DateTime? now})`, `static List<String> JobService.buildJobCountQueries({String? campusId, bool includeExpired, DateTime? now})`, `Future<List<JobModel>> listJobs({...})`, `Future<int> countJobs({...})`.

Copy the structure of `EventService` (`lib/data/services/event_service.dart`) — shared `_jobFilters`, two builders on top. It is the reviewed precedent.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/services/job_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appwrite serialises each query to JSON, e.g.
/// `{"method":"limit","values":[20]}`. Matching the exact `"method":"x"`
/// fragment stops `contains` also matching `containsAny`/`containsAll`.
Matcher hasQuery(String method, {List<String> containing = const []}) {
  return predicate<List<String>>(
    (queries) => queries.any(
      (q) =>
          q.contains('"method":"$method"') &&
          containing.every((fragment) => q.contains(fragment)),
    ),
    'has a "$method" query containing ${containing.join(', ')}',
  );
}

void main() {
  group('JobService.buildJobQueries', () {
    test('always filters to published rows', () {
      expect(
        JobService.buildJobQueries(),
        hasQuery('equal', containing: ['status', 'published']),
      );
    });

    test('selects nested translations so they are returned', () {
      expect(
        JobService.buildJobQueries(),
        hasQuery('select', containing: ['translations.*']),
      );
    });

    test('never filters on translation locale', () {
      // 73% of live jobs are Norwegian-only and 21% English-only, so a
      // locale filter would hide most of the board from every user.
      final q = JobService.buildJobQueries();
      expect(q.any((s) => s.contains('translations.locale')), isFalse);
    });

    test('filters by campus when provided', () {
      expect(
        JobService.buildJobQueries(campusId: '1'),
        hasQuery('equal', containing: ['campus_id', '"1"']),
      );
    });

    test('omits the campus filter when campusId is null', () {
      expect(
        JobService.buildJobQueries().any((s) => s.contains('campus_id')),
        isFalse,
      );
    });

    test('hides jobs whose deadline has passed, keeping those with none', () {
      final q = JobService.buildJobQueries(now: DateTime.utc(2026, 9, 8));
      expect(
        q,
        hasQuery(
          'or',
          containing: [
            'application_deadline',
            '2026-09-08T00:00:00.000Z',
            'isNull',
          ],
        ),
      );
    });

    test('includeExpired drops the deadline window entirely', () {
      final q = JobService.buildJobQueries(
        includeExpired: true,
        now: DateTime.utc(2026, 9, 8),
      );
      expect(q.any((s) => s.contains('application_deadline')), isFalse);
    });

    test('searches server-side with contains on the translated title', () {
      expect(
        JobService.buildJobQueries(search: 'advisor'),
        hasQuery('contains', containing: ['translations.title', 'advisor']),
      );
    });

    test('omits the search clause for a blank term', () {
      expect(
        JobService.buildJobQueries(search: '   ').any(
          (s) => s.contains('translations.title'),
        ),
        isFalse,
      );
    });

    test('applies the requested limit and offset', () {
      final q = JobService.buildJobQueries(limit: 37, offset: 40);
      expect(q, hasQuery('limit', containing: ['37']));
      expect(q, hasQuery('offset', containing: ['40']));
    });
  });

  group('JobService.buildJobCountQueries', () {
    test('selects only the id rather than whole rows', () {
      expect(
        JobService.buildJobCountQueries(),
        hasQuery('select', containing: [r'$id']),
      );
      expect(
        JobService.buildJobCountQueries().any(
          (s) => s.contains('translations.*'),
        ),
        isFalse,
      );
    });

    test('uses the same deadline window as the list read', () {
      expect(
        JobService.buildJobCountQueries(now: DateTime.utc(2026, 9, 8)),
        hasQuery('or', containing: ['application_deadline']),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/services/job_service_query_test.dart`
Expected: FAIL — `The method 'buildJobQueries' isn't defined for the type 'JobService'`

- [ ] **Step 3: Write minimal implementation**

```dart
  /// The filter clauses every jobs read shares, list and count alike.
  ///
  /// Locale is intentionally absent: filtering `translations.locale`
  /// narrows parent rows rather than the nested array. 73% of live jobs
  /// are Norwegian-only and 21% English-only, so such a filter would hide
  /// most of the board from every user. Locale is resolved client-side.
  static List<String> _jobFilters({
    String? campusId,
    bool includeExpired = false,
    String? search,
    DateTime? now,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }

    if (!includeExpired) {
      final from = (now ?? DateTime.now().toUtc()).toIso8601String();
      // A job with no deadline is open-ended, not expired.
      queries.add(
        Query.or([
          Query.greaterThanEqual('application_deadline', from),
          Query.isNull('application_deadline'),
        ]),
      );
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translations.title', [term]));
    }

    return queries;
  }

  static List<String> buildJobQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
    DateTime? now,
  }) {
    return [
      ..._jobFilters(
        campusId: campusId,
        includeExpired: includeExpired,
        search: search,
        now: now,
      ),
      // Nested translations are only returned when explicitly selected.
      Query.select(['*', 'translations.*']),
      Query.orderAsc('application_deadline'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  static List<String> buildJobCountQueries({
    String? campusId,
    bool includeExpired = false,
    DateTime? now,
  }) {
    return [
      ..._jobFilters(
        campusId: campusId,
        includeExpired: includeExpired,
        now: now,
      ),
      Query.select([r'$id']),
      Query.limit(1),
    ];
  }

  Future<List<JobModel>> listJobs({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildJobQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        includeExpired: includeExpired,
        search: search,
      ),
    );

    return response.rows
        .map((row) => JobModel.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  Future<int> countJobs({
    String? campusId,
    bool includeExpired = false,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildJobCountQueries(
        campusId: campusId,
        includeExpired: includeExpired,
      ),
    );
    return response.total;
  }
```

Ensure `job_service.dart` imports `package:appwrite/appwrite.dart`, `../../core/constants/app_constants.dart`, `../../core/utils/appwrite_row.dart`, and `appwrite_service.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/services/job_service_query_test.dart`
Expected: PASS (12 tests)

- [ ] **Step 5: Verify against live Appwrite**

Run this and confirm it prints a total of roughly 27 (published and still open), far fewer than the 252 published overall:

```bash
curl -s -H "X-Appwrite-Project: biso" \
  "https://appwrite.biso.no/v1/tablesdb/app/tables/jobs/rows?queries%5B%5D=%7B%22method%22%3A%22equal%22%2C%22attribute%22%3A%22status%22%2C%22values%22%3A%5B%22published%22%5D%7D" \
  | python3 -c "import json,sys; print('published:', json.load(sys.stdin)['total'])"
```

- [ ] **Step 6: Commit**

```bash
git add lib/data/services/job_service.dart test/data/services/job_service_query_test.dart
git commit -m "feat: read jobs directly from Appwrite with deadline filtering"
```

---

### Task 3: Delete the HTTP jobs paths

**Files:**
- Modify: `lib/data/services/job_service.dart`
- Modify: `lib/data/services/campus_service.dart`
- Modify: `lib/presentation/screens/explore/jobs_screen.dart`
- Modify: `lib/presentation/screens/home/premium_home_screen.dart`

**Interfaces:**
- Consumes: `listJobs` / `countJobs` (Task 2).
- Produces: a `JobService` whose only read path is Appwrite.

- [ ] **Step 1: Find every caller**

```bash
grep -rn "getLatestJobs\|getJobsTotalCount\|fnFetchJobsId\|JobModel.fromWordPress\|fromFunctionJob" lib/ test/
```

Record the list; every hit must be repointed or deleted in this task.

- [ ] **Step 2: Repoint callers**

Replace each call with `listJobs(...)` / `countJobs(...)`. Pass the user's locale from `ref.watch(localeProvider).languageCode` where a `WidgetRef` is available; let the `'no'` default apply where it is not (e.g. `campus_service.dart`).

`campus_service.dart` must call `jobService.countJobs(...)` rather than issuing its own `db.listRows` — `EventService.countEvents` is the reviewed precedent.

- [ ] **Step 3: Delete the dead code**

Remove from `job_service.dart`: `getLatestJobs`, `getJobsTotalCount`, `_preview`, `_applyCampusFilterAndPaging`/`_matchesCampus`/`_campusMatchers`/`_metadataStrings` if their only callers were the deleted methods, and any now-unused `http` / `functions` / `dart:convert` imports.

Remove from `job_model.dart` any WordPress-only constructors and the private helpers only they use.

Remove `fnFetchJobsId` from `lib/core/constants/app_constants.dart` if unused.

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: no errors, no references to removed symbols, all tests pass.

Run: `grep -rn "getLatestJobs\|getJobsTotalCount\|fnFetchJobsId" lib/` — expected: no hits.

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/job_service.dart lib/data/services/campus_service.dart \
        lib/presentation/screens/explore/jobs_screen.dart \
        lib/presentation/screens/home/premium_home_screen.dart \
        lib/core/constants/app_constants.dart
git commit -m "refactor: remove api.biso.no jobs fetch path"
```

---

### Task 4: Remove superseded JobModel fields

**Files:**
- Modify: `lib/data/models/job_model.dart`
- Modify: consuming screens surfaced by `flutter analyze`

- [ ] **Step 1: Remove the fields with no Appwrite column**

`department`, `departmentLogo`, `type`, `category`, `requirements`, `responsibilities`, `skills`, `salary`, `timeCommitment`, `startDate`, `url`, `endDate`, `applicationMethod`, `applicationUrl`, `applicationEmail`, `contactPersonName`, `contactPersonEmail`, `contactPersonPhone`, `maxApplicants`, `currentApplicants`, `isUrgent`, `isFeatured`, `benefits`

Verified against live data: `metadata.company`, `metadata.employment_type` and `metadata.location` are null on all 100 sampled jobs, and `department_id` is null on all of them, so none of these can be populated from the backend.

Keep: `id`, `slug`, `title`, `description`, `shortDescription`, `campusId`, `departmentId`, `tags`, `status`, `applicationDeadline`, `metadata`, `createdAt`, `updatedAt`.

**Also make `applicationDeadline` nullable** (`DateTime?`) and delete the
`_noDeadlineSentinel` constant introduced in Task 1, updating
`fromAppwriteRow` to pass `deadline` directly. `application_deadline` is
`required=False` in the schema, and a null deadline means open-ended. Fix the
consuming UI to omit the deadline line when it is null rather than printing a
sentinel date. Add a test asserting a row with no `application_deadline`
yields `null`.

Update `props` to match the surviving field list exactly.

**Do NOT touch types that merely share member names.** These files use `.benefits`, `.category` etc. on OTHER classes and must not be modified: `lib/data/models/campus_model.dart`, `lib/data/models/membership_model.dart`, `lib/presentation/widgets/membership_purchase_modal.dart`, `lib/schema/appwrite/funding_programs.dart`, `lib/presentation/widgets/premium/wonderous_story_card.dart`, `lib/presentation/screens/explore/campus_detail_components.dart` (verify each hit is a `JobModel` before editing).

- [ ] **Step 2: Let the compiler find consumers**

Run: `flutter analyze`
Expected: errors in `jobs_screen.dart` (14 usages) and possibly `premium_home_screen.dart`. Fix each.

Do not invent data to keep a widget alive. If a UI element existed only to show a field with no remaining source, remove that element and report it. Do not render a raw `status` enum value — derive any badge from the deadline instead.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: no errors, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/data/models/job_model.dart lib/presentation/screens/explore/jobs_screen.dart \
        lib/presentation/screens/home/premium_home_screen.dart
git commit -m "refactor: drop JobModel fields with no Appwrite column"
```

---

## Verification

- `flutter analyze` reports no errors; `flutter test` passes.
- The jobs board renders open jobs with real titles, in the user's locale where available and the other locale where not.
- An English-only job is visible to a Norwegian user (this is the majority case, not an edge case).
- Expired jobs are absent unless `includeExpired` is set.
- No raw `status` enum value appears in the UI.
- `grep -rn "api.biso.no" lib/` shows hits only in expense code.

## Follow-on plans

3. Webshop products, variations and custom fields.
4. Screen audit across home, explore, marketplace and detail screens.
