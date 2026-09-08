# Screen Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the consumption bugs found by walking the migrated screens on a device, and clear the dead code the three migrations left behind.

**Architecture:** No new data layer. Every fix either uses data the app already fetches, removes UI with no data source, or deletes code with no callers. Tasks are independent and can land in any order.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, `appwrite` Dart SDK, `flutter_riverpod`, `equatable`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-07-appwrite-content-migration-design.md` (§7, screen audit)

**Plan 4 of 4.** Plans 1–3 (shared layer + events, jobs, webshop) are complete. Events, jobs and webshop products all read from Appwrite; only expenses still use `api.biso.no`.

## Findings, and how each was established

Everything below was observed on the simulator or verified against live Appwrite — not inferred.

| # | Finding | Evidence |
|---|---|---|
| A | Campus switcher shows **"0.0k Students" and "0 Events" for every campus** | `getSwitcherCampuses` builds `stats: const CampusStats()` (`campus_service.dart:160`); `_getCampusStats` is only reachable from `_buildCampusModel`, used by `getCampusById`. Seen on device |
| B | **RenderFlex overflow, 5.9px** in the home hero header | `EXCEPTION CAUGHT BY RENDERING LIBRARY` in the run log, at `dynamic_hero_carousel.dart:330`. Visible yellow/black stripes on device |
| C | The **explore** jobs card shows less than the **home** card for the same job | Explore card is title + deadline + "View Details"; home card renders a description. `tags` (99/100 live jobs) and `shortDescription` are fetched, parsed, in `props`, and rendered nowhere on explore |
| D | A campus switch **mid-fetch** can append a stale page into the freshly reset list | Identical shape in `marketplace_screen._loadMoreWebshop` and `events_screen`/`jobs_screen._fetchPage`: each reads campus via `ref.read`, awaits, then `setState`s without re-checking |
| E | The **empty state is unreachable by pull-to-refresh** on events and jobs | `_EmptyState` sits outside the `RefreshIndicator` in both screens, so a user on an empty campus cannot refresh |
| F | Dead code the migrations left behind | `EventException` (zero throwers/catchers), `WebshopService`'s uncalled `category` parameter, orphan `saleMessage` l10n key, stale `'No visible jobs after filters'` log wording, redundant single-child wrappers |
| G | `getProductById` duplicates the select list that `buildProductQueries` owns | `webshop_service.dart` — add a nested relation to one and the other silently won't fetch it |

**`studentCount` has no data source at all.** The `campus_data` table is **empty (0 rows)** in live Appwrite, so the Students badge cannot be made correct — only removed or left lying. `activeEvents` and `availableJobs` *can* be computed: `EventService.countEvents` and `JobService.countJobs` already exist and are proven.

## Deliberately out of scope

- **Localization.** The migrated screens carry hardcoded English (`'Welcome to BISO'`, `'Students'`, `'Events'`, `'Options'`, `'Additional information'`, `'Continue'`, `'This field is required'`, `'Apply by …'`, `'View Details'`, `'Description'`). Fixing it means new ARB entries plus regeneration across `app_en.arb` / `app_no.arb` and generated Dart — a different kind of work with a different risk profile, and large enough to deserve its own plan rather than being smuggled into an audit. It is a real gap on screens whose whole purpose is bilingual content; it is not forgotten.
- **Search on the jobs board.** `listJobs` has a working server-side `search` parameter but the UI is commented out (`jobs_screen.dart:233-234`). Wiring it is a feature, not an audit fix.
- **Membership-gated pricing**, still blocked on data (spec §6; see plan 3's ruling).
- **The stale generated schema** under `lib/schema/` — regenerate with `appwrite types -l dart` when convenient; no app code reads it.

## Global Constraints

- Use data the app already fetches; never invent a value to fill a widget.
- If a widget has no data source, remove it rather than rendering a zero or placeholder.
- Never render a raw Appwrite enum (`status`, `inventory_mode`, `cover_pattern`) to users.
- Never render `field_key`; it is an opaque id.
- Reuse `EventService.countEvents` / `JobService.countJobs`; do not hand-roll a `listRows` count.
- Every field added to a model must also be added to `props`.
- Never `git add -A` / `git add .` / `git commit -a` / `git add <directory>` — the tree carries unrelated WIP. Stage explicit paths.
- Run `flutter analyze` and `flutter test` before each commit; 139 tests pass today.

---

### Task 1: Campus switcher stats

**Files:**
- Modify: `lib/data/services/campus_service.dart`
- Modify: `lib/presentation/widgets/campus_switcher.dart`
- Test: `test/data/services/campus_stats_test.dart`

**Interfaces:**
- Consumes: `EventService.countEvents({String? campusId, bool includePast})`, `JobService.countJobs({String? campusId, bool includeExpired})`.
- Produces: `getSwitcherCampuses` returning campuses whose `stats.activeEvents` and `stats.availableJobs` are real counts.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/models/campus_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CampusStats', () {
    test('defaults every counter to zero', () {
      const s = CampusStats();
      expect(s.activeEvents, 0);
      expect(s.availableJobs, 0);
    });

    test('carries real counts when supplied', () {
      const s = CampusStats(activeEvents: 3, availableJobs: 16);
      expect(s.activeEvents, 3);
      expect(s.availableJobs, 16);
    });

    test('two stats differing only in availableJobs are not equal', () {
      expect(
        const CampusStats(activeEvents: 1, availableJobs: 2),
        isNot(equals(const CampusStats(activeEvents: 1, availableJobs: 3))),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `flutter test test/data/services/campus_stats_test.dart`

If `CampusStats` already satisfies these, say so in your report — this test is a regression guard for Step 3, not a driver. If the equality test fails, `props` is incomplete: fix that first.

- [ ] **Step 3: Populate the counts in `getSwitcherCampuses`**

Replace `stats: const CampusStats()` (`campus_service.dart:160`) with real counts, fetched per campus in parallel, mirroring how `_getCampusStats` already does it:

```dart
final eventService = EventService();
final jobService = JobService();

