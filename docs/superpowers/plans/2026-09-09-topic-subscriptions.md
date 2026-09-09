# Topic Subscriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Appwrite Messaging topic subscriptions work end-to-end, so a student can choose topics once and actually receive the pushes they asked for.

**Architecture:** Four user-facing logical topics (`news`, `events`, `jobs`, `shop`) expand into campus-scoped Appwrite topic ids (`events_oslo`, `events_national`, …) derived from the profile campus, plus one always-on `general` topic. Per-user *intent* lives in Appwrite account preferences; per-device Appwrite subscriber ids live in device-local `SharedPreferences`. A single idempotent `reconcile()` diffs desired against current and is the only thing that ever creates or deletes a subscription.

**Tech Stack:** Flutter 3.32.8 / Dart 3.8.1, `appwrite` Dart SDK 26.1.0, `flutter_riverpod` 2.6.1, `shared_preferences` 2.5.3, `firebase_messaging` 16.2.0. Admin side: Next.js, `node-appwrite`, Biome, vitest.

**Spec:** `docs/superpowers/specs/2026-09-09-topic-subscriptions-design.md` (in this repo)

**Repos:** This plan spans two working directories.
- `/Users/markus/Documents/dev/BISO-Flutter` — Tasks 1–9, 12
- `/Users/markus/Documents/dev/BISO-Sites` — Tasks 1, 10, 11, 12

## Global Constraints

