# Topic Subscriptions That Actually Work — Design

**Date:** 2026-09-09
**Status:** Approved for planning
**Scope:** Make Appwrite Messaging topic subscriptions functional end-to-end — topic
taxonomy, Flutter push-target and subscription wiring, the first-run subscribe prompt,
the profile settings screen, and honest subscriber counts in the admin app.

This is **spec 1 of 3** in the communications work:

| Spec | Covers |
|---|---|
| **1 (this one)** | Topic subscriptions that actually work — the plumbing |
| 2 | Admin composer email channel + automated publish notifications (news / jobs / shop) |
| 3 | Personal notifications — expense lifecycle + Finago booking poller |

Specs 2 and 3 both depend on this one: neither can deliver a notification until a device
has a working push target.

## Goal

Today a student can toggle notification topics in three separate places and **none of them
do anything**. The toggles write to a preferences map that is either discarded outright or
keyed to topic ids that do not exist, and the underlying push target is never successfully
created after the first launch.

Make the following true:

1. A student is asked once, on first app login, which topics they want.
2. Their choice is stored, survives reinstalls and new devices, and is editable in profile
   settings.
3. Their device is genuinely subscribed to the corresponding Appwrite topics, and a push
   sent to one of those topics actually arrives.
4. Content only reaches students it is relevant to, by campus.
5. The admin app can state a true subscriber count instead of a hardcoded one.

## Verified ground truth

Everything below was verified by **reading the code in both repositories** on 2026-09-09.
It was *not* verified against live Appwrite — the Appwrite MCP server is unauthorized in
this session. Items marked **[assumed]** need confirmation against the live project before
or during implementation.

### The topic taxonomy disagrees in three places

| Source | Topic ids |
|---|---|
| Appwrite (`appwrite.config.json`, identical in both repos) | `news`, `events`, `expenses`, `orders`, `jobs` |
| Flutter defaults, settings screen, onboarding step | `events`, **`products`**, `jobs`, `expenses` |
| Admin composer `TOPIC_OPTIONS` | `events`, **`products`**, `jobs` |

`products` is not a topic, so subscribing to it fails. `news` and `orders` exist but have no
UI in either app.

### Flutter push wiring is broken in seven distinct ways

All in `lib/data/services/notification_service.dart` unless noted.

1. **Wrong provider id.** `_createPushTarget` passes `providerId: 'fcm'`. The project's FCM
   provider `$id` is `push`. Target creation fails outright.

2. **Re-registration always 409s.** `_createPushTarget` always calls `createPushTarget` with
   a fresh `ID.unique()`. On the second launch the same FCM token collides with the existing
   target. The `catch` swallows it, `_pushTargetId` stays `null`, and every subsequent
   `subscribeToTopic` returns early at `'No push target available'` — silently, with only a
   `debugPrint`. **This is the single bug that makes topic subscription impossible in
   practice**, and it hides behind the same log line as a genuine first-run failure.

3. **`initialize()` never establishes a target.** It configures Firebase and fetches a token
   but never calls `_createPushTarget` or `_loadTopicSubscriptions`. Only `requestPermission()`
   does. A returning user who already granted permission therefore has no target in memory
   for the whole session.

4. **Settings screen reads unloaded state.** `NotificationPreferencesNotifier._loadPreferences()`
   (`lib/providers/notification/notification_provider.dart`) reads the in-memory
   `topicSubscriptions` map without awaiting `ensureTopicSubscriptionsLoaded()`. On a fresh
   start it renders hardcoded defaults over the user's saved choices.

5. **Per-user storage for per-device state.** `push_target_id` and `topic_subscriber_ids`
   live in Appwrite *account preferences*, which are per-user. A push target is per-device.
   A second device overwrites the first's ids; unsubscribing on device B deletes device A's
   subscriber.

6. **Logout orphans subscriptions.** `clearToken()` removes the preference keys and deletes
   the FCM token, but never calls `deleteSubscriber` or `deletePushTarget`. The Appwrite-side
   subscriptions survive.