Future<CampusStats> statsFor(String campusId) async {
  // Each counter degrades to 0 independently: one failing count must not
  // blank the whole switcher.
  final results = await Future.wait([
    eventService.countEvents(campusId: campusId).catchError((_) => 0),
    jobService.countJobs(campusId: campusId).catchError((_) => 0),
  ]);
  return CampusStats(activeEvents: results[0], availableJobs: results[1]);
}
```

Keep the existing `includeWeather` behavior unchanged.

- [ ] **Step 4: Remove the Students badge**

`campus_switcher.dart:509-515` renders `'${(campus.stats.studentCount / 1000).toStringAsFixed(1)}k'` with the label `Students`. `studentCount` has **no data source** — the `campus_data` table is empty in live Appwrite — so it always reads `0.0k`.

Remove that `_StatBadge` and the `SizedBox` that separates it from the next one. Do **not** substitute a placeholder.

If `studentCount` becomes unreferenced anywhere in `lib/`, remove it from `CampusStats` and from `props`; if something else still reads it, leave the field and say so.

- [ ] **Step 5: Verify**

Run: `flutter analyze && flutter test`

- [ ] **Step 6: Commit**

```bash
git add lib/data/services/campus_service.dart lib/presentation/widgets/campus_switcher.dart \
        test/data/services/campus_stats_test.dart
git commit -m "fix: show real event and job counts in the campus switcher"
```

---

### Task 2: Hero header overflow

**Files:**
- Modify: `lib/presentation/widgets/dynamic_hero_carousel.dart`

- [ ] **Step 1: Reproduce**

Run the app and select the campus with the longest name (Trondheim or Stavanger). The run log shows:

```
A RenderFlex overflowed by 5.9 pixels on the right.
  Row:file:///.../dynamic_hero_carousel.dart:330:17
```

Confirm you see the yellow/black stripes before changing anything, and record the pixel count for the campus you tested — it is larger for longer names.

- [ ] **Step 2: Fix the layout**

The header `Row` (`:330`) holds a fixed `Text('Welcome to BISO')` next to a nested `Row` containing the notification bell and the campus button. The text does not shrink, so a long campus name overflows.

Wrap the `Text` in a `Flexible` and give it `overflow: TextOverflow.ellipsis` so it yields space to the buttons. Do not shrink the buttons — the campus name is the more important of the two, and truncating a greeting is harmless.

- [ ] **Step 3: Verify on every campus**

Run the app and switch through **all** campuses including National (`campus_id` `'5'` exists in live data — do not assume a 1–4 range). Confirm zero overflow exceptions in the run log:

```bash
grep -c "RenderFlex overflowed" <run log>
```
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/widgets/dynamic_hero_carousel.dart
git commit -m "fix: stop the home hero header overflowing for long campus names"
```

---

### Task 3: Explore jobs card parity

**Files:**
- Modify: `lib/presentation/screens/explore/jobs_screen.dart`

The explore card renders title + deadline + "View Details". The **home** card for the same job renders a description. `tags` (populated on 99 of 100 live jobs) and `shortDescription` are already fetched, parsed and in `props` — they are simply not rendered on explore, which makes the dedicated jobs screen the *sparser* of the two views of the same data.

- [ ] **Step 1: Render `shortDescription`**

Add it under the title, guarded on non-null and non-empty, with `maxLines` and ellipsis so cards stay uniform. Match the home card's treatment (`premium_home_screen.dart`) rather than inventing a new style.

`shortDescription` is plain text, not HTML — do **not** run it through `toFullHtml`.

- [ ] **Step 2: Render `tags`**

Add a chip row, capped at three, following the pattern the events card already uses (`events_screen.dart` `_chipLabels`) — including its case-insensitive de-duplication, so a repeated tag does not consume a slot.

If the job has no tags, render nothing — no empty row, no placeholder.

- [ ] **Step 3: Verify on device**