- **FCM messaging provider `$id` is `push`.** Never `fcm`. This is the single most important literal in the plan — the current bug is that it says `fcm`.
- **SMTP provider `$id` is `6aa0ed61002bb5023dfa`.** Not used in this plan (spec 2), listed so it is not invented elsewhere.
- **Campus ids are strings**: `'1'` Oslo, `'2'` Bergen, `'3'` Trondheim, `'4'` Stavanger, `'5'` National. `UserModel.campusId` is `String?` and may legitimately be null.
- **Topic id format:** `<logical>_<campusSlug>`, plus the bare `general`. Slugs are `oslo`, `bergen`, `trondheim`, `stavanger`, `national`. Any unknown or null campus id maps to `national`.
- **The client Appwrite SDK cannot list subscribers.** Only `createSubscriber` and `deleteSubscriber` exist. Never write code that tries to read subscriptions back from Appwrite.
- **Never swallow an Appwrite error into a generic string.** Every `catch` logs the actual exception (code and message). The bug this plan fixes hid for months behind a generic `debugPrint`.
- **Dart tests use hand-written fakes**, not mockito/mocktail — neither is a dependency. Subclass the Appwrite service and override the method, following `test/data/services/notification_service_retry_test.dart`.
- **Run Flutter tests with** `flutter test <path>` from `/Users/markus/Documents/dev/BISO-Flutter`.
- **Never re-serialise a config file.** Neither `appwrite.config.json` survives a JSON round-trip: the Sites one is Biome-formatted (short arrays stay on one line, and it uses 2-space indent to Flutter's 4), and the Flutter one holds float literals like `1.0e+19` that Python rewrites as `1e+19`. Both differences are invisible to JSON and both bury a 105-line change in a five-figure diff. Edit the topics array as text (Tasks 1 and 12 carry the tool). Always check `git diff --stat` before committing: an add must show zero deletions, a removal zero insertions.
- **Rollout order is load-bearing.** Task 1 *adds* topics; Task 12 *removes* the old ones, and only after Tasks 10–11 have shipped. Removing them earlier breaks live event pushes.

## File Structure

**BISO-Flutter — created**

| File | Responsibility |
|---|---|
| `lib/core/constants/notification_topics.dart` | The taxonomy: logical topics, campus slug map, topic-id derivation. Pure, no I/O. |
| `lib/data/services/topic_reconciler.dart` | The reconcile diff and legacy-intent migration. Pure, no I/O. |
| `lib/data/services/device_subscription_store.dart` | Device-local persistence of push target id + subscriber ids. |
| `lib/presentation/widgets/notification_topics_prompt.dart` | The first-run sheet. |
| `test/core/constants/notification_topics_test.dart` | Tests for the taxonomy. |
| `test/data/services/topic_reconciler_test.dart` | Tests for the diff and migration. |
| `test/data/services/device_subscription_store_test.dart` | Tests for device-local storage. |
| `test/data/services/notification_service_target_test.dart` | Tests for push-target resolution. |

**BISO-Flutter — modified**

| File | Change |
|---|---|
| `lib/data/services/notification_service.dart` | Target resolution, `reconcile()`, intent persistence, logout cleanup. |
| `lib/providers/notification/notification_provider.dart` | Await loaded intent; expose intent + reconcile. |
| `lib/presentation/screens/profile/settings_screen.dart` | Loop over the taxonomy; drop the expenses toggle. |
| `lib/presentation/screens/onboarding/onboarding_screen.dart` | Delete the dead notification step. |
| `lib/main.dart` | Mount the first-run gate. |
| `appwrite.config.json` | Topics. |

**BISO-Sites — created**

| File | Responsibility |
|---|---|
| `packages/shared/utils/notification-topics.ts` | Mirror of the Flutter taxonomy for server-side senders. |
| `packages/shared/utils/notification-topics.test.ts` | Tests for it. |
| `apps/admin/src/lib/notifications/topic-subscribers.ts` | Cached subscriber counts. |
| `apps/admin/src/lib/notifications/topic-subscribers.test.ts` | Tests for it. |

**BISO-Sites — modified**

| File | Change |
|---|---|
| `apps/admin/src/app/(portal)/_actions/events.ts` | `EVENTS_PUSH_TOPIC_ID` → derived per campus. |
| `apps/admin/src/lib/announcements/send.ts` | `DEFAULT_BROADCAST_TOPIC` → `general`. |
| `apps/admin/src/app/(portal)/events/[id]/page.tsx` | Fetch the real subscriber count. |
| `apps/admin/src/app/(portal)/events/[id]/_components/event-studio-editor.tsx` | Consume it; delete `PUSH_FOLLOWERS`. |
| `packages/api/appwrite.config.json` | Topics. |

---

### Task 1: Add the new topics to Appwrite config (both repos)

Purely additive. The five existing topics stay for now so nothing breaks mid-rollout; Task 12 removes them once every consumer has shipped.

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/packages/api/appwrite.config.json`

**Interfaces:**
- Consumes: nothing.
- Produces: 21 Appwrite topic ids — `general`, and `{news,events,jobs,shop}_{oslo,bergen,trondheim,stavanger,national}`. Every later task depends on these existing.

- [ ] **Step 1: Write the topics editor**

The two configs are formatted differently and neither survives a JSON
round-trip: the Sites config is Biome-formatted (short arrays stay on one
line) and the Flutter config contains float literals (`1.0e+19`) that
Python renormalises to `1e+19`. Both differences are invisible to JSON but
turn a 105-line addition into a five-figure diff. This script edits the
topics array as text, so every byte outside it is untouched by construction,
and it refuses to write anything that does not parse as JSON.

```bash
mkdir -p /Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions
cat > /Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions/topics_edit.py <<'TOPICS_EDIT_EOF'
"""Add or remove Appwrite topics by editing the config TEXT, never re-serialising it.

Round-tripping these configs through json.dump rewrites unrelated content: it
expands Biome's single-line arrays in the Sites config, and renormalises float
literals (1.0e+19 -> 1e+19) in the Flutter one. Both are invisible to JSON
semantics and both bury the real change in a 10,000-line diff. Editing text
directly leaves every byte outside the topics array untouched by construction.

Usage:  topics_edit.py add    CONFIG
        topics_edit.py remove CONFIG
"""
import json
import re
import sys

CAMPUS = [('oslo', 'Oslo'), ('bergen', 'Bergen'), ('trondheim', 'Trondheim'),
          ('stavanger', 'Stavanger'), ('national', 'National')]
LOGICAL = [('news', 'News'), ('events', 'Events'), ('jobs', 'Jobs'), ('shop', 'Shop')]
LEGACY = ['news', 'events', 'expenses', 'orders', 'jobs']


def find_topics_array(text):
    """Return (index of '[', index of matching ']') for the topics array."""
    m = re.search(r'"topics"\s*:\s*\[', text)
    if not m:
        raise SystemExit('no "topics" array found')
    start = m.end() - 1
    depth, i, in_str, esc = 0, start, False, False
    while i < len(text):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0:
                return start, i
        i += 1
    raise SystemExit('unterminated "topics" array')


def split_objects(body):
    """Split an array body into its top-level object texts, in order."""
    objs, depth, i, obj_start, in_str, esc = [], 0, 0, None, False, False
    while i < len(body):
        ch = body[i]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == '{':
            if depth == 0:
                obj_start = i
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                objs.append((obj_start, i + 1, body[obj_start:i + 1]))
        i += 1
    return objs


def write(path, text):
    json.loads(text)  # refuse to write anything that is not valid JSON
    open(path, 'w').write(text)


def do_add(path, text, start, end):
    body = text[start + 1:end]
    existing = {t['$id'] for t in json.loads(text[start:end + 1])}

    wanted = [(f'{lid}_{cs}', f'{ll} — {cl}')
              for lid, ll in LOGICAL for cs, cl in CAMPUS]
    wanted.append(('general', 'Important announcements'))
    added = [(tid, name) for tid, name in wanted if tid not in existing]
    if not added:
        print(f'{path}: nothing to add; total {len(existing)}')
        return

    obj_indent = (re.search(r'\n(\s+)\{', body) or [None, '  '])[1]
    key_m = re.search(r'\n(\s+)"\$id"', body)
    key_indent = key_m.group(1) if key_m else obj_indent + '  '
    close_indent = re.search(r'(\s*)$', body).group(1).lstrip('\n')

    chunks = [
        f'{obj_indent}{{\n'
        f'{key_indent}"$id": "{tid}",\n'
        f'{key_indent}"name": "{name}",\n'
        f'{key_indent}"subscribe": ["users"]\n'
        f'{obj_indent}}}'
        for tid, name in added
    ]
    stripped = body.rstrip()
    joined = ',\n'.join(chunks)
    new_body = (f'{stripped},\n{joined}\n{close_indent}' if stripped.endswith('}')
                else f'\n{joined}\n{close_indent}')

    write(path, text[:start + 1] + new_body + text[end:])
    print(f'{path}: added {len(added)} topics; total {len(existing) + len(added)}')


def do_remove(path, text, start, end):
    body = text[start + 1:end]
    objs = split_objects(body)
    keep = []
    removed = []
    for s, e, obj_text in objs:
        tid = json.loads(obj_text)['$id']
        (removed if tid in LEGACY else keep).append((tid, obj_text))
    if not removed:
        print(f'{path}: nothing to remove; total {len(keep)}')
        return

    obj_indent = (re.search(r'\n(\s+)\{', body) or [None, '  '])[1]
    close_indent = re.search(r'(\s*)$', body).group(1).lstrip('\n')
    # split_objects returns each object starting at its '{', without the
    # leading whitespace, so re-apply the array's own indent to every one.
    joined = ',\n'.join(obj_indent + t for _, t in keep)
    new_body = f'\n{joined}\n{close_indent}' if keep else ''

    write(path, text[:start + 1] + new_body + text[end:])
    print(f'{path}: removed {len(removed)} topics ({", ".join(t for t, _ in removed)}); '
          f'total {len(keep)}')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('add', 'remove'):
        raise SystemExit(__doc__)
    op, cfg = sys.argv[1], sys.argv[2]
    txt = open(cfg).read()
    s, e = find_topics_array(txt)
    (do_add if op == 'add' else do_remove)(cfg, txt, s, e)
TOPICS_EDIT_EOF
echo written
```

- [ ] **Step 2: Add the topics to both configs**

```bash
WS=/Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions
python3 "$WS/topics_edit.py" add /Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json
python3 "$WS/topics_edit.py" add /Users/markus/Documents/dev/BISO-Sites/packages/api/appwrite.config.json
```

Expected output — one line per file, each ending `added 21 topics; total 26`.

Then confirm each change is purely additive. **Both** commands must report
insertions in the low hundreds and **zero deletions**; anything else means the
file was reformatted and must not be committed:

```bash
git -C /Users/markus/Documents/dev/BISO-Flutter diff --stat -- appwrite.config.json
git -C /Users/markus/Documents/dev/BISO-Sites diff --stat -- packages/api/appwrite.config.json
```

Expected: roughly `105 insertions(+)` on each, with no deletions.

- [ ] **Step 3: Verify both configs are still valid JSON and agree**

```bash
python3 -c "
import json
a=json.load(open('/Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json'))['topics']
b=json.load(open('/Users/markus/Documents/dev/BISO-Sites/packages/api/appwrite.config.json'))['topics']
ida=sorted(t['\$id'] for t in a); idb=sorted(t['\$id'] for t in b)
assert ida==idb, ('configs disagree', set(ida)^set(idb))
assert 'general' in ida and 'events_oslo' in ida and 'shop_national' in ida
print('OK', len(ida), 'topics in both configs')
"
```

Expected: `OK 26 topics in both configs`

- [ ] **Step 4: Commit in both repos**

```bash
git add appwrite.config.json && git commit -m "Add campus-scoped notification topics

Additive only - the five original topics stay until every consumer has
migrated, so no live send path breaks mid-rollout.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
cd /Users/markus/Documents/dev/BISO-Sites && git add packages/api/appwrite.config.json && git commit -m "Add campus-scoped notification topics

Mirrors the Flutter repo's appwrite.config.json.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Tell the user to push the config**

Stop and report: the new topics must exist in Appwrite before any later task can be verified against a real device. The user pushes them (`appwrite push topics` or the console). Do not proceed past Task 9 without confirmation that they exist.

---

### Task 2: The topic taxonomy (pure)

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Flutter/lib/core/constants/notification_topics.dart`
- Test: `/Users/markus/Documents/dev/BISO-Flutter/test/core/constants/notification_topics_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum NotificationTopic { news, events, jobs, shop }` with `String get id` (its `name`) and `String get label`.
  - `const String kGeneralTopicId = 'general';`
  - `const Map<String, bool> kDefaultTopicIntent` — all four `true`.
  - `String campusSlugFor(String? campusId)`
  - `Set<String> appwriteTopicIdsFor({required Map<String, bool> intent, required String? campusId})`

- [ ] **Step 1: Write the failing test**

Create `test/core/constants/notification_topics_test.dart`:

```dart
import 'package:biso/core/constants/notification_topics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('campusSlugFor', () {
    test('maps each known campus id to its slug', () {
      expect(campusSlugFor('1'), 'oslo');
      expect(campusSlugFor('2'), 'bergen');
      expect(campusSlugFor('3'), 'trondheim');
      expect(campusSlugFor('4'), 'stavanger');
      expect(campusSlugFor('5'), 'national');
    });

    test(
      'falls back to national for a null campus, because a profile campus is '
      'optional and those students must still receive national content',
      () {
        expect(campusSlugFor(null), 'national');
      },
    );

    test('falls back to national for an unrecognised campus id', () {
      expect(campusSlugFor('99'), 'national');
      expect(campusSlugFor(''), 'national');
    });
  });

  group('appwriteTopicIdsFor', () {
    test('expands each enabled topic into its campus and national scopes', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': true, 'events': false, 'jobs': false, 'shop': false},
          campusId: '2',
        ),
        <String>{'general', 'news_bergen', 'news_national'},
      );
    });

    test('always includes the general topic, even with everything off', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': false, 'events': false, 'jobs': false, 'shop': false},
          campusId: '1',
        ),
        <String>{'general'},
      );
    });

    test(
      'does not emit a duplicate national id for a national student - the '
      'campus scope and the national scope are the same topic',
      () {
        expect(
          appwriteTopicIdsFor(
            intent: const {'news': true, 'events': false, 'jobs': false, 'shop': false},
            campusId: '5',
          ),
          <String>{'general', 'news_national'},
        );
      },
    );

    test('expands every enabled topic', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': true, 'events': true, 'jobs': true, 'shop': true},
          campusId: '1',
        ),
        <String>{
          'general',
          'news_oslo', 'news_national',
          'events_oslo', 'events_national',
          'jobs_oslo', 'jobs_national',
          'shop_oslo', 'shop_national',
        },
      );
    });

    test('treats a missing intent key as disabled rather than throwing', () {
      expect(
        appwriteTopicIdsFor(intent: const {}, campusId: '1'),
        <String>{'general'},
      );
    });
  });

  group('kDefaultTopicIntent', () {
    test('covers exactly the four logical topics', () {
      expect(
        kDefaultTopicIntent.keys.toSet(),
        NotificationTopic.values.map((t) => t.id).toSet(),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/core/constants/notification_topics_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'biso' ... notification_topics.dart` (the file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/core/constants/notification_topics.dart`:

```dart
/// The notification topic taxonomy.
///
/// A student chooses among [NotificationTopic] values — News, Events, Jobs,
/// Shop. They never see an Appwrite topic id: the campus half is derived from
/// their profile campus by [appwriteTopicIdsFor].
///
/// Mirrored server-side in BISO-Sites at
/// `packages/shared/utils/notification-topics.ts`. The two must agree; a change
/// here needs the same change there.
library;

/// A topic a student can opt into.
enum NotificationTopic { news, events, jobs, shop }

extension NotificationTopicDetails on NotificationTopic {
  /// The logical id, and the prefix of every Appwrite topic id for it.
  String get id => name;

  String get label => switch (this) {
    NotificationTopic.news => 'News',
    NotificationTopic.events => 'Events',
    NotificationTopic.jobs => 'Jobs',
    NotificationTopic.shop => 'Shop',
  };
}

/// The one topic a student does not choose.
///
/// Every device subscribes to it unconditionally so that a true broadcast has a
/// single topic to target. Without it, "broadcast" would have to fan out across
/// every campus topic, and a student subscribed to several of them might be
/// notified more than once for one message.
const String kGeneralTopicId = 'general';

/// The slug used when a campus is unknown, absent, or is National itself.
const String kNationalSlug = 'national';

const Map<String, String> _campusSlugs = <String, String>{
  '1': 'oslo',
  '2': 'bergen',
  '3': 'trondheim',
  '4': 'stavanger',
  '5': kNationalSlug,
};

/// What a student gets before they have answered the prompt.
const Map<String, bool> kDefaultTopicIntent = <String, bool>{
  'news': true,
  'events': true,
  'jobs': true,
  'shop': true,
};

/// The campus slug for [campusId].
///
/// Falls back to [kNationalSlug] for null, empty, or unrecognised ids. That
/// fallback is load-bearing rather than defensive: a profile campus is
/// optional, so "no campus" is a state real students are in. They get national
/// content instead of nothing at all.
String campusSlugFor(String? campusId) =>
    _campusSlugs[campusId] ?? kNationalSlug;

/// The full set of Appwrite topic ids a device should be subscribed to.
///
/// Each enabled logical topic contributes its campus scope *and* the national
/// scope, so that content published as national reaches every campus. For a
/// student whose campus is National those are the same id, and the set
/// collapses it.
Set<String> appwriteTopicIdsFor({
  required Map<String, bool> intent,
  required String? campusId,
}) {
  final slug = campusSlugFor(campusId);
  final ids = <String>{kGeneralTopicId};
  for (final topic in NotificationTopic.values) {
    if (intent[topic.id] != true) continue;
    ids.add('${topic.id}_$slug');
    ids.add('${topic.id}_$kNationalSlug');
  }
  return ids;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/core/constants/notification_topics_test.dart
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/core/constants/notification_topics.dart test/core/constants/notification_topics_test.dart
git commit -m "Add the notification topic taxonomy

Logical topics are what a student picks; the campus half of an Appwrite
topic id is derived from their profile campus and never chosen. A null
campus resolves to national rather than to nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The reconcile diff and legacy migration (pure)

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Flutter/lib/data/services/topic_reconciler.dart`
- Test: `/Users/markus/Documents/dev/BISO-Flutter/test/data/services/topic_reconciler_test.dart`

**Interfaces:**
- Consumes: `kDefaultTopicIntent`, `NotificationTopic` from Task 2.
- Produces:
  - `class TopicDiff { Set<String> toCreate; Set<String> toDelete; bool get isEmpty; }`
  - `TopicDiff computeTopicDiff({required Set<String> desired, required Map<String, String> current})`
  - `Map<String, bool> migrateLegacyIntent(Map<String, bool>? legacy)`

- [ ] **Step 1: Write the failing test**

Create `test/data/services/topic_reconciler_test.dart`:

```dart
import 'package:biso/data/services/topic_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeTopicDiff', () {
    test('is empty when the device already matches what is wanted', () {
      final diff = computeTopicDiff(
        desired: {'general', 'news_oslo'},
        current: {'general': 'sub1', 'news_oslo': 'sub2'},
      );
      expect(diff.toCreate, isEmpty);
      expect(diff.toDelete, isEmpty);
      expect(diff.isEmpty, isTrue);
    });

    test('creates everything for a device with no subscriptions yet', () {
      final diff = computeTopicDiff(
        desired: {'general', 'news_oslo'},
        current: const {},
      );
      expect(diff.toCreate, {'general', 'news_oslo'});
      expect(diff.toDelete, isEmpty);
    });

    test('deletes what is no longer wanted', () {
      final diff = computeTopicDiff(
        desired: {'general'},
        current: {'general': 'sub1', 'news_oslo': 'sub2'},
      );
      expect(diff.toCreate, isEmpty);
      expect(diff.toDelete, {'news_oslo'});
    });

    test(
      'a campus move swaps the campus scope and keeps the national one, so a '
      'student who transfers stops getting the old campus feed',
      () {
        final diff = computeTopicDiff(
          desired: {'general', 'news_bergen', 'news_national'},
          current: {
            'general': 'sub1',
            'news_oslo': 'sub2',
            'news_national': 'sub3',
          },
        );
        expect(diff.toCreate, {'news_bergen'});
        expect(diff.toDelete, {'news_oslo'});
      },
    );

    test('turning everything off still keeps general', () {
      final diff = computeTopicDiff(
        desired: {'general'},
        current: {
          'general': 'sub1',
          'news_oslo': 'sub2',
          'events_oslo': 'sub3',
        },
      );
      expect(diff.toDelete, {'news_oslo', 'events_oslo'});
      expect(diff.toCreate, isEmpty);
    });
  });

  group('migrateLegacyIntent', () {
    test('renames the old products topic to shop', () {
      expect(
        migrateLegacyIntent(const {'products': false}),
        containsPair('shop', false),
      );
    });

    test(
      'drops expenses entirely - reimbursement updates become personal '
      'notifications, not a topic',
      () {
        final migrated = migrateLegacyIntent(const {'expenses': true});
        expect(migrated.containsKey('expenses'), isFalse);
      },
    );

    test('carries the unchanged topics across', () {
      final migrated = migrateLegacyIntent(const {
        'events': false,
        'jobs': true,
      });
      expect(migrated['events'], isFalse);
      expect(migrated['jobs'], isTrue);
    });

    test('defaults news on, since it had no old equivalent to carry over', () {
      expect(migrateLegacyIntent(const {'events': false})['news'], isTrue);
    });

    test('returns the defaults when there is nothing to migrate', () {
      final migrated = migrateLegacyIntent(null);
      expect(migrated['news'], isTrue);
      expect(migrated['events'], isTrue);
      expect(migrated['jobs'], isTrue);
      expect(migrated['shop'], isTrue);
    });

    test('produces exactly the four logical keys and no others', () {
      expect(
        migrateLegacyIntent(const {
          'products': true,
          'expenses': true,
          'orders': true,
        }).keys.toSet(),
        {'news', 'events', 'jobs', 'shop'},
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/topic_reconciler_test.dart
```

Expected: FAIL — `topic_reconciler.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/data/services/topic_reconciler.dart`:

```dart
import '../../core/constants/notification_topics.dart';

/// What a device must create and delete to match the student's intent.
class TopicDiff {
  const TopicDiff({required this.toCreate, required this.toDelete});

  /// Appwrite topic ids that need a new subscriber.
  final Set<String> toCreate;

  /// Appwrite topic ids whose subscriber should be deleted.
  final Set<String> toDelete;

  bool get isEmpty => toCreate.isEmpty && toDelete.isEmpty;
}

/// Diff the topics a device *should* hold against the ones it *does*.
///
/// This is what makes reconciliation idempotent: it compares observed state
/// rather than replaying a sequence of toggles, so running it twice is a no-op
/// and two devices never interfere with each other.
TopicDiff computeTopicDiff({
  required Set<String> desired,
  required Map<String, String> current,
}) {
  final held = current.keys.toSet();
  return TopicDiff(
    toCreate: desired.difference(held),
    toDelete: held.difference(desired),
  );
}

/// Old topic id -> new logical id. Anything absent from this map is dropped.
const Map<String, String> _legacyRenames = <String, String>{
  'news': 'news',
  'events': 'events',
  'jobs': 'jobs',
  'products': 'shop',
  // 'expenses' and 'orders' are deliberately absent: both become personal
  // notifications rather than topics.
};

/// Convert a pre-existing `topic_subscriptions` map into the new intent shape.
///
/// Starts from the defaults so a topic with no old equivalent — `news` — is
/// switched on rather than silently missing, then applies whatever the student
/// had actually chosen on top.
Map<String, bool> migrateLegacyIntent(Map<String, bool>? legacy) {
  final intent = Map<String, bool>.from(kDefaultTopicIntent);
  if (legacy == null) return intent;
  for (final entry in legacy.entries) {
    final renamed = _legacyRenames[entry.key];
    if (renamed == null) continue;
    intent[renamed] = entry.value;
  }
  return intent;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/topic_reconciler_test.dart
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/data/services/topic_reconciler.dart test/data/services/topic_reconciler_test.dart
git commit -m "Add the topic reconcile diff and legacy intent migration

The diff compares observed state rather than replaying toggles, which is
what lets reconcile() run twice harmlessly and lets two devices reconcile
the same intent without coordinating.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Device-local subscription store

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Flutter/lib/data/services/device_subscription_store.dart`
- Test: `/Users/markus/Documents/dev/BISO-Flutter/test/data/services/device_subscription_store_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class DeviceSubscriptionStore` with
  - `Future<String?> readTargetId()`
  - `Future<void> writeTargetId(String targetId)`
  - `Future<Map<String, String>> readSubscriberIds()`
  - `Future<void> writeSubscriberIds(Map<String, String> ids)`
  - `Future<void> clear()`

- [ ] **Step 1: Write the failing test**

Create `test/data/services/device_subscription_store_test.dart`:

```dart
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('round-trips the push target id', () async {
    final store = DeviceSubscriptionStore();
    expect(await store.readTargetId(), isNull);

    await store.writeTargetId('target-1');
    expect(await store.readTargetId(), 'target-1');
  });

  test('round-trips subscriber ids', () async {
    final store = DeviceSubscriptionStore();
    expect(await store.readSubscriberIds(), isEmpty);

    await store.writeSubscriberIds({'news_oslo': 'sub-1'});
    expect(await store.readSubscriberIds(), {'news_oslo': 'sub-1'});
  });

  test('replaces the stored map wholesale rather than merging', () async {
    final store = DeviceSubscriptionStore();
    await store.writeSubscriberIds({'news_oslo': 'sub-1'});
    await store.writeSubscriberIds({'events_oslo': 'sub-2'});
    expect(await store.readSubscriberIds(), {'events_oslo': 'sub-2'});
  });

  test(
    'reads corrupt stored JSON as empty instead of throwing, so one bad write '
    'cannot brick notifications for the life of the install',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'topic_subscriber_ids': 'not json',
      });
      expect(await DeviceSubscriptionStore().readSubscriberIds(), isEmpty);
    },
  );

  test('ignores non-string values in stored JSON', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'topic_subscriber_ids': '{"news_oslo":"sub-1","events_oslo":42}',
    });
    expect(
      await DeviceSubscriptionStore().readSubscriberIds(),
      {'news_oslo': 'sub-1'},
    );
  });

  test('clear removes both keys', () async {
    final store = DeviceSubscriptionStore();
    await store.writeTargetId('target-1');
    await store.writeSubscriberIds({'news_oslo': 'sub-1'});

    await store.clear();

    expect(await store.readTargetId(), isNull);
    expect(await store.readSubscriberIds(), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/device_subscription_store_test.dart
```

Expected: FAIL — `device_subscription_store.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/data/services/device_subscription_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local record of this install's push subscriptions.
///
/// An Appwrite push target belongs to a *device*, not to a user, and the client
/// SDK offers no way to list a topic's subscribers — so the subscriber ids
/// needed to unsubscribe have nowhere to live but here. Account preferences
/// would be wrong: two devices sharing one account would overwrite each other,
/// and unsubscribing on one would delete the other's subscription.
///
/// The student's *intent* is per-user and lives in account preferences instead.
class DeviceSubscriptionStore {
  static const String _targetKey = 'push_target_id';
  static const String _subscribersKey = 'topic_subscriber_ids';

  Future<String?> readTargetId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_targetKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writeTargetId(String targetId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetKey, targetId);
  }

  /// The `topicId -> Appwrite subscriber $id` map for this device.
  ///
  /// Unreadable or malformed storage reads as empty rather than throwing. A
  /// device that cannot read its map re-creates its subscriptions on the next
  /// reconcile, which is recoverable; an exception here would break
  /// notifications for the life of the install.
  Future<Map<String, String>> readSubscriberIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subscribersKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    } catch (e) {
      debugPrint('DeviceSubscriptionStore: unreadable subscriber ids: $e');
      return <String, String>{};
    }
  }

  Future<void> writeSubscriberIds(Map<String, String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subscribersKey, jsonEncode(ids));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_targetKey);
    await prefs.remove(_subscribersKey);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/device_subscription_store_test.dart
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/data/services/device_subscription_store.dart test/data/services/device_subscription_store_test.dart
git commit -m "Store push target and subscriber ids per device

A push target belongs to a device, so keeping these in account prefs made
two devices on one account overwrite each other. Corrupt storage reads as
empty so a bad write cannot permanently break notifications.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Push-target resolution

The core bug fix. Today `_createPushTarget` always calls `createPushTarget` with a fresh `ID.unique()`; on every launch after the first the FCM token collides, the 409 is swallowed, `_pushTargetId` stays null, and every subsequent subscribe silently no-ops.

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/data/services/notification_service.dart` (replace `_createPushTarget`, lines 196–213)
- Test: `/Users/markus/Documents/dev/BISO-Flutter/test/data/services/notification_service_target_test.dart`

**Interfaces:**
- Consumes: `DeviceSubscriptionStore` (Task 4).
- Produces: `Future<String?> NotificationService.resolvePushTarget(String token)` — returns the Appwrite target `$id`, or `null` if it could not be established. Also `const String kFcmProviderId = 'push';` exported from the same file.

- [ ] **Step 1: Write the failing test**

Create `test/data/services/notification_service_target_test.dart`:

```dart
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

models.Target _target({required String id, required String identifier}) =>
    models.Target(
      $id: id,
      $createdAt: '',
      $updatedAt: '',
      name: 'device',
      userId: 'user-1',
      providerId: 'push',
      providerType: 'push',
      identifier: identifier,
      expired: false,
    );

models.User _user(List<models.Target> targets) => models.User(
  $id: 'user-1',
  $createdAt: '',
  $updatedAt: '',
  name: 'Test',
  registration: '',
  status: true,
  labels: const <String>[],
  passwordUpdate: '',
  email: 'test@bi.no',
  phone: '',
  emailVerification: true,
  phoneVerification: false,
  mfa: false,
  prefs: models.Preferences(data: <String, dynamic>{}),
  targets: targets,
  accessedAt: '',
);

class _FakeAccount extends Account {
  _FakeAccount() : super(Client());

  int createCalls = 0;
  int updateCalls = 0;
  int getCalls = 0;

  /// When set, `createPushTarget` throws this instead of succeeding.
  AppwriteException? createThrows;

  /// When set, `updatePushTarget` throws this instead of succeeding.
  AppwriteException? updateThrows;

  List<models.Target> existingTargets = const <models.Target>[];

  @override
  Future<models.Target> createPushTarget({
    required String targetId,
    required String identifier,
    String? providerId,
  }) async {
    createCalls++;
    lastProviderId = providerId;
    final failure = createThrows;
    if (failure != null) throw failure;
    return _target(id: 'created-target', identifier: identifier);
  }

  String? lastProviderId;

  @override
  Future<models.Target> updatePushTarget({
    required String targetId,
    required String identifier,
  }) async {
    updateCalls++;
    final failure = updateThrows;
    if (failure != null) throw failure;
    return _target(id: targetId, identifier: identifier);
  }

  @override
  Future<models.User> get() async {
    getCalls++;
    return _user(existingTargets);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('creates a target on a first run and stores its id', () async {
    final account = _FakeAccount();
    final service = NotificationService.withAccount(account);

    expect(await service.resolvePushTarget('token-1'), 'created-target');
    expect(account.createCalls, 1);
    expect(await DeviceSubscriptionStore().readTargetId(), 'created-target');
  });

  test(
    'registers against the FCM provider id "push" - the project has no '
    'provider called "fcm", which is why targets never got created',
    () async {
      final account = _FakeAccount();
      await NotificationService.withAccount(account).resolvePushTarget('t');
      expect(account.lastProviderId, 'push');
    },
  );

  test('updates the stored target on a later run instead of recreating', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_target_id': 'stored-target',
    });
    final account = _FakeAccount();

    final resolved = await NotificationService.withAccount(
      account,
    ).resolvePushTarget('token-2');

    expect(resolved, 'stored-target');
    expect(account.updateCalls, 1);
    expect(account.createCalls, 0);
  });

  test('falls back to creating when the stored target is gone', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_target_id': 'deleted-target',
    });
    final account = _FakeAccount()
      ..updateThrows = AppwriteException('not found', 404);

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('t'),
      'created-target',
    );
    expect(account.createCalls, 1);
  });

  test(
    'adopts the existing target when creation 409s - this is the case that '
    'silently broke every subscription after the first launch',
    () async {
      final account = _FakeAccount()
        ..createThrows = AppwriteException('target exists', 409)
        ..existingTargets = [
          _target(id: 'other-device', identifier: 'someone-elses-token'),
          _target(id: 'this-device', identifier: 'token-1'),
        ];

      final resolved = await NotificationService.withAccount(
        account,
      ).resolvePushTarget('token-1');

      expect(resolved, 'this-device');
      expect(account.getCalls, 1);
      expect(await DeviceSubscriptionStore().readTargetId(), 'this-device');
    },
  );

  test('returns null when a 409 has no matching target to adopt', () async {
    final account = _FakeAccount()
      ..createThrows = AppwriteException('target exists', 409)
      ..existingTargets = const <models.Target>[];

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('token-1'),
      isNull,
    );
  });

  test(
    'forgets stale subscriber ids when the target changes identity, so the '
    'next reconcile re-subscribes rather than computing an empty diff against '
    'subscribers that belong to a target which no longer exists',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'old-target',
        'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
      });
      final account = _FakeAccount()
        ..updateThrows = AppwriteException('not found', 404);

      final resolved = await NotificationService.withAccount(
        account,
      ).resolvePushTarget('token-1');

      expect(resolved, 'created-target');
      expect(await DeviceSubscriptionStore().readSubscriberIds(), isEmpty);
    },
  );

  test(
    'keeps subscriber ids when the target id is unchanged, so a routine token '
    'refresh does not churn every subscription',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'stored-target',
        'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
      });
      final account = _FakeAccount();

      await NotificationService.withAccount(account).resolvePushTarget('t2');

      expect(
        await DeviceSubscriptionStore().readSubscriberIds(),
        {'news_oslo': 'sub-1'},
      );
    },
  );

  test('returns null on a non-409 create failure without calling get', () async {
    final account = _FakeAccount()
      ..createThrows = AppwriteException('offline', 500);

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('t'),
      isNull,
    );
    expect(account.getCalls, 0);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/services/notification_service_target_test.dart
```

Expected: FAIL — `The method 'resolvePushTarget' isn't defined for the class 'NotificationService'`.

- [ ] **Step 3: Replace `_createPushTarget` with `resolvePushTarget`**

In `lib/data/services/notification_service.dart`:

Add to the imports at the top:

```dart
import 'device_subscription_store.dart';
```

Add above `class NotificationService`:

```dart
/// The Appwrite Messaging provider `$id` for FCM push.
///
/// Not `'fcm'`. The project has no provider by that name, and passing it is why
/// push targets were never created.
const String kFcmProviderId = 'push';
```

Add a store field alongside `final Account _account;`:

```dart
final DeviceSubscriptionStore _store = DeviceSubscriptionStore();
```

Then replace the whole `_createPushTarget` method (currently lines 196–213) with:

```dart
  /// Establish this device's Appwrite push target for [token] and return its id.
  ///
  /// Ordered so the common case is a single call. The 409 branch is the one
  /// that matters: Appwrite rejects a second target for an identifier it
  /// already holds, which happens on every launch after the first. The old code
  /// swallowed that and left `_pushTargetId` null, so every later
  /// `subscribeToTopic` returned early and topic subscription could never work.
  Future<String?> resolvePushTarget(String token) async {
    final storedId = await _store.readTargetId();
    if (storedId != null) {
      try {
        final target = await _account.updatePushTarget(
          targetId: storedId,
          identifier: token,
        );
        _pushTargetId = target.$id;
        return target.$id;
      } on AppwriteException catch (e) {
        // The target was deleted server-side, or the id is stale. Fall through
        // and create a fresh one.
        debugPrint(
          'resolvePushTarget: update of $storedId failed '
          '(${e.code}) ${e.message}; creating a new target',
        );
      }
    }

    try {
      final target = await _account.createPushTarget(
        targetId: ID.unique(),
        identifier: token,
        providerId: kFcmProviderId,
      );
      await _adoptTarget(target.$id, storedId);
      return target.$id;
    } on AppwriteException catch (e) {
      if (e.code != 409) {
        debugPrint(
          'resolvePushTarget: create failed (${e.code}) ${e.message}',
        );
        return null;
      }
    }

    // 409: a target already holds this token. Find and adopt it.
    try {
      final user = await _account.get();
      for (final target in user.targets) {
        if (target.identifier == token) {
          await _adoptTarget(target.$id, storedId);
          return target.$id;
        }
      }
      debugPrint(
        'resolvePushTarget: got 409 but no target matches this token; '
        'push is unavailable on this device',
      );
    } on AppwriteException catch (e) {
      debugPrint(
        'resolvePushTarget: could not read targets after 409 '
        '(${e.code}) ${e.message}',
      );
    }
    return null;
  }

  /// Record [targetId] as this device's target, forgetting the stored
  /// subscriber ids if it replaces a different one.
  ///
  /// A subscriber belongs to a *target*. When the target changes identity the
  /// old subscribers are attached to something that no longer exists — but the
  /// stored map would still claim those topics are covered, so the next
  /// reconcile would compute an empty diff and the device would go silently
  /// unsubscribed. Clearing forces them to be recreated against the new target.
  Future<void> _adoptTarget(String targetId, String? previousId) async {
    if (previousId != null && previousId != targetId) {
      await _store.writeSubscriberIds(const <String, String>{});
    }
    await _store.writeTargetId(targetId);
    _pushTargetId = targetId;
  }
```

Update the two existing call sites that referenced the old name — line 131 (`_createPushTarget(newToken)`) and line 172 (`await _createPushTarget(_fcmToken!)`) — to call `resolvePushTarget` instead:

```dart
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        resolvePushTarget(newToken);
      });
```

```dart
      if (isGranted && _fcmToken != null) {
        await resolvePushTarget(_fcmToken!);
        await _loadTopicSubscriptions();
      }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/notification_service_target_test.dart
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Verify nothing else broke**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/ && flutter analyze lib/data/services/notification_service.dart
```

Expected: all tests pass; analyze reports no errors (pre-existing warnings elsewhere are fine).

- [ ] **Step 7: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/data/services/notification_service.dart test/data/services/notification_service_target_test.dart
git commit -m "Resolve the push target instead of blindly recreating it

createPushTarget 409s once a target holds the FCM token, which is every
launch after the first. That was swallowed, leaving no target id, so every
topic subscribe returned early - silently. Now the 409 adopts the existing
target, and the provider id is 'push' rather than the nonexistent 'fcm'.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Intent persistence and `reconcile()`

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/data/services/notification_service.dart`
- Test: `/Users/markus/Documents/dev/BISO-Flutter/test/data/services/notification_service_reconcile_test.dart` (create)

**Interfaces:**
- Consumes: `appwriteTopicIdsFor`, `kDefaultTopicIntent` (Task 2); `computeTopicDiff`, `migrateLegacyIntent` (Task 3); `DeviceSubscriptionStore` (Task 4); `resolvePushTarget` (Task 5).
- Produces:
  - `Future<Map<String, bool>> NotificationService.loadTopicIntent()`
  - `Future<void> NotificationService.saveTopicIntent(Map<String, bool> intent)`
  - `Future<bool> NotificationService.hasAnsweredTopicPrompt()`
  - `Future<void> NotificationService.reconcile({required String? campusId})`
  - Preference keys: `notification_topics`, `notification_topics_set_at`.

- [ ] **Step 1: Write the failing test**

Create `test/data/services/notification_service_reconcile_test.dart`:

```dart
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccount extends Account {
  _FakeAccount(this._prefs) : super(Client());

  Map<String, dynamic> _prefs;
  Map<String, dynamic> get saved => _prefs;

  @override
  Future<models.Preferences> getPrefs() async =>
      models.Preferences(data: Map<String, dynamic>.from(_prefs));

  @override
  Future<models.User> updatePrefs({required Map prefs}) async {
    _prefs = Map<String, dynamic>.from(prefs);
    throw UnimplementedError('return value unused by the code under test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('loadTopicIntent', () {
    test('returns the defaults for an account that has never chosen', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.loadTopicIntent(), {
        'news': true,
        'events': true,
        'jobs': true,
        'shop': true,
      });
    });

    test('reads a stored intent map', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics': <String, dynamic>{
            'news': false,
            'events': true,
            'jobs': false,
            'shop': false,
          },
        }),
      );
      expect((await service.loadTopicIntent())['news'], isFalse);
    });

    test(
      'migrates a legacy topic_subscriptions map, renaming products to shop '
      'and dropping expenses',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{
              'products': false,
              'expenses': true,
              'events': false,
            },
          }),
        );
        final intent = await service.loadTopicIntent();
        expect(intent['shop'], isFalse);
        expect(intent['events'], isFalse);
        expect(intent.containsKey('expenses'), isFalse);
      },
    );
  });

  group('hasAnsweredTopicPrompt', () {
    test('is false for a brand new account', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.hasAnsweredTopicPrompt(), isFalse);
    });

    test('is true once the marker is stored', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics_set_at': '2026-09-09T10:00:00.000Z',
        }),
      );
      expect(await service.hasAnsweredTopicPrompt(), isTrue);
    });

    test(
      'is true for a legacy account with old preferences, so a student who '
      'already chose is not asked again',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{'events': false},
          }),
        );
        expect(await service.hasAnsweredTopicPrompt(), isTrue);
      },
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/notification_service_reconcile_test.dart
```

Expected: FAIL — `The method 'loadTopicIntent' isn't defined`.