7. **The onboarding step is dead UI.** `_NotificationPreferencesStep`
   (`lib/presentation/screens/onboarding/onboarding_screen.dart:555`) holds a local
   `_preferences` map. `_completeOnboarding()` never reads it. Nothing is persisted, no OS
   permission is requested, nothing is subscribed. The four switches are decorative.

### Admin side

8. `PUSH_FOLLOWERS = 4217` is a literal in
   `apps/admin/src/app/(portal)/events/[id]/_components/event-studio-editor.tsx:159`.

9. The unified dispatch path is good and worth building on:
   `apps/admin/src/lib/announcements/send.ts` already resolves audience by
   `audience_type` (`topic` / `broadcast` / `segment` / `users`), builds a stable push `data`
   map, applies row-level read permissions, and fans out `user_notifications`. Event publish
   already routes through it via `sendEventAnnouncement`.

### Appwrite platform constraints

10. **The client SDK cannot list subscribers.** Verified directly against the installed
    Dart SDK (`appwrite-26.1.0`): `lib/services/messaging.dart` exposes exactly two methods —
    `createSubscriber` and `deleteSubscriber`. There is no list operation; listing subscribers
    is an API-key (server) call. The app therefore *cannot* read its own subscriptions back
    from Appwrite and must remember them locally. **This is the constraint that drives the
    whole state model below.**

11. **A topic contains targets, not users.** `createPush` reaches only push targets in a
    topic; `createEmail` reaches only email targets. Emailing a topic (spec 2) will require
    the user's *email* target to be subscribed as well — this spec deliberately subscribes
    only the push target, and spec 2 revisits it.

12. **`account.get()` returns the user's targets.** `models.User` carries a
    `List<Target> targets` field, and `Account` exposes `createPushTarget`,
    `updatePushTarget` and `deletePushTarget` (same SDK version). This is what makes the 409
    recovery in section D possible: the existing target for a known FCM token can be found
    and adopted rather than blindly recreated.

13. **Campus `5` is National and is modelled as a real campus.** Confirmed by the user; the
    id mapping is corroborated by `SHOP_CAMPUS_DEPARTMENT_IDS` in
    `packages/connectors/src/24sevenoffice/rest/transactions.ts`.

14. **[assumed]** The existing five topics have effectively no real subscribers, since
    subscription has never worked. Deleting them is therefore non-destructive. Worth a
    glance in the console before pushing the config.

## Decisions

Settled with the user during brainstorming:

| Question | Decision |
|---|---|
| Topic list | `news`, `events`, `jobs`, `shop`. Drop `expenses` and `orders` — those become personal sends in spec 3. No marketplace topic (student-generated, too noisy). |
| Campus scoping | Campus-scoped topic ids, with a `_national` scope everyone holds. |
| State storage | Intent per-user in account prefs; subscriber ids per-device in local storage; reconcile on launch. |
| Prompt | One post-auth gate, single code path, covering both new signups and existing users' first app login. |

## Design

### A. Topic model

Four logical topics × five campus scopes = 20 Appwrite topics, id format
`<topic>_<campusSlug>`:

```
news_oslo    news_bergen    news_trondheim    news_stavanger    news_national
events_oslo  events_bergen  events_trondheim  events_stavanger  events_national
jobs_oslo    jobs_bergen    jobs_trondheim    jobs_stavanger    jobs_national
shop_oslo    shop_bergen    shop_trondheim    shop_stavanger    shop_national
```

Plus one non-campus-scoped topic, `general`, for service announcements that must reach
everyone (see section J). Twenty-one topics total. All carry `subscribe: ["users"]`.

`general` is the one topic a user does not choose: `reconcile()` subscribes every device to
it unconditionally. It exists so a true broadcast has exactly one topic to target, which
avoids both the "broadcast reaches only events subscribers" bug described in section J and
the question of whether Appwrite de-duplicates a target that appears in several topics of
one message. Students who want nothing can still turn notifications off at the OS level.

**These ids are internal.** No user ever sees one. The UI offers exactly four choices —
News, Events, Jobs, Shop — and the system derives the campus half from the profile's
`campus_id`.

Campus slug mapping (the `campus` table has no slug column, so this is a hardcoded map):

