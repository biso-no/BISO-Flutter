# Shared Content Layer + Events Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared Appwrite content layer (translations, locale resolution, image normalization) and migrate events off `api.biso.no` onto direct Appwrite reads.

**Architecture:** Three small pure units form a shared layer that jobs and webshop will reuse in later plans. `EventService` then reads `events` from Appwrite in one round trip with translations nested via `Query.select`, resolves locale client-side, and searches server-side with `contains`. Model reshaping is staged so the app compiles and runs after every task.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, `appwrite` Dart SDK (`TablesDB`), `flutter_riverpod`, `equatable`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-07-appwrite-content-migration-design.md`

## Global Constraints

- Database id is `app` — always reference `AppConstants.databaseId`, never a literal.
- Public reads only; never require a session for browsing content.
- Always filter list reads with `Query.equal('status', 'published')` — drafts have `$permissions: []` and are unreadable publicly.
- Nested relationships are absent unless explicitly selected via `Query.select(['*', 'translation_refs.*'])`.
- Never filter by `translation_refs.locale` to select a locale — it filters parent rows, not the nested array, and silently drops rows lacking that locale.
- Locale values are exactly `'en'` and `'no'`. Locale fallback order: requested → `'no'` → `'en'` → first available → empty.
- `content_translations.description` is HTML and must not be rendered as plain text.
- Image columns hold either a bare file ID or a full URL; both must be handled. Storage bucket is `media`.
- Expenses stay on `api.biso.no` — do not modify any expense code.
- Run `flutter analyze` before each commit; it must report no new errors.

---

### Task 1: ContentTranslation model

**Files:**
- Create: `lib/data/models/content_translation.dart`
- Test: `test/data/models/content_translation_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class ContentTranslation` with `final String locale, title, description, contentType, contentId; final String? shortDescription, additionalFields;` and `factory ContentTranslation.fromMap(Map<String, dynamic> map)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/models/content_translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentTranslation.fromMap', () {
    test('parses a real content_translations row', () {
      final t = ContentTranslation.fromMap({
        'content_id': 'wpprod37313',
        'locale': 'en',
        'title': 'Booklocker - Campus Oslo',
        'description': '<p>Pick a locker.</p>',
        'short_description': 'Pick a locker.',
        'additional_fields': null,
        'content_type': 'product',
      });

      expect(t.locale, 'en');
      expect(t.title, 'Booklocker - Campus Oslo');
      expect(t.description, '<p>Pick a locker.</p>');
      expect(t.shortDescription, 'Pick a locker.');
      expect(t.contentType, 'product');
      expect(t.contentId, 'wpprod37313');
      expect(t.additionalFields, isNull);
    });

    test('defaults missing strings to empty rather than throwing', () {
      final t = ContentTranslation.fromMap({'locale': 'no'});

      expect(t.locale, 'no');
      expect(t.title, '');
      expect(t.description, '');
      expect(t.shortDescription, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/content_translation_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:biso/data/models/content_translation.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:equatable/equatable.dart';

/// A single localized row from the `content_translations` table.
class ContentTranslation extends Equatable {
  final String locale;
  final String title;
  final String description;
  final String? shortDescription;
  final String? additionalFields;
  final String contentType;
  final String contentId;

  const ContentTranslation({
    required this.locale,
    required this.title,
    required this.description,
    this.shortDescription,
    this.additionalFields,
    this.contentType = '',
    this.contentId = '',
  });

  factory ContentTranslation.fromMap(Map<String, dynamic> map) {
    return ContentTranslation(
      locale: (map['locale'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      shortDescription: map['short_description']?.toString(),
      additionalFields: map['additional_fields']?.toString(),
      contentType: (map['content_type'] ?? '').toString(),
      contentId: (map['content_id'] ?? '').toString(),
    );
  }

  /// Parses a nested relationship array such as `translation_refs`.
  static List<ContentTranslation> listFrom(Object? value) {
    if (value is! List) return const <ContentTranslation>[];
    return value
        .whereType<Map>()
        .map((e) => ContentTranslation.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [
    locale,
    title,
    description,
    shortDescription,
    additionalFields,
    contentType,
    contentId,
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/content_translation_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/content_translation.dart test/data/models/content_translation_test.dart
git commit -m "feat: add ContentTranslation model for Appwrite content_translations"
```

---

### Task 2: Locale resolver

**Files:**
- Create: `lib/core/utils/localized_content.dart`
- Test: `test/core/utils/localized_content_test.dart`

**Interfaces:**
- Consumes: `ContentTranslation` from Task 1.
- Produces: `class LocalizedContent` with `final String title, description; final String? shortDescription;` and top-level `LocalizedContent resolveLocalizedContent(List<ContentTranslation> translations, String locale)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/utils/localized_content.dart';
import 'package:biso/data/models/content_translation.dart';
import 'package:flutter_test/flutter_test.dart';

ContentTranslation t(String locale, String title) => ContentTranslation(
  locale: locale,
  title: title,
  description: '<p>$title</p>',
  shortDescription: title,
);

void main() {
  group('resolveLocalizedContent', () {
    final both = [t('no', 'Karrieredagene'), t('en', 'Career Days')];

    test('returns the requested locale when present', () {
      expect(resolveLocalizedContent(both, 'en').title, 'Career Days');
      expect(resolveLocalizedContent(both, 'no').title, 'Karrieredagene');
    });

    test('falls back to Norwegian when the requested locale is missing', () {
      expect(resolveLocalizedContent(both, 'de').title, 'Karrieredagene');
    });

    test('falls back to English when Norwegian is absent', () {
      final onlyEn = [t('en', 'Career Days')];
      expect(resolveLocalizedContent(onlyEn, 'no').title, 'Career Days');
    });

    test('falls back to the first available for an unexpected locale', () {
      final odd = [t('fr', 'Journees')];
      expect(resolveLocalizedContent(odd, 'no').title, 'Journees');
    });

    test('returns empty content rather than throwing when list is empty', () {
      final r = resolveLocalizedContent(const [], 'no');
      expect(r.title, '');
      expect(r.description, '');
      expect(r.shortDescription, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/localized_content_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:biso/core/utils/localized_content.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
import '../../data/models/content_translation.dart';

/// Title and description resolved for one locale.
class LocalizedContent {
  final String title;
  final String description;
  final String? shortDescription;

  const LocalizedContent({
    required this.title,
    required this.description,
    this.shortDescription,
  });

  static const empty = LocalizedContent(title: '', description: '');
}

/// Picks the best translation for [locale].
///
/// Locale selection is deliberately client-side. Filtering by
/// `translation_refs.locale` in Appwrite narrows parent rows rather than the
/// nested array, which would silently hide content lacking that locale.
///
/// Fallback order: requested -> 'no' -> 'en' -> first available -> empty.
LocalizedContent resolveLocalizedContent(
  List<ContentTranslation> translations,
  String locale,
) {
  if (translations.isEmpty) return LocalizedContent.empty;

  ContentTranslation? pick(String wanted) {
    for (final t in translations) {
      if (t.locale == wanted) return t;
    }
    return null;
  }

  final chosen =
      pick(locale) ?? pick('no') ?? pick('en') ?? translations.first;

  return LocalizedContent(
    title: chosen.title,
    description: chosen.description,
    shortDescription: chosen.shortDescription,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/localized_content_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/localized_content.dart test/core/utils/localized_content_test.dart
git commit -m "feat: add locale resolver with no/en fallback chain"
```

---

### Task 3: Appwrite image normalization

**Files:**
- Create: `lib/core/utils/appwrite_image.dart`
- Test: `test/core/utils/appwrite_image_test.dart`

**Interfaces:**
- Consumes: `AppConstants.appwriteEndpoint`, `AppConstants.appwriteProjectId`.
- Produces: `String? appwriteImageUrl(Object? value, {String bucketId = 'media'})` and `List<String> appwriteImageUrls(Object? value, {String bucketId = 'media'})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/utils/appwrite_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appwriteImageUrl', () {
    test('passes through an existing full URL unchanged', () {
      const url =
          'https://appwrite.biso.no/v1/storage/buckets/media/files/abc/view?project=biso';
      expect(appwriteImageUrl(url), url);
    });

    test('builds a view URL from a bare file id', () {
      final r = appwriteImageUrl('6a99004100362c968d1e');
      expect(r, contains('/storage/buckets/media/files/6a99004100362c968d1e/view'));
      expect(r, contains('project=biso'));
    });

    test('returns null for null or empty input', () {
      expect(appwriteImageUrl(null), isNull);
      expect(appwriteImageUrl(''), isNull);
      expect(appwriteImageUrl('   '), isNull);
    });
  });

  group('appwriteImageUrls', () {
    test('normalizes a mixed list of ids and URLs', () {
      const url =
          'https://appwrite.biso.no/v1/storage/buckets/media/files/xyz/view?project=biso';
      final r = appwriteImageUrls([url, '6a99004100362c968d1e', '', null]);

      expect(r.length, 2);
      expect(r.first, url);
      expect(r.last, contains('6a99004100362c968d1e'));
    });

    test('returns empty list for a non-list value', () {
      expect(appwriteImageUrls(null), isEmpty);
      expect(appwriteImageUrls('not-a-list'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/appwrite_image_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:biso/core/utils/appwrite_image.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
import '../constants/app_constants.dart';

/// Normalizes an Appwrite image value into a usable URL.
///
/// Live data stores either a bare file id or an already-complete view URL in
/// the same column, so both forms must be accepted.
String? appwriteImageUrl(Object? value, {String bucketId = 'media'}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

  return '${AppConstants.appwriteEndpoint}/storage/buckets/$bucketId'
      '/files/$raw/view?project=${AppConstants.appwriteProjectId}';
}

/// Normalizes a list column such as `images`, dropping unusable entries.
List<String> appwriteImageUrls(Object? value, {String bucketId = 'media'}) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => appwriteImageUrl(e, bucketId: bucketId))
      .whereType<String>()
      .toList(growable: false);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/appwrite_image_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/appwrite_image.dart test/core/utils/appwrite_image_test.dart
git commit -m "feat: normalize Appwrite image ids and URLs"
```

---

### Task 4: EventModel.fromAppwriteRow

Adds the Appwrite constructor and new schema-backed fields **without removing**
existing fields, so every screen still compiles. Removal happens in Task 7.

**Files:**
- Modify: `lib/data/models/event_model.dart`
- Test: `test/data/models/event_model_appwrite_test.dart`

**Interfaces:**
- Consumes: `ContentTranslation` (Task 1), `resolveLocalizedContent` (Task 2), `appwriteImageUrl` (Task 3).
- Produces: `factory EventModel.fromAppwriteRow(Map<String, dynamic> row, {String locale = 'no'})`, plus new fields on `EventModel`: `final String? slug, shortDescription, ticketUrl, locationMode, onlineUrl, category, coverPattern, pricingMode, departmentId, contactName, contactRole, contactEmail; final double? memberPrice; final bool memberOnly, waitlist; final int capacity; final List<String> tags;`

- [ ] **Step 1: Write the failing test**

Payload below is a real published `events` row captured from live Appwrite.

```dart
import 'package:biso/data/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> get realEventRow => {
  r'$id': 'evt_kd',
  'slug': 'kd',
  'status': 'published',
  'campus_id': '1',
  'department_id': '25',
  'start_date': '2026-09-22T10:00:00.000+00:00',
  'end_date': '2026-09-24T16:00:00.000+00:00',
  'image':
      'https://appwrite.biso.no/v1/storage/buckets/media/files/6a8b12f80004a404560c/view?project=biso',
  'price': null,
  'member_price': null,
  'pricing_mode': 'free',
  'member_only': false,
  'location': 'BI Oslo',
  'location_mode': 'physical',
  'capacity': 5000,
  'waitlist': false,
  'category': 'career',
  'cover_pattern': 'dotted',
  'tags': ['Networking', 'Free', 'Career'],
  'ticket_url': null,
  'translation_refs': [
    {
      'locale': 'no',
      'title': 'Karrieredagene',
      'description': '<p>Bli med.</p>',
      'short_description': 'Bli med.',
      'content_type': 'event',
    },
    {
      'locale': 'en',
      'title': 'Carreer Days',
      'description': '<p>Join us.</p>',
      'short_description': 'Join us.',
      'content_type': 'event',
    },
  ],
};

void main() {
  group('EventModel.fromAppwriteRow', () {
    test('parses scalar columns from a real row', () {
      final e = EventModel.fromAppwriteRow(realEventRow);

      expect(e.id, 'evt_kd');
      expect(e.slug, 'kd');
      expect(e.campusId, '1');
      expect(e.departmentId, '25');
      expect(e.location, 'BI Oslo');
      expect(e.locationMode, 'physical');
      expect(e.capacity, 5000);
      expect(e.category, 'career');
      expect(e.tags, ['Networking', 'Free', 'Career']);
      expect(e.pricingMode, 'free');
      expect(e.memberOnly, isFalse);
      expect(e.startDate, DateTime.parse('2026-09-22T10:00:00.000+00:00'));
      expect(e.endDate, DateTime.parse('2026-09-24T16:00:00.000+00:00'));
    });

    test('resolves title and description for the requested locale', () {
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'en').title,
          'Carreer Days');
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'no').title,
          'Karrieredagene');
    });

    test('falls back to Norwegian for an unknown locale', () {
      expect(EventModel.fromAppwriteRow(realEventRow, locale: 'de').title,
          'Karrieredagene');
    });

    test('keeps a full image URL intact', () {
      expect(EventModel.fromAppwriteRow(realEventRow).images.single,
          contains('6a8b12f80004a404560c'));
    });

    test('normalizes a bare image file id into a URL', () {
      final row = {...realEventRow, 'image': '6a8b12f80004a404560c'};
      expect(EventModel.fromAppwriteRow(row).images.single,
          contains('/storage/buckets/media/files/6a8b12f80004a404560c/view'));
    });

    test('tolerates a row with no translations', () {
      final row = {...realEventRow}..remove('translation_refs');
      final e = EventModel.fromAppwriteRow(row);

      expect(e.title, '');
      expect(e.description, '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/event_model_appwrite_test.dart`
Expected: FAIL — `The method 'fromAppwriteRow' isn't defined for the type 'EventModel'`

- [ ] **Step 3: Write minimal implementation**

Add the new fields to the `EventModel` field list and constructor as optional
parameters with the defaults shown, then add this factory. Do **not** delete
`fromWordPress` / `fromFunctionEvent` yet — Task 5 removes their callers first.

```dart
  // --- new schema-backed fields (add to field list + constructor) ---
  // final String? slug, shortDescription, ticketUrl, locationMode, onlineUrl;
  // final String? category, coverPattern, pricingMode, departmentId;
  // final String? contactName, contactRole, contactEmail;
  // final double? memberPrice;
  // final bool memberOnly, waitlist;
  // final int capacity;
  // final List<String> tags;

  factory EventModel.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translation_refs']);
    final content = resolveLocalizedContent(translations, locale);
    final image = appwriteImageUrl(row['image']);

    DateTime? parseDate(Object? v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return EventModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      // `venue`, `organizerId` and `organizerName` are still `required` on the
      // constructor at this point. They have no Appwrite column and Task 7
      // removes them; pass interim values so this task compiles.
      venue: (row['location'] ?? '').toString(),
      organizerId: '',
      organizerName: '',
      title: content.title,
      description: content.description,
      shortDescription: content.shortDescription,
      startDate: parseDate(row['start_date']) ?? DateTime.now(),
      endDate: parseDate(row['end_date']),
      registrationDeadline: parseDate(row['registration_deadline']),
      campusId: (row['campus_id'] ?? '').toString(),
      departmentId: row['department_id']?.toString(),
      location: row['location']?.toString(),
      locationMode: row['location_mode']?.toString(),
      onlineUrl: row['online_url']?.toString(),
      images: image == null ? const <String>[] : <String>[image],
      price: (row['price'] as num?)?.toDouble(),
      memberPrice: (row['member_price'] as num?)?.toDouble(),
      pricingMode: row['pricing_mode']?.toString(),
      memberOnly: row['member_only'] == true,
      capacity: (row['capacity'] as num?)?.toInt() ?? 0,
      waitlist: row['waitlist'] == true,
      category: row['category']?.toString(),
      coverPattern: row['cover_pattern']?.toString(),
      tags: (row['tags'] is List)
          ? (row['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      ticketUrl: row['ticket_url']?.toString(),
      contactName: row['contact_name']?.toString(),
      contactRole: row['contact_role']?.toString(),
      contactEmail: row['contact_email']?.toString(),
      status: (row['status'] ?? 'published').toString(),
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
    );
  }
```

Add these imports to `event_model.dart`:

```dart
import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/event_model_appwrite_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter analyze && flutter test`
Expected: analyze reports no new errors; all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/event_model.dart test/data/models/event_model_appwrite_test.dart
git commit -m "feat: parse events from Appwrite rows with nested translations"
```

---

### Task 5: EventService reads from Appwrite

**Files:**
- Modify: `lib/data/services/event_service.dart`
- Test: `test/data/services/event_service_query_test.dart`

**Interfaces:**
- Consumes: `EventModel.fromAppwriteRow` (Task 4).
- Produces: `Future<List<EventModel>> EventService.listEvents({String? campusId, String locale = 'no', int limit = 20, int offset = 0, bool includePast = false, String? search})` and the testable helper `static List<String> buildEventQueries({String? campusId, int limit = 20, int offset = 0, bool includePast = false, String? search, DateTime? now})`.

Extracting query construction into a pure static function lets the query shape
be tested without a network call or an Appwrite mock.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/services/event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventService.buildEventQueries', () {
    test('always filters to published rows', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('status') && s.contains('published')), isTrue);
    });

    test('selects nested translations so they are returned', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('translation_refs.*')), isTrue);
    });

    test('never filters on translation locale', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('translation_refs.locale')), isFalse);
    });

    test('filters by campus when provided', () {
      final q = EventService.buildEventQueries(campusId: '1');
      expect(q.any((s) => s.contains('campus_id') && s.contains('"1"')), isTrue);
    });

    test('omits the campus filter when campusId is null', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('campus_id')), isFalse);
    });

    test('searches server-side with contains on the translated title', () {
      final q = EventService.buildEventQueries(search: 'dagene');
      expect(
        q.any((s) => s.contains('contains') && s.contains('translation_refs.title')),
        isTrue,
      );
    });

    test('excludes past events unless includePast is set', () {
      final now = DateTime.utc(2026, 9, 7);
      final upcoming = EventService.buildEventQueries(now: now);
      expect(
        upcoming.any(
          (s) => s.contains('greaterThanEqual') && s.contains('start_date'),
        ),
        isTrue,
      );

      final all = EventService.buildEventQueries(includePast: true, now: now);
      expect(
        all.any((s) => s.contains('greaterThanEqual') && s.contains('start_date')),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/services/event_service_query_test.dart`
Expected: FAIL — `The method 'buildEventQueries' isn't defined for the type 'EventService'`

- [ ] **Step 3: Write minimal implementation**

Add to `EventService`:

```dart
  /// Builds the query list for an events read.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// events that lack that locale. Locale is resolved client-side instead.
  static List<String> buildEventQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
    DateTime? now,
  }) {
    final queries = <String>[
      Query.equal('status', 'published'),
      Query.select(['*', 'translation_refs.*']),
    ];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }

    if (!includePast) {
      final from = (now ?? DateTime.now().toUtc()).toIso8601String();
      queries.add(Query.greaterThanEqual('start_date', from));
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translation_refs.title', [term]));
    }

    queries
      ..add(Query.orderAsc('start_date'))
      ..add(Query.limit(limit))
      ..add(Query.offset(offset));

    return queries;
  }

  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'events',
      queries: buildEventQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        includePast: includePast,
        search: search,
      ),
    );

    return response.rows
        .map((row) => EventModel.fromAppwriteRow(_rowData(row), locale: locale))
        .toList(growable: false);
  }

  Map<String, dynamic> _rowData(Row row) => {
    ...row.data,
    r'$id': row.$id,
    r'$createdAt': row.$createdAt,
    r'$updatedAt': row.$updatedAt,
  };
```

Ensure `event_service.dart` imports `package:appwrite/appwrite.dart`,
`package:appwrite/models.dart`, `appwrite_service.dart` and `app_constants.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/services/event_service_query_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Verify against live Appwrite**

Run this and confirm it prints 3 published events with both locales nested:

```bash
curl -s -H "X-Appwrite-Project: biso" \
  "https://appwrite.biso.no/v1/tablesdb/app/tables/events/rows?queries%5B%5D=%7B%22method%22%3A%22select%22%2C%22values%22%3A%5B%22*%22%2C%22translation_refs.*%22%5D%7D&queries%5B%5D=%7B%22method%22%3A%22equal%22%2C%22attribute%22%3A%22status%22%2C%22values%22%3A%5B%22published%22%5D%7D" \
  | python3 -m json.tool | head -20
```

- [ ] **Step 6: Commit**

```bash
git add lib/data/services/event_service.dart test/data/services/event_service_query_test.dart
git commit -m "feat: read events directly from Appwrite with server-side search"
```

---

### Task 6: Delete the HTTP and WordPress event paths

**Files:**
- Modify: `lib/data/services/event_service.dart`
- Modify: `lib/data/models/event_model.dart`
- Modify: `lib/core/constants/app_constants.dart:37`
- Delete: `test/data/models/event_model_test.dart`
- Modify: any caller surfaced by `flutter analyze`

**Interfaces:**
- Consumes: `EventService.listEvents` (Task 5).
- Produces: an `EventService` whose only read path is Appwrite.

- [ ] **Step 1: Find every caller of the paths being deleted**

```bash
grep -rn "getFunctionEvents\|getWordPressEvents\|fromWordPress\|fromFunctionEvent\|wordPressEventsApi\|getAppwriteEvents\|getAllEvents" lib/ test/
```

Record the list; every hit must be updated or deleted in this task.

- [ ] **Step 2: Repoint callers to listEvents**

Replace each call site with `listEvents(...)`, passing the user's locale from
`ref.watch(localeProvider).languageCode` where a `WidgetRef` is available and
`'no'` otherwise.

- [ ] **Step 3: Delete the dead code**

Remove from `event_service.dart`: `getWordPressEvents`, `getFunctionEvents`,
`getAppwriteEvents`, `getAllEvents`, `getEventsTotalCount`, `_preview`, and any
now-unused `http` / `functions` imports.

Remove from `event_model.dart`: `fromWordPress`, `fromFunctionEvent` and every
private WordPress helper they alone use.

Remove `wordPressEventsApi` from `app_constants.dart:37`.

Delete `test/data/models/event_model_test.dart` — it tests only the removed
WordPress constructors, and Task 4 already replaced its coverage.

- [ ] **Step 4: Verify the build is clean**

Run: `flutter analyze && flutter test`
Expected: no errors, no references to removed symbols, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove WordPress and api.biso.no event fetch paths"
```

---

### Task 7: Remove superseded EventModel fields

**Files:**
- Modify: `lib/data/models/event_model.dart`
- Modify: consuming screens surfaced by `flutter analyze`

**Interfaces:**
- Consumes: everything from Tasks 4-6.
- Produces: an `EventModel` whose every field maps to a real Appwrite column.

- [ ] **Step 1: List the fields to remove**

These have no column in the `events` table and can only ever be empty:
`venue`, `organizerId`, `organizerName`, `organizerLogo`, `categories`,
`maxAttendees`, `currentAttendees`, `isPublic`, `requiresRegistration`,
`registrationUrl`.

Mapping for consumers: `venue` → `location`, `categories` → `category` + `tags`,
`maxAttendees` → `capacity`, `registrationUrl` → `ticketUrl`.

- [ ] **Step 2: Remove them and let the compiler find consumers**

Run: `flutter analyze`
Expected: errors at each screen still referencing a removed field. Fix each
using the mapping above.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: no errors, all tests pass.

- [ ] **Step 4: Run the app and confirm events render**

```bash
flutter run -d <simulator-udid>
```

Confirm the home screen events section renders the 3 published events with
titles (not blank), and that switching app language changes the titles.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: drop EventModel fields with no Appwrite column"
```

---

## Verification

After Task 7 the following must all hold:

- `flutter analyze` reports no errors.
- `flutter test` passes, including the new content-layer tests.
- The home and events screens render the 3 published events with real titles.
- Switching language between Norwegian and English changes event titles.
- No reference to `api.biso.no` or WordPress remains in the events path:
  `grep -rn "wordpress\|wp-json\|getFunctionEvents" lib/` returns nothing.

## Follow-on plans

Written only after this plan lands and is verified:

2. Jobs migration — reuses Tasks 1-3 unchanged.
3. Webshop products, variations and custom fields.
4. Screen audit across home, explore, marketplace and detail screens.