- [ ] **Step 3: Add intent persistence and reconcile**

Add these imports to `lib/data/services/notification_service.dart`:

```dart
import '../../core/constants/notification_topics.dart';
import 'topic_reconciler.dart';
```

Add the preference-key constants near `kFcmProviderId`:

```dart
/// Per-user intent: which logical topics this student wants. Campus-free.
const String kTopicIntentPrefKey = 'notification_topics';

/// Marks the first-run prompt as answered. Its absence is what triggers it.
const String kTopicIntentSetAtPrefKey = 'notification_topics_set_at';

/// The pre-migration key, still read once to carry old choices forward.
const String kLegacyTopicSubscriptionsPrefKey = 'topic_subscriptions';
```

Add these methods to `NotificationService`:

```dart
  /// The student's topic intent, migrating a pre-existing legacy map if that is
  /// all the account has.
  Future<Map<String, bool>> loadTopicIntent() async {
    try {
      final prefs = await _account.getPrefs();
      final stored = decodeTopicSubscriptions(prefs.data[kTopicIntentPrefKey]);
      if (stored != null) {
        return <String, bool>{...kDefaultTopicIntent, ...stored}
          ..removeWhere((key, _) => !kDefaultTopicIntent.containsKey(key));
      }
      return migrateLegacyIntent(
        decodeTopicSubscriptions(prefs.data[kLegacyTopicSubscriptionsPrefKey]),
      );
    } catch (e) {
      debugPrint('loadTopicIntent failed: $e');
      return Map<String, bool>.from(kDefaultTopicIntent);
    }
  }

  /// Persist intent and mark the prompt answered.
  ///
  /// Written before the OS permission request and regardless of its outcome: a
  /// student who declines the system dialog has still expressed a preference,
  /// and it takes effect if they enable notifications later.
  Future<void> saveTopicIntent(Map<String, bool> intent) async {
    final prefs = await _account.getPrefs();
    final updated = Map<String, dynamic>.from(prefs.data);
    updated[kTopicIntentPrefKey] = intent;
    updated[kTopicIntentSetAtPrefKey] = DateTime.now().toIso8601String();
    await _account.updatePrefs(prefs: updated);
  }

  /// Whether this student has already been asked to pick topics.
  ///
  /// A legacy `topic_subscriptions` map counts as answered — they chose once
  /// already, under the old names, and should not be re-prompted just because
  /// the storage changed.
  Future<bool> hasAnsweredTopicPrompt() async {
    try {
      final prefs = await _account.getPrefs();
      if (prefs.data[kTopicIntentSetAtPrefKey] != null) return true;
      return decodeTopicSubscriptions(
            prefs.data[kLegacyTopicSubscriptionsPrefKey],
          ) !=
          null;
    } catch (e) {
      debugPrint('hasAnsweredTopicPrompt failed: $e');
      // Fail closed: do not interrupt a student because a read failed.
      return true;
    }
  }

  /// Bring this device's Appwrite subscriptions in line with the student's
  /// intent for [campusId].
  ///
  /// Idempotent by construction — it diffs desired against observed rather than
  /// replaying toggles — so it is safe to call on every launch, and two devices
  /// on one account reconcile independently without coordinating.
  Future<void> reconcile({required String? campusId}) async {
    if (!await areNotificationsEnabled()) {
      debugPrint('reconcile: notifications not permitted; intent kept for later');
      return;
    }

    final token = _fcmToken ?? await _firebaseMessaging.getToken();
    if (token == null) {
      debugPrint('reconcile: no FCM token; skipping');
      return;
    }
    _fcmToken = token;

    final targetId = await resolvePushTarget(token);
    if (targetId == null) {
      debugPrint('reconcile: no push target; skipping subscription changes');
      return;
    }

    final intent = await loadTopicIntent();
    final desired = appwriteTopicIdsFor(intent: intent, campusId: campusId);
    final current = await _store.readSubscriberIds();
    final diff = computeTopicDiff(desired: desired, current: current);
    if (diff.isEmpty) return;

    final updated = Map<String, String>.from(current);

    for (final topicId in diff.toCreate) {
      try {
        final subscriber = await _messaging.createSubscriber(
          topicId: topicId,
          subscriberId: ID.unique(),
          targetId: targetId,
        );
        updated[topicId] = subscriber.$id;
      } on AppwriteException catch (e) {
        // Best-effort per topic: one failure must not abort the rest. The next
        // reconcile retries, because the diff recomputes from observed state.
        debugPrint('reconcile: subscribe to $topicId failed (${e.code}) ${e.message}');
      }
    }

    for (final topicId in diff.toDelete) {
      final subscriberId = updated[topicId];
      if (subscriberId == null) continue;
      try {
        await _messaging.deleteSubscriber(
          topicId: topicId,
          subscriberId: subscriberId,
        );
        updated.remove(topicId);
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          // Already gone server-side; stop tracking it.
          updated.remove(topicId);
          continue;
        }
        debugPrint('reconcile: unsubscribe from $topicId failed (${e.code}) ${e.message}');
      }
    }

    await _store.writeSubscriberIds(updated);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/notification_service_reconcile_test.dart
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Run the whole service suite and analyze**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test test/data/services/ && flutter analyze lib/data/services/notification_service.dart
```