| `campus_id` | slug |
|---|---|
| `1` | `oslo` |
| `2` | `bergen` |
| `3` | `trondheim` |
| `4` | `stavanger` |
| `5` | `national` |
| null, absent, or unrecognised | `national` |

The fallback is deliberate and load-bearing, not defensive padding: a profile campus is
genuinely optional — onboarding lets `_selectedCampusId` stay null — so "no campus" is a
state real users will be in. Those students get the national scope, meaning they receive
national content and no campus content, rather than silently receiving nothing at all.

**Subscribing to logical topic `T` means subscribing to two Appwrite topics:**
`T_<home campus slug>` and `T_national`. A publisher pushes to exactly one topic — the
content's own campus scope, or `_national` when the content is national. Because every
subscriber holds the national half, publishing to `*_national` reaches everyone who opted
into that logical topic, on every campus.

Notifications follow the profile's **home** `campus_id`, not the campus switcher used for
browsing. Browsing Bergen for an afternoon must not resubscribe the device.

This mapping is needed in both repositories. It lives in one clearly-named file per repo
(`lib/core/constants/notification_topics.dart` and a `@repo/shared` equivalent), each
carrying a comment pointing at the other. Cross-repo duplication is unavoidable; making it
obvious is the mitigation.

### B. State model

Two stores, split by what the data is actually scoped to:

**Appwrite account preferences** (per-user, survives reinstall and new devices):

```jsonc
{
  "notification_topics": { "news": true, "events": true, "jobs": true, "shop": false },
  "notification_topics_set_at": "2026-09-09T10:00:00.000Z"
}
```

`notification_topics` is *intent* — which logical topics this student wants, campus-free.
`notification_topics_set_at` records that the prompt has been answered; its absence is what
triggers the prompt.

**Device-local `SharedPreferences`** (per-device, matches the scope of a push target):

```jsonc
{
  "push_target_id": "<appwrite target $id>",
  "topic_subscriber_ids": { "events_oslo": "<subscriber $id>", "events_national": "..." }
}
```

The subscriber ids are the only reason this store exists: they are required to unsubscribe,
and constraint 10 means Appwrite will not tell us what they are.

Account prefs remain the write path for intent, so a new device inherits choices. Nothing
per-device is ever written to account prefs again — that is the fix for bug 5.

### C. `reconcile()` — the only mutator

One function becomes the sole thing that creates or deletes subscriptions. Everything else
edits intent and calls it.

```
reconcile():
  1. If OS notification permission is not granted → return.
     Intent stays saved and applies whenever they enable it.
  2. Resolve the push target (see D). On failure → return without touching subscriptions.
  3. desired = { "{t}_{homeCampusSlug}", "{t}_national" for each t where intent[t] is true }
  4. current = keys of local topic_subscriber_ids
     - for id in desired - current:  createSubscriber → store returned $id
     - for id in current - desired:  deleteSubscriber → drop the entry
  5. Persist the local map.
```

Because step 4 is a **diff against observed state** rather than a sequence of imperative
toggles, `reconcile()` is idempotent — running it twice is a no-op. That property is what
makes the multi-device case work without coordination: each device independently reconciles
*its own* target against the *shared* intent, and they never interfere.

Called on: app start after auth resolves, OS permission grant, intent change, **home campus
change**, FCM token refresh, and login.

The diff itself (step 3–4) is extracted as a pure function taking `(intent, campusSlug,
currentMap)` and returning `(toCreate, toDelete)`. No Appwrite, no I/O, fully unit-testable.

### D. Push-target resolution

The fix for bugs 1–3, and the most failure-prone part of the whole design. Ordered by
likelihood so the common path is one call:

```
resolvePushTarget(token):
  1. If a local push_target_id exists:
       updatePushTarget(targetId, identifier: token)   // handles token refresh
       on success → return that id
       on 404 → fall through (target was deleted server-side)
  2. createPushTarget(ID.unique(), identifier: token, providerId: 'push')
       on success → store and return
  3. On 409 (a target already holds this identifier):
       account.get().targets → find the target whose identifier == token
       adopt its $id, store it, return it
  4. If all three fail → log the real error and return null.
```