Run the app, open Explore → Volunteer on campus 1 (16 open jobs today). Confirm cards show a description and tags, that a job with no tags renders no empty row, and that card heights stay reasonable.

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/explore/jobs_screen.dart
git commit -m "feat: show description and tags on the explore jobs card"
```

---

### Task 4: Stale-page race and unreachable empty state

**Files:**
- Modify: `lib/presentation/screens/explore/events_screen.dart`
- Modify: `lib/presentation/screens/explore/jobs_screen.dart`
- Modify: `lib/presentation/screens/explore/marketplace_screen.dart`

Two defects that exist in the same shape in all three screens. Fix them the same way in all three — the value here is that the screens stay identical to each other.

- [ ] **Step 1: Guard the in-flight page append**

Each screen's paging method reads the campus via `ref.read`, awaits a fetch, then `setState`s the result into its accumulator without re-checking. If the user switches campus mid-fetch, the in-flight page lands in the freshly reset list, mixing campuses.

Capture the campus (and, for `marketplace_screen`, the locale) into a local before the await, and after the await drop the result if it no longer matches the current value. Return early rather than calling `setState`.

Use the same guard shape in all three files.

- [ ] **Step 2: Make the empty state refreshable**

In `events_screen.dart` and `jobs_screen.dart`, `_EmptyState` is rendered *outside* the `RefreshIndicator`, so a user looking at an empty campus cannot pull to refresh — exactly when they would most want to.

Move it inside, wrapped so it still fills the viewport and remains scrollable enough to trigger the gesture (an `AlwaysScrollableScrollPhysics` list with a single sliver-fill child, or equivalent).

Verify by pulling to refresh on campus 3 for jobs — it has **0 open jobs** today.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`

Run the app: switch campus rapidly while a page is loading on each of the three screens and confirm no mixed-campus list appears.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/explore/events_screen.dart \
        lib/presentation/screens/explore/jobs_screen.dart \
        lib/presentation/screens/explore/marketplace_screen.dart
git commit -m "fix: drop stale pages on campus switch and allow refresh when empty"
```

---

### Task 5: Dead code sweep

**Files:**
- Modify: `lib/data/services/event_service.dart`
- Modify: `lib/data/services/webshop_service.dart`
- Modify: `lib/presentation/screens/explore/jobs_screen.dart`
- Modify: `lib/generated/l10n/app_en.arb`, `app_no.arb` and the generated Dart
- Modify: `lib/presentation/screens/explore/marketplace_screen.dart`, `lib/presentation/screens/home/premium_home_screen.dart`

**Grep before deleting each item; if anything still reads it, leave it and say so in your report.**

- [ ] **Step 1: `EventException`**

`event_service.dart` — every thrower was removed when the legacy methods went. Confirm zero throwers and zero catchers, then delete.

- [ ] **Step 2: `WebshopService`'s `category` parameter**

`buildProductQueries` / `_productFilters` accept a `category` that no caller passes and no test covers — the category chips are gated to marketplace mode and `_WebshopQuery` has no category field. Remove the parameter and its filter branch. It is trivially re-added with a test when something actually needs it.

- [ ] **Step 3: Share the select list in `getProductById`**

`getProductById` re-declares `['*', 'translation_refs.*', 'variations.*', 'custom_fields.*']` and the published filter that `_productFilters` / `buildProductQueries` already own. Add a nested relation to the list read and the by-id read silently would not fetch it.

Extract the select list to a single private constant used by both, and add a test asserting the by-id query selects all four entries.

- [ ] **Step 4: `saleMessage` orphan**

Remove the now-unused `saleMessage` key from `app_en.arb` and `app_no.arb`, and regenerate so the generated Dart matches. Do not hand-edit generated files.

- [ ] **Step 5: Stale log wording**

`jobs_screen.dart` still logs `'[JOBS_SCREEN] No visible jobs after filters'` and a `visible_count` that now always equals `loaded_count` — there are no client-side filters any more. Correct the wording and drop the redundant field.

- [ ] **Step 6: Redundant single-child wrappers**

`marketplace_screen.dart` and `premium_home_screen.dart` carry single-child `Row`/`Column` wrappers left behind when siblings were deleted. Collapse them. Purely cosmetic — do not change any rendered output.

- [ ] **Step 7: Verify**

Run: `flutter analyze && flutter test`

- [ ] **Step 8: Commit**

Stage each changed file by explicit path.

```bash
git commit -m "refactor: remove dead code left by the Appwrite migrations"
```

---

## Verification

- `flutter analyze` reports no errors; `flutter test` passes.
- `grep -c "RenderFlex overflowed"` over a fresh run log across all five campuses returns `0`.
- The campus switcher shows real event and job counts, and no Students badge.
- The explore jobs card shows a description and tags.
- Pull-to-refresh works on an empty jobs board (campus 3 has 0 open jobs today).
- Switching campus mid-fetch never mixes campuses in a list.

## Follow-on

- **Localization of the migrated screens** — its own plan, per the scope note above.
- Wiring the jobs board's server-side search to a UI.
- Membership-gated pricing, once product-level member data exists.
- Regenerating `lib/schema/` with `appwrite types -l dart`.