Expected: all pass, no analyzer errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/data/services/notification_service.dart test/data/services/notification_service_reconcile_test.dart
git commit -m "Add topic intent persistence and idempotent reconcile

Intent is per-user in account prefs; subscriber ids are per-device. A
legacy topic_subscriptions map counts as already answered, so migrating
students are not re-prompted. Subscribe failures are per-topic, and the
next reconcile retries them because the diff recomputes from observed state.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Provider and settings screen

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/providers/notification/notification_provider.dart`
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/presentation/screens/profile/settings_screen.dart` (the `_NotificationSettingsTab` class, from line 683)

**Interfaces:**
- Consumes: `loadTopicIntent`, `saveTopicIntent`, `reconcile` (Task 6); `NotificationTopic` (Task 2).
- Produces: `topicIntentProvider` — a `StateNotifierProvider<TopicIntentNotifier, AsyncValue<Map<String, bool>>>` with `Future<void> setTopic(String topicId, bool enabled)`.

- [ ] **Step 1: Add the intent notifier to the provider file**

Append to `lib/providers/notification/notification_provider.dart`:

```dart
/// The student's topic intent, and the only UI entry point for changing it.
///
/// Every change writes intent first, then reconciles this device's Appwrite
/// subscriptions to match. A failed reconcile surfaces as an error state rather
/// than leaving a switch asserting a subscription that does not exist.
class TopicIntentNotifier extends StateNotifier<AsyncValue<Map<String, bool>>> {
  TopicIntentNotifier(this._service, this._campusId)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final NotificationService _service;
  final String? _campusId;

  Future<void> _load() async {
    try {
      state = AsyncValue.data(await _service.loadTopicIntent());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> setTopic(String topicId, bool enabled) async {
    final current = state.value;
    if (current == null) return;

    final updated = <String, bool>{...current, topicId: enabled};
    // Optimistic, so the switch responds immediately.
    state = AsyncValue.data(updated);
    try {
      await _service.saveTopicIntent(updated);
      await _service.reconcile(campusId: _campusId);
    } catch (error, stackTrace) {
      // Put the switch back rather than leave the UI claiming something untrue.
      state = AsyncValue.data(current);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() => _load();
}

/// Rebuilds when the signed-in student or their home campus changes, so a
/// campus move resubscribes this device.
final topicIntentProvider =
    StateNotifierProvider<TopicIntentNotifier, AsyncValue<Map<String, bool>>>((
      ref,
    ) {
      final service = ref.watch(notificationServiceProvider);
      final campusId = ref.watch(
        authStateProvider.select((state) => state.user?.campusId),
      );
      return TopicIntentNotifier(service, campusId);
    });
```