Step 3 is the recovery the current code lacks entirely. Note `providerId: 'push'`, not
`'fcm'`.

Failures here must **log the underlying Appwrite error**, not a generic string. The present
code's uniform `'No push target available'` is why this has been broken silently.

### E. The first-run prompt

A single sheet widget, shown from one post-auth gate when **all** of:

- auth has resolved to a signed-in user,
- a profile exists (so it never fires mid-onboarding),
- `notification_topics_set_at` is absent from account prefs.

Flow: explain the value → four toggles (News, Events, Jobs, Shop) → save intent and
`notification_topics_set_at` → request OS permission → `reconcile()`.

Intent is saved **before** the OS permission request and regardless of its outcome. A
student who declines the system dialog has still expressed a preference, and it takes effect
if they later enable notifications in settings.

`_NotificationPreferencesStep` and its call site in the onboarding flow are **deleted**. The
gate covers new signups (it fires once onboarding completes) and existing Appwrite users'
first app login through the identical path. Two entry points writing the same state is how
bug 7 happened; this spec deliberately has one.

### F. Settings screen

`lib/presentation/screens/profile/settings_screen.dart`:

- Replace the four hardcoded `SwitchListTile`s with a loop over the logical topic list, so
  the screen cannot drift from the taxonomy again.
- Fix `_loadPreferences()` to `await ensureTopicSubscriptionsLoaded()` before reading (bug 4).
- Drop the `expenses` toggle; spec 3 replaces it with personal notifications.
- Show the home campus, so "Events" visibly means "events at your campus, plus national".
- Every toggle writes intent, then calls `reconcile()`.

### G. Subscriber counts (admin)

A small server-side helper in `apps/admin`:

```ts
getTopicSubscriberCount(topicId): Promise<number>
  → messaging.listSubscribers(topicId, [Query.limit(1)]).total
```

Cached briefly (counts move slowly; a 5-minute revalidate is ample), and failing **closed**:
if the count cannot be fetched, the UI says so rather than showing a number it cannot stand
behind. A wrong count is worse than an absent one — the whole point is replacing a fabricated
figure.

Wired into the event studio's notify card, replacing `PUSH_FOLLOWERS`. The count shown is
for the topic the event will actually publish to — `events_<its campus>` — so it answers the
question the admin is actually asking.

The rest of the admin work (email channel, news/jobs/shop triggers) is spec 2. This piece is
included here because it is a handful of lines and it is the cheapest end-to-end proof that
the topic model is real.

### H. Migration for existing users

Existing accounts carry `topic_subscriptions` in prefs with the old ids. On first run of the
new code, when `notification_topics` is absent but `topic_subscriptions` is present:

| Old | New |
|---|---|
| `events` | `events` |
| `products` | `shop` |
| `jobs` | `jobs` |
| `expenses` | dropped (spec 3) |
| — | `news` defaults to `true` |

Write `notification_topics` and set `notification_topics_set_at`, so a student who already
made a choice is not re-prompted.

Stale `topic_subscriber_ids` in account prefs are discarded rather than cleaned up: they
reference topics this spec deletes, and deleting a topic removes its subscribers.

### I. Logout

`clearToken()` gains real cleanup, in this order:

1. `deleteSubscriber` for every entry in the local map (best-effort, continue on failure).
2. `deletePushTarget` for this device's target.
3. Clear local device storage.
4. Delete the FCM token.

All of this must run **before** the session is destroyed — afterwards the calls are
unauthorized. Intent stays in account prefs; the next login re-reconciles from it.

### J. Existing send paths that must migrate

Deleting the current topics breaks two live paths in `apps/admin`. Both must move in this
spec — leaving them pointed at a deleted topic would make event pushes and every broadcast
fail *silently*, because `dispatchAnnouncement` catches and logs push errors without
surfacing them. That is precisely the failure mode this spec exists to remove.

1. **`EVENTS_PUSH_TOPIC_ID = "events"`** (`_actions/events.ts:14`) — the topic
   `sendEventAnnouncement` writes into `announcement.audience_value` on event publish.
   Becomes derived: `events_<slug for the event's campus_id>`, using the shared mapping.