- [ ] **Step 2: Fix the stale read in `NotificationPreferencesNotifier`**

In the same file, `_loadPreferences()` currently reads `_notificationService.topicSubscriptions` without awaiting the load, so the screen renders defaults over saved state. Replace that line:

```dart
      // Load topic subscriptions
      final topicSubscriptions = _notificationService.topicSubscriptions;
```

with:

```dart
      // Await the load: reading the in-memory map directly renders hardcoded
      // defaults over the student's saved choices on a cold start.
      final topicSubscriptions =
          await _notificationService.ensureTopicSubscriptionsLoaded();
```

- [ ] **Step 3: Replace the hardcoded switches in the settings screen**

In `lib/presentation/screens/profile/settings_screen.dart`, add the import:

```dart
import '../../../core/constants/notification_topics.dart';
```

In `_NotificationSettingsTab.build`, replace `ref.watch(notificationPreferencesProvider)` with the intent provider for the topic switches, and replace the four hardcoded `buildNotificationTile` blocks — Events, Marketplace, Jobs, and the feature-flagged Expenses block — with a loop. The Chat Messages tile stays exactly as it is, still driven by `notificationPreferencesProvider`.

The topic card becomes:

```dart
final topicIntentAsync = ref.watch(topicIntentProvider);
final homeCampusId = ref.watch(
  authStateProvider.select((state) => state.user?.campusId),
);

// …

topicIntentAsync.when(
  data: (intent) => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Column(
      children: [
        for (final topic in NotificationTopic.values) ...[
          if (topic != NotificationTopic.values.first) buildDivider(),
          buildNotificationTile(
            context: context,
            ref: ref,
            icon: _topicIcon(topic),
            iconColor: _topicColor(topic),
            title: topic.label,
            subtitle: _topicSubtitle(topic),
            isEnabled: intent[topic.id] ?? false,
            onChanged: (value) {
              ref.read(topicIntentProvider.notifier).setTopic(topic.id, value);
            },
            selectedCampus: selectedCampus,
          ),
        ],
      ],
    ),
  ),
  loading: () => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  ),
  error: (error, _) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      'Could not load your notification settings. Pull to retry.',
      style: theme.textTheme.bodyMedium,
    ),
  ),
),
```

Add these helpers as top-level functions in the same file:

```dart
IconData _topicIcon(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => Icons.article_outlined,
  NotificationTopic.events => Icons.event_outlined,
  NotificationTopic.jobs => Icons.work_outline,
  NotificationTopic.shop => Icons.shopping_bag_outlined,
};

Color _topicColor(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => AppColors.defaultBlue,
  NotificationTopic.events => AppColors.accentBlue,
  NotificationTopic.jobs => AppColors.purple9,
  NotificationTopic.shop => AppColors.green9,
};

String _topicSubtitle(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => 'Articles and updates from BISO',
  NotificationTopic.events => 'New campus events and activities',
  NotificationTopic.jobs => 'Volunteer and job opportunities',
  NotificationTopic.shop => 'New items and offers in the BISO shop',
};
```

Below the card, add a line naming the campus, so "Events" visibly means "at your campus, plus national":

```dart
Padding(
  padding: const EdgeInsets.only(top: 8, left: 4),
  child: Text(
    homeCampusId == null
        ? 'You will receive national updates. Set your campus in your profile '
              'to also get campus news.'
        : 'You receive updates for your campus and national updates.',
    style: theme.textTheme.bodySmall?.copyWith(
      color: AppColors.onSurfaceVariant,
    ),
  ),
),
```

If `AppColors.purple9` does not exist, check `lib/core/constants/app_colors.dart` and substitute the nearest defined purple; do not invent a constant.

- [ ] **Step 4: Verify it analyzes and the app builds**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter analyze lib/presentation/screens/profile/settings_screen.dart lib/providers/notification/notification_provider.dart
```

Expected: no errors.

- [ ] **Step 5: Run the full test suite**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/providers/notification/notification_provider.dart lib/presentation/screens/profile/settings_screen.dart
git commit -m "Drive notification settings from the topic taxonomy

The four switches were hardcoded and two of them named topics that do not
exist, so they could never work. Looping over the taxonomy stops the screen
drifting from it again. Also awaits the saved intent instead of rendering
defaults over it on a cold start.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Launch wiring — reconcile on start, and the first-run prompt

Two pieces of launch-time wiring in `BisoApp.build`. They belong together: without the reconciler the prompt is the *only* thing that ever subscribes anyone, so a returning student, a campus move, and a fresh login would all leave the device out of date.

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Flutter/lib/presentation/widgets/notification_topics_prompt.dart`
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/providers/notification/notification_provider.dart`
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/main.dart` (`BisoApp.build`, around line 150)
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/presentation/screens/onboarding/onboarding_screen.dart` (delete the dead step)

**Interfaces:**
- Consumes: `NotificationTopic` (Task 2); `hasAnsweredTopicPrompt`, `saveTopicIntent`, `reconcile`, `requestPermission` (Tasks 5–6).
- Produces: `class NotificationTopicsPrompt extends ConsumerStatefulWidget`, `Future<void> maybeShowTopicsPrompt(BuildContext, WidgetRef)`, and `final topicReconcileProvider = FutureProvider<void>`.

- [ ] **Step 1: Add the launch reconciler provider**

Append to `lib/providers/notification/notification_provider.dart`:

```dart
/// Keeps this device's Appwrite subscriptions in step with the signed-in
/// student and their home campus.
///
/// This is what makes `reconcile()` run at all for a returning student: the
/// prompt only fires once, and the settings screen only fires when a switch is
/// touched. Watching the campus as well means a student who transfers stops
/// receiving their old campus's notifications, which nothing else would
/// trigger.
///
/// Reconciliation is idempotent, so re-running it on every auth or campus
/// change is free when nothing has actually changed.
final topicReconcileProvider = FutureProvider<void>((ref) async {
  final (ready, campusId) = ref.watch(
    authStateProvider.select(
      (state) => (
        !state.isLoading && state.isAuthenticated,
        state.user?.campusId,
      ),
    ),
  );
  if (!ready) return;
  await ref
      .read(notificationServiceProvider)
      .reconcile(campusId: campusId);
});
```

- [ ] **Step 2: Write the prompt widget**

Create `lib/presentation/widgets/notification_topics_prompt.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/notification_topics.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/notification/notification_provider.dart';

/// Asked once, the first time a student reaches the app signed in.
///
/// Covers both entry points identically: a new signup arrives here once
/// onboarding completes, and an existing Appwrite user arrives on their first
/// app login. There is deliberately only one of these — the previous design had
/// a second copy inside onboarding, and it silently discarded every choice.
class NotificationTopicsPrompt extends ConsumerStatefulWidget {
  const NotificationTopicsPrompt({super.key});

  @override
  ConsumerState<NotificationTopicsPrompt> createState() =>
      _NotificationTopicsPromptState();
}

class _NotificationTopicsPromptState
    extends ConsumerState<NotificationTopicsPrompt> {
  late final Map<String, bool> _intent = Map<String, bool>.from(
    kDefaultTopicIntent,
  );
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final service = ref.read(notificationServiceProvider);
    final campusId = ref.read(authStateProvider).user?.campusId;

    // Intent first, and regardless of what the OS dialog returns: declining the
    // system prompt is not the same as wanting nothing, and this choice should
    // take effect if they enable notifications later.
    try {
      await service.saveTopicIntent(_intent);
    } catch (e) {
      debugPrint('NotificationTopicsPrompt: could not save intent: $e');
    }

    await service.requestPermission();
    await service.reconcile(campusId: campusId);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stay in the loop',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.strongBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick what you want to hear about. You will get updates for your '
              'campus and anything BISO publishes nationally.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final topic in NotificationTopic.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(topic.label),
                value: _intent[topic.id] ?? false,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _intent[topic.id] = value),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show the prompt if this student has not answered it yet.
///
/// Safe to call on every build — it checks the stored marker first and does
/// nothing for anyone who has already chosen.
Future<void> maybeShowTopicsPrompt(BuildContext context, WidgetRef ref) async {
  final service = ref.read(notificationServiceProvider);
  if (await service.hasAnsweredTopicPrompt()) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const NotificationTopicsPrompt(),
  );
}
```

- [ ] **Step 3: Mount the gate in `BisoApp`**

In `lib/main.dart`, inside `BisoApp.build`, directly after the existing checkout-controller block (which ends with the closing brace of `if (!ref.watch(authStateProvider.select((state) => state.isLoading)))`), add:

```dart
    // Ask a signed-in student which topics they want, once. Gated the same way
    // as the checkout controller: not until the session has resolved, and only
    // once a profile exists so it never lands on top of onboarding.
    final promptEligible = ref.watch(
      authStateProvider.select(
        (state) =>
            !state.isLoading && state.isAuthenticated && !state.needsOnboarding,
      ),
    );
    if (promptEligible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context != null) {
          maybeShowTopicsPrompt(context, ref);
        }
      });
    }

    // Reconcile this device's subscriptions at launch, and again whenever the
    // student or their campus changes. Nothing else covers a returning user.
    ref.watch(topicReconcileProvider);
```

Add the import at the top of `main.dart`:

```dart
import 'presentation/widgets/notification_topics_prompt.dart';
```

`topicReconcileProvider` comes from the notification provider file, which
`main.dart` already imports; confirm the import is present rather than adding a
duplicate.

- [ ] **Step 4: Delete the dead onboarding step**

In `lib/presentation/screens/onboarding/onboarding_screen.dart`:

1. Delete the entire `_NotificationPreferencesStep` class and its `_NotificationPreferencesStepState` (lines 555 to the end of the file).
2. Remove `_NotificationPreferencesStep(...)` from the `PageView` children (around line 196).
3. Change the step count from 3 to 2: `if (_currentStep < 2)` becomes `if (_currentStep < 1)`; `'${_currentStep + 1} / 3'` becomes `'${_currentStep + 1} / 2'`; `(_currentStep + 1) / 3` becomes `(_currentStep + 1) / 2`.
4. Move the `onComplete: _completeOnboarding` callback onto `_CampusSelectionStep`, which is now the final step. Check its constructor: if it takes `onNext`, pass `_completeOnboarding` there instead and confirm the button label reads as a completion rather than "Next".

- [ ] **Step 5: Verify it analyzes**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter analyze lib/main.dart lib/presentation/screens/onboarding/onboarding_screen.dart lib/presentation/widgets/notification_topics_prompt.dart
```

Expected: no errors. In particular no "unused" warnings for the deleted step.

- [ ] **Step 6: Run the full suite**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/presentation/widgets/notification_topics_prompt.dart lib/providers/notification/notification_provider.dart lib/main.dart lib/presentation/screens/onboarding/onboarding_screen.dart
git commit -m "Reconcile subscriptions at launch, and ask topics once

The onboarding step that collected topic choices never persisted anything -
its local map was read by nothing. Replaced with a single post-auth gate
covering both a new signup and an existing user's first app login, saving
intent before the OS permission request so declining it does not discard
the choice.

Also reconciles at launch and on campus change. The prompt fires once and
the settings screen only on a tap, so without this a returning student, a
fresh login, and a campus move would all leave the device out of date.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Logout cleanup

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/lib/data/services/notification_service.dart` (`clearToken`, the last method)

**Interfaces:**
- Consumes: `DeviceSubscriptionStore` (Task 4).
- Produces: no new API; `clearToken()` gains real Appwrite-side cleanup.

- [ ] **Step 1: Find every caller and confirm ordering**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && grep -rn "clearToken" lib/
```

Read each call site. `clearToken()` must run **before** the Appwrite session is deleted — afterwards `deleteSubscriber` and `deletePushTarget` are unauthorized and silently fail. If any caller deletes the session first, move the call.

- [ ] **Step 2: Replace `clearToken`**

```dart
  /// Detach this device on logout.
  ///
  /// Order matters: the subscriber and target deletions need the session, so
  /// they must happen before it is destroyed. Without this the Appwrite-side
  /// subscriptions survive and the device keeps receiving pushes for an account
  /// that is no longer signed in.
  ///
  /// Intent is deliberately left in account preferences — it is per-user, and
  /// the next login reconciles from it.
  Future<void> clearToken() async {
    final subscriberIds = await _store.readSubscriberIds();
    for (final entry in subscriberIds.entries) {
      try {
        await _messaging.deleteSubscriber(
          topicId: entry.key,
          subscriberId: entry.value,
        );
      } on AppwriteException catch (e) {
        debugPrint('clearToken: could not remove ${entry.key} (${e.code}) ${e.message}');
      }
    }

    final targetId = await _store.readTargetId();
    if (targetId != null) {
      try {
        await _account.deletePushTarget(targetId: targetId);
      } on AppwriteException catch (e) {
        debugPrint('clearToken: could not delete target (${e.code}) ${e.message}');
      }
    }

    await _store.clear();
    _pushTargetId = null;
    _topicSubscriptions.clear();
    _topicSubscriberIds.clear();

    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
    } catch (e) {
      debugPrint('clearToken: could not delete the FCM token: $e');
    }
  }
```

Note this no longer writes to account preferences at all. The old version removed `fcm_token`, `push_target_id` and `topic_subscriptions` from prefs; those keys are now either device-local or intentionally retained.

- [ ] **Step 3: Verify it analyzes and tests pass**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && flutter analyze lib/data/services/notification_service.dart && flutter test
```

Expected: no errors; all tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter
git add lib/data/services/notification_service.dart
git commit -m "Delete this device's subscriptions on logout

clearToken removed local keys but left the Appwrite subscribers and push
target in place, so a signed-out device kept receiving pushes. Runs before
the session is destroyed, since these calls need it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Shared topic mapping and the two live send paths (BISO-Sites)

Deleting the old `events` topic in Task 12 would break event pushes and every broadcast. Both must point at real topics first. `dispatchAnnouncement` catches push errors, so if this is skipped the failure is silent.

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Sites/packages/shared/utils/notification-topics.ts`
- Test: `/Users/markus/Documents/dev/BISO-Sites/packages/shared/utils/notification-topics.test.ts`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/app/(portal)/_actions/events.ts:14` and `:128`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/lib/announcements/send.ts:30`

**Interfaces:**
- Consumes: the topic ids created in Task 1.
- Produces, from `@repo/shared/utils/notification-topics`:
  - `const NOTIFICATION_TOPICS = ["news", "events", "jobs", "shop"] as const`
  - `type NotificationTopic = (typeof NOTIFICATION_TOPICS)[number]`
  - `const GENERAL_TOPIC_ID = "general"`, `const NATIONAL_SLUG = "national"`
  - `function campusSlugFor(campusId?: string | null): string`
  - `function topicIdFor(topic: NotificationTopic, campusId?: string | null): string`

- [ ] **Step 1: Write the failing test**