2. **`DEFAULT_BROADCAST_TOPIC = "events"`** (`lib/announcements/send.ts:30`) — the topic used
   for `audience_type: "broadcast"`. Becomes `general`.

Note that (2) is not merely a rename: a "broadcast" today reaches only students subscribed
to *events*, which has been wrong independently of this work. Pointing it at `general`, which
every device holds, makes the audience match the name.

The admin composer's own stale `TOPIC_OPTIONS` list stays in spec 2, which rewrites that UI
wholesale. Only these two server-side constants move now, because only they would break.

## Error handling

The governing principle is that **a failure must not look like a success**, which is
precisely how the current code fails.

- Every swallowed Appwrite error logs the actual error object, not a generic message.
- `reconcile()` is best-effort per topic: one failing `createSubscriber` does not abort the
  others, and the local map records only what actually succeeded. The next `reconcile()`
  retries the rest, because the diff recomputes from observed state.
- A failed push-target resolution short-circuits `reconcile()` rather than proceeding to
  subscribe against a null target.
- The settings screen surfaces a failed toggle to the user and reverts the switch, rather
  than leaving the UI asserting a subscription that does not exist.
- Admin subscriber counts fail closed (see G).

## Testing

TDD, alongside the existing `test/data/services/notification_service_prefs_test.dart` and
`notification_service_retry_test.dart`.

The valuable logic is pure and is extracted so it can be tested without a network:

| Unit | Cases |
|---|---|
| Topic id derivation | each campus id → slug; unmapped id → `national`; intent → the two topic ids per logical topic |
| Reconcile diff | no-op when matched; create-only; delete-only; mixed; campus change swaps the campus half and keeps `_national`; all-off deletes everything |
| Intent migration | old map → new map; `products`→`shop`; `expenses` dropped; `news` default; absent old map → defaults; already-migrated map untouched |
| Prefs decoding | extends existing coverage for the `[]`-instead-of-`{}` shape to the new keys |

Appwrite calls stay in a thin shell around these, driven in tests through the existing
`NotificationService.withAccount` seam.

Not unit-tested, and called out honestly as manual verification before merge:

- A real push sent to `events_oslo` arriving on a device subscribed via the app.
- Second-launch behaviour — that bug 2's 409 path adopts the existing target.
- Logout leaving no subscribers behind.

## Schema changes

Only `appwrite.config.json` (both repos hold a copy; both need updating). The `topics` array
is replaced wholesale:

```jsonc
"topics": [
  { "$id": "news_oslo",       "name": "News — Oslo",        "subscribe": ["users"] },
  { "$id": "news_bergen",     "name": "News — Bergen",      "subscribe": ["users"] },
  { "$id": "news_trondheim",  "name": "News — Trondheim",   "subscribe": ["users"] },
  { "$id": "news_stavanger",  "name": "News — Stavanger",   "subscribe": ["users"] },
  { "$id": "news_national",   "name": "News — National",    "subscribe": ["users"] },
  // …the same five scopes for events, jobs and shop
]
```

...plus the single `general` topic:

```jsonc
{ "$id": "general", "name": "Important announcements", "subscribe": ["users"] }
```

Twenty-one in total. The five current topics (`news`, `events`, `expenses`, `orders`,
`jobs`) are removed. See assumption 14.

**No table changes.** `announcements` gains its `email` column in spec 2, not here.

## Out of scope

Deliberately deferred, to keep this spec reviewable:

- Email as a channel, and subscribing email targets to topics (spec 2).
- The admin composer's topic picker, which shares the same stale `TOPIC_OPTIONS` bug — spec 2
  rewrites it against the taxonomy this spec establishes. Only the two server-side constants
  in section J move now, because only they would break outright.
- Publish-triggered announcements for news, jobs and shop products (spec 2).
- All personal notifications, including expense status and the Finago booking poller (spec 3).
- Segment audiences, still disabled as "Phase 2" in the composer.
- Any notification for student-marketplace listings.