Create `packages/shared/utils/notification-topics.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  campusSlugFor,
  GENERAL_TOPIC_ID,
  NOTIFICATION_TOPICS,
  topicIdFor,
} from "./notification-topics";

describe("campusSlugFor", () => {
  it("maps each known campus id to its slug", () => {
    expect(campusSlugFor("1")).toBe("oslo");
    expect(campusSlugFor("2")).toBe("bergen");
    expect(campusSlugFor("3")).toBe("trondheim");
    expect(campusSlugFor("4")).toBe("stavanger");
    expect(campusSlugFor("5")).toBe("national");
  });

  it("falls back to national for a missing campus, so content with no campus still reaches everyone", () => {
    expect(campusSlugFor(null)).toBe("national");
    expect(campusSlugFor(undefined)).toBe("national");
    expect(campusSlugFor("")).toBe("national");
  });

  it("falls back to national for an unrecognised campus id", () => {
    expect(campusSlugFor("99")).toBe("national");
  });
});

describe("topicIdFor", () => {
  it("builds a campus-scoped topic id", () => {
    expect(topicIdFor("events", "1")).toBe("events_oslo");
    expect(topicIdFor("news", "3")).toBe("news_trondheim");
  });

  it("builds the national id when the campus is national or absent", () => {
    expect(topicIdFor("jobs", "5")).toBe("jobs_national");
    expect(topicIdFor("shop", null)).toBe("shop_national");
  });
});

describe("the taxonomy", () => {
  it("matches the Flutter client's four logical topics", () => {
    expect([...NOTIFICATION_TOPICS]).toEqual(["news", "events", "jobs", "shop"]);
  });

  it("keeps general out of the campus-scoped set", () => {
    expect(NOTIFICATION_TOPICS).not.toContain(GENERAL_TOPIC_ID);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/packages/shared && bun run test notification-topics
```

Expected: FAIL — cannot resolve `./notification-topics`.

- [ ] **Step 3: Write the implementation**

Create `packages/shared/utils/notification-topics.ts`:

```ts
/**
 * The notification topic taxonomy, server side.
 *
 * Mirrors the Flutter client at
 * `BISO-Flutter/lib/core/constants/notification_topics.dart`. The two must
 * agree — a topic id built here that the app never subscribed to reaches
 * nobody, silently. A change in one needs the same change in the other.
 */

/** The topics a student can opt into. `general` is deliberately not one. */
export const NOTIFICATION_TOPICS = ["news", "events", "jobs", "shop"] as const;

export type NotificationTopic = (typeof NOTIFICATION_TOPICS)[number];

/**
 * The topic every device is subscribed to, whether or not the student chose
 * anything. Used for broadcasts, so that "everyone" means everyone rather than
 * "everyone who happened to opt into events".
 */
export const GENERAL_TOPIC_ID = "general";

export const NATIONAL_SLUG = "national";

const CAMPUS_SLUGS: Record<string, string> = {
  "1": "oslo",
  "2": "bergen",
  "3": "trondheim",
  "4": "stavanger",
  "5": NATIONAL_SLUG,
};

/**
 * The slug for a campus id, falling back to national for anything unknown.
 *
 * The fallback carries meaning: content with no campus is national content, and
 * every subscriber holds the national scope of the topics they chose.
 */
export function campusSlugFor(campusId?: string | null): string {
  if (!campusId) {
    return NATIONAL_SLUG;
  }
  return CAMPUS_SLUGS[campusId] ?? NATIONAL_SLUG;
}

/** The Appwrite topic id a publisher should push to. */
export function topicIdFor(
  topic: NotificationTopic,
  campusId?: string | null
): string {
  return `${topic}_${campusSlugFor(campusId)}`;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/packages/shared && bun run test notification-topics
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Point the event push at the campus-scoped topic**

In `apps/admin/src/app/(portal)/_actions/events.ts`, delete line 14:

```ts
const EVENTS_PUSH_TOPIC_ID = "events";
```

Add to the imports:

```ts
import { topicIdFor } from "@repo/shared/utils/notification-topics";
```

At line 128, inside `sendEventAnnouncement`, replace:

```ts
        audience_value: EVENTS_PUSH_TOPIC_ID,
```

with:

```ts
        // Campus-scoped: a published event notifies students at its own campus,
        // and `topicIdFor` resolves a null campus to the national topic, which
        // every subscriber holds.
        audience_value: topicIdFor("events", input.campusId),
```

- [ ] **Step 6: Point broadcasts at the general topic**

In `apps/admin/src/lib/announcements/send.ts`, replace line 30:

```ts
/** Default app-wide topic used for broadcasts with no explicit topic. */
const DEFAULT_BROADCAST_TOPIC = "events";
```

with:

```ts
import { GENERAL_TOPIC_ID } from "@repo/shared/utils/notification-topics";

/**
 * The topic a broadcast targets.
 *
 * Every device subscribes to `general` unconditionally, so this genuinely means
 * everyone. It used to be "events", which quietly limited every broadcast to
 * students who had opted into event notifications.
 */
const DEFAULT_BROADCAST_TOPIC = GENERAL_TOPIC_ID;
```

Place the `import` with the other imports at the top of the file, not inline.

- [ ] **Step 7: Verify types and the existing suites still pass**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/apps/admin && bun run check-types && bun test ./src
cd /Users/markus/Documents/dev/BISO-Sites/packages/shared && bun run test
```

Expected: no type errors; all tests pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Sites
git add packages/shared/utils/notification-topics.ts packages/shared/utils/notification-topics.test.ts "apps/admin/src/app/(portal)/_actions/events.ts" apps/admin/src/lib/announcements/send.ts
git commit -m "Send to campus-scoped topics, and broadcast to everyone

Mirrors the Flutter taxonomy server-side. Event pushes now target their own
campus topic, and a broadcast targets 'general' - which every device holds -
instead of 'events', which had quietly limited every broadcast to students
who opted into event notifications.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Real subscriber counts in the admin app

**Files:**
- Create: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/lib/notifications/topic-subscribers.ts`
- Test: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/lib/notifications/topic-subscribers.test.ts`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/app/(portal)/events/[id]/page.tsx`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/apps/admin/src/app/(portal)/events/[id]/_components/event-studio-editor.tsx:159` and `:2646`

**Interfaces:**
- Consumes: `topicIdFor` (Task 10).
- Produces:
  - `async function getTopicSubscriberCount(topicId: string): Promise<number | null>` — `null` means "could not determine", never `0`.
  - `async function getEventTopicSubscriberCounts(campusIds: string[]): Promise<Record<string, number | null>>`
  - New prop on `EventStudioEditorProps`: `pushSubscribers: Record<string, number | null>`, keyed by campus id.

The count is keyed by campus because the editor lets a global admin change the event's campus client-side; a single server-fetched number would go stale the moment they did.

- [ ] **Step 1: Write the failing test**

Create `apps/admin/src/lib/notifications/topic-subscribers.test.ts`:

```ts
import { describe, expect, test } from "bun:test";
import { pickPushSubscriberTotal } from "./topic-subscribers";

describe("pickPushSubscriberTotal", () => {
  test("returns the total from a subscriber list", () => {
    expect(pickPushSubscriberTotal({ subscribers: [], total: 42 })).toBe(42);
  });

  test("returns zero when a topic genuinely has no subscribers", () => {
    expect(pickPushSubscriberTotal({ subscribers: [], total: 0 })).toBe(0);
  });

  test(
    "returns null when the total is missing rather than reporting zero - a " +
      "fabricated count is the bug this replaces",
    () => {
      expect(pickPushSubscriberTotal({ subscribers: [] })).toBeNull();
      expect(pickPushSubscriberTotal(undefined)).toBeNull();
    }
  );

  test("returns null for a non-numeric total", () => {
    expect(
      pickPushSubscriberTotal({ subscribers: [], total: "many" })
    ).toBeNull();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/apps/admin && bun test ./src/lib/notifications
```

Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `apps/admin/src/lib/notifications/topic-subscribers.ts`:

```ts
import "server-only";

import { Query } from "@repo/api";
import { createAdminClient } from "@repo/api/server";
import { topicIdFor } from "@repo/shared/utils/notification-topics";
import { unstable_cache } from "next/cache";

/** How long a subscriber count may be stale. Counts move slowly. */
const COUNT_TTL_SECONDS = 300;

/**
 * Read the total off a subscriber list, or `null` if it is not a number.
 *
 * Deliberately never coerces a missing total to `0`. This helper exists to
 * replace a hardcoded, fabricated follower count, and reporting a confident
 * "0 students" when the lookup failed would be the same class of lie.
 */
export function pickPushSubscriberTotal(
  list: { total?: unknown } | undefined
): number | null {
  const total = list?.total;
  return typeof total === "number" ? total : null;
}

/**
 * How many push targets are subscribed to `topicId`.
 *
 * Filtered to `providerType: "push"` because this number is shown next to a
 * push toggle — email targets on the same topic would inflate it. Returns
 * `null` when the count cannot be determined, so callers can say so rather
 * than show a number they cannot stand behind.
 */
export async function getTopicSubscriberCount(
  topicId: string
): Promise<number | null> {
  try {
    const { messaging } = await createAdminClient();
    const list = await messaging.listSubscribers({
      topicId,
      queries: [Query.equal("providerType", "push"), Query.limit(1)],
    });
    return pickPushSubscriberTotal(list);
  } catch (error) {
    console.error(`[topic-subscribers] count failed for ${topicId}:`, error);
    return null;
  }
}

/**
 * Push subscriber counts for the events topic of each campus, keyed by campus
 * id. Fetched in parallel and cached briefly.
 */
export const getEventTopicSubscriberCounts = unstable_cache(
  async (campusIds: string[]): Promise<Record<string, number | null>> => {
    const entries = await Promise.all(
      campusIds.map(
        async (campusId) =>
          [
            campusId,
            await getTopicSubscriberCount(topicIdFor("events", campusId)),
          ] as const
      )
    );
    return Object.fromEntries(entries);
  },
  ["event-topic-subscriber-counts"],
  { revalidate: COUNT_TTL_SECONDS }
);
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/apps/admin && bun test ./src/lib/notifications
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Fetch the counts in the page**

In `apps/admin/src/app/(portal)/events/[id]/page.tsx`, add the import:

```ts
import { getEventTopicSubscriberCounts } from "@/lib/notifications/topic-subscribers";
```

After `filteredCampuses` is computed, add:

```ts
  const pushSubscribers = await getEventTopicSubscriberCounts(
    filteredCampuses.map((c) => c.$id)
  );
```

Pass it to the editor, alongside the existing props:

```tsx
      pushSubscribers={pushSubscribers}
```

- [ ] **Step 6: Consume the count in the editor**

In `apps/admin/src/app/(portal)/events/[id]/_components/event-studio-editor.tsx`:

Delete line 159:

```ts
const PUSH_FOLLOWERS = 4217;
```

Add to `EventStudioEditorProps`:

```ts
  /** Push subscribers per campus id. `null` means the count is unavailable. */
  pushSubscribers: Record<string, number | null>;
```

Destructure `pushSubscribers` from props wherever the other props are destructured.

Replace the notify `ToggleCard` description at line 2646:

```tsx
          description={`Notify ${PUSH_FOLLOWERS.toLocaleString("en-GB")} students who follow this tag. Sends once when published.`}
```

with:

```tsx
          description={describePushAudience(
            pushSubscribers[values.campus_id ?? ""] ?? null
          )}
```

Add this helper near the other module-level helpers in the same file:

```ts
/**
 * What the push toggle promises.
 *
 * An unavailable count says so rather than guessing. The number this replaced
 * was a hardcoded literal, and a wrong count is worse than an absent one when
 * the whole point is telling an admin how many people they are about to reach.
 */
function describePushAudience(count: number | null): string {
  if (count === null) {
    return "Notify students subscribed to events at this campus. Subscriber count unavailable. Sends once when published.";
  }
  if (count === 0) {
    return "No students are subscribed to event notifications at this campus yet. Sends once when published.";
  }
  const students = count === 1 ? "student" : "students";
  return `Notify ${count.toLocaleString("en-GB")} ${students} subscribed to events at this campus. Sends once when published.`;
}
```

- [ ] **Step 7: Verify types, lint and tests**

```bash
cd /Users/markus/Documents/dev/BISO-Sites/apps/admin && bun run check-types && bun run lint && bun test ./src
```

Expected: no type errors, no lint errors, all tests pass.

Note: `STUDENT_POPULATION = 6840` on the next line is a separate hardcoded figure used elsewhere in this editor. It is **out of scope** — do not change it, but mention it in your report so it can be scheduled.

- [ ] **Step 8: Commit**

```bash
cd /Users/markus/Documents/dev/BISO-Sites
git add apps/admin/src/lib/notifications "apps/admin/src/app/(portal)/events/[id]"
git commit -m "Show the real subscriber count on the event push toggle

Replaces a hardcoded 4217. Counts are per campus because a global admin can
change the event's campus in the editor, and are filtered to push targets
since the number sits next to a push toggle. An unavailable count says so
rather than reporting a confident zero.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Retire the old topics

**Do not start this task until Tasks 10 and 11 are deployed** and the Flutter build from Tasks 2–9 has shipped. Removing these earlier points live event pushes and broadcasts at topics that no longer exist, and those failures are swallowed.

**Files:**
- Modify: `/Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json`
- Modify: `/Users/markus/Documents/dev/BISO-Sites/packages/api/appwrite.config.json`

**Interfaces:**
- Consumes: everything above.
- Produces: a topic list of exactly 21 ids.

- [ ] **Step 1: Confirm nothing still references the old ids**

```bash
cd /Users/markus/Documents/dev/BISO-Sites && grep -rn '"events"\|"expenses"\|"orders"\|"products"' apps/admin/src/lib/announcements "apps/admin/src/app/(portal)/_actions/events.ts" | grep -i topic
grep -rn "'products'\|'expenses'" lib/data/services/notification_service.dart lib/presentation/screens/profile/settings_screen.dart
```

Expected: no matches. Any hit here is a consumer that will break — fix it before continuing.

Note the admin composer's `TOPIC_OPTIONS` in `announcement-studio-editor.tsx` **will** still list the old ids. That is expected and owned by spec 2. Confirm with the user that no admin will hand-send to a topic between this task and spec 2 shipping; if that is a risk, do Task 12 after spec 2 instead.

- [ ] **Step 2: Write the topics editor**

Same tool as Task 1, re-created here so this task stands alone. It edits the
topics array as text rather than re-serialising the file, because neither
config survives a JSON round-trip without a five-figure reformat.

```bash
mkdir -p /Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions
cat > /Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions/topics_edit.py <<'TOPICS_EDIT_EOF'
"""Add or remove Appwrite topics by editing the config TEXT, never re-serialising it.

Round-tripping these configs through json.dump rewrites unrelated content: it
expands Biome's single-line arrays in the Sites config, and renormalises float
literals (1.0e+19 -> 1e+19) in the Flutter one. Both are invisible to JSON
semantics and both bury the real change in a 10,000-line diff. Editing text
directly leaves every byte outside the topics array untouched by construction.

Usage:  topics_edit.py add    CONFIG
        topics_edit.py remove CONFIG
"""
import json
import re
import sys

CAMPUS = [('oslo', 'Oslo'), ('bergen', 'Bergen'), ('trondheim', 'Trondheim'),
          ('stavanger', 'Stavanger'), ('national', 'National')]
LOGICAL = [('news', 'News'), ('events', 'Events'), ('jobs', 'Jobs'), ('shop', 'Shop')]
LEGACY = ['news', 'events', 'expenses', 'orders', 'jobs']


def find_topics_array(text):
    """Return (index of '[', index of matching ']') for the topics array."""
    m = re.search(r'"topics"\s*:\s*\[', text)
    if not m:
        raise SystemExit('no "topics" array found')
    start = m.end() - 1
    depth, i, in_str, esc = 0, start, False, False
    while i < len(text):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0:
                return start, i
        i += 1
    raise SystemExit('unterminated "topics" array')


def split_objects(body):
    """Split an array body into its top-level object texts, in order."""
    objs, depth, i, obj_start, in_str, esc = [], 0, 0, None, False, False
    while i < len(body):
        ch = body[i]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == '{':
            if depth == 0:
                obj_start = i
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                objs.append((obj_start, i + 1, body[obj_start:i + 1]))
        i += 1
    return objs


def write(path, text):
    json.loads(text)  # refuse to write anything that is not valid JSON
    open(path, 'w').write(text)


def do_add(path, text, start, end):
    body = text[start + 1:end]
    existing = {t['$id'] for t in json.loads(text[start:end + 1])}

    wanted = [(f'{lid}_{cs}', f'{ll} — {cl}')
              for lid, ll in LOGICAL for cs, cl in CAMPUS]
    wanted.append(('general', 'Important announcements'))
    added = [(tid, name) for tid, name in wanted if tid not in existing]
    if not added:
        print(f'{path}: nothing to add; total {len(existing)}')
        return

    obj_indent = (re.search(r'\n(\s+)\{', body) or [None, '  '])[1]
    key_m = re.search(r'\n(\s+)"\$id"', body)
    key_indent = key_m.group(1) if key_m else obj_indent + '  '
    close_indent = re.search(r'(\s*)$', body).group(1).lstrip('\n')

    chunks = [
        f'{obj_indent}{{\n'
        f'{key_indent}"$id": "{tid}",\n'
        f'{key_indent}"name": "{name}",\n'
        f'{key_indent}"subscribe": ["users"]\n'
        f'{obj_indent}}}'
        for tid, name in added
    ]
    stripped = body.rstrip()
    joined = ',\n'.join(chunks)
    new_body = (f'{stripped},\n{joined}\n{close_indent}' if stripped.endswith('}')
                else f'\n{joined}\n{close_indent}')

    write(path, text[:start + 1] + new_body + text[end:])
    print(f'{path}: added {len(added)} topics; total {len(existing) + len(added)}')


def do_remove(path, text, start, end):
    body = text[start + 1:end]
    objs = split_objects(body)
    keep = []
    removed = []
    for s, e, obj_text in objs:
        tid = json.loads(obj_text)['$id']
        (removed if tid in LEGACY else keep).append((tid, obj_text))
    if not removed:
        print(f'{path}: nothing to remove; total {len(keep)}')
        return

    obj_indent = (re.search(r'\n(\s+)\{', body) or [None, '  '])[1]
    close_indent = re.search(r'(\s*)$', body).group(1).lstrip('\n')
    # split_objects returns each object starting at its '{', without the
    # leading whitespace, so re-apply the array's own indent to every one.
    joined = ',\n'.join(obj_indent + t for _, t in keep)
    new_body = f'\n{joined}\n{close_indent}' if keep else ''

    write(path, text[:start + 1] + new_body + text[end:])
    print(f'{path}: removed {len(removed)} topics ({", ".join(t for t, _ in removed)}); '
          f'total {len(keep)}')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('add', 'remove'):
        raise SystemExit(__doc__)
    op, cfg = sys.argv[1], sys.argv[2]
    txt = open(cfg).read()
    s, e = find_topics_array(txt)
    (do_add if op == 'add' else do_remove)(cfg, txt, s, e)
TOPICS_EDIT_EOF
echo written
```

- [ ] **Step 2b: Remove the five legacy topics from both configs**

```bash
WS=/Users/markus/Documents/dev/BISO-Flutter/.superpowers/sdd/2026-09-09-topic-subscriptions
python3 "$WS/topics_edit.py" remove /Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json
python3 "$WS/topics_edit.py" remove /Users/markus/Documents/dev/BISO-Sites/packages/api/appwrite.config.json
```

Expected: each reports `removed 5 topics (news, events, expenses, orders, jobs); total 21`.

Confirm the change is purely subtractive — **zero insertions** on both:

```bash
git -C /Users/markus/Documents/dev/BISO-Flutter diff --stat -- appwrite.config.json
git -C /Users/markus/Documents/dev/BISO-Sites diff --stat -- packages/api/appwrite.config.json
```

Expected: deletions only (35 in Flutter, 25 in Sites — they differ because the
legacy entries are formatted differently in each). Any insertion means the file
was reformatted; do not commit.


Expected: both report `26 -> 21`.

- [ ] **Step 3: Verify the final topic set**

```bash
python3 -c "
import json
t=json.load(open('/Users/markus/Documents/dev/BISO-Flutter/appwrite.config.json'))['topics']
ids=sorted(x['\$id'] for x in t)
assert len(ids)==21, ids
assert 'general' in ids
assert 'events' not in ids and 'products' not in ids
print('OK:', ids)
"
```

Expected: 21 ids, none of them the legacy names.

- [ ] **Step 4: Commit in both repos**

```bash
cd /Users/markus/Documents/dev/BISO-Flutter && git add appwrite.config.json && git commit -m "Retire the pre-campus notification topics

Every consumer now targets a campus-scoped topic or 'general'. Expenses and
orders are gone entirely - they become personal notifications rather than
topics anyone subscribes to.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
cd /Users/markus/Documents/dev/BISO-Sites && git add packages/api/appwrite.config.json && git commit -m "Retire the pre-campus notification topics

Mirrors the Flutter repo's appwrite.config.json.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand back to the user to push**

Report that the config is ready and that pushing it deletes the five old topics and their subscribers.

---

## Manual verification before merge

These cannot be unit-tested and must be checked on a real device against the real project. Report the result of each honestly — "not checked" is an acceptable answer, "assumed working" is not.

- [ ] **A push actually arrives.** With the app signed in and subscribed to Events, send a push to `events_<your campus>` from the Appwrite console. It arrives on the device.
- [ ] **Second launch keeps working.** Force-quit and relaunch. Toggle a topic off and on in settings. It still works — this is the 409 path from Task 5, and the bug it fixes only ever appeared on the *second* run.
- [ ] **The prompt appears once.** A fresh install on an account that has never chosen shows the sheet. Relaunching does not show it again.
- [ ] **An existing user is not re-prompted.** An account with an old `topic_subscriptions` map goes straight in, with `products` carried over as `shop`.
- [ ] **Campus change resubscribes.** Change the profile campus; confirm in the Appwrite console that the old campus topic lost a subscriber and the new one gained one.
- [ ] **Logout leaves nothing behind.** Sign out, then confirm in the console that this device's subscribers and push target are gone.
- [ ] **The event card shows a real number.** Open an event in the admin app and confirm the push toggle reports a plausible count that changes when you switch campus.

## Notes for spec 2

Discovered while planning, not fixed here:

- `TOPIC_OPTIONS` in `announcement-studio-editor.tsx:145` still lists `events`, `products`, `jobs` — two of which will not exist after Task 12. Spec 2 rewrites this UI against the taxonomy.
- The `announcements` table has no `email` column; `dispatchAnnouncement` only calls `createPush`.
- Emailing a topic needs the user's **email** target subscribed to it. This plan subscribes only the push target.
- `STUDENT_POPULATION = 6840` in the event editor is another hardcoded figure with no source.
