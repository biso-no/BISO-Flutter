# Inbox Read State and Clearing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inbox read state survives restarts and devices, and students can clear notifications by swiping a row or with a filter-scoped "Clear all".

**Architecture:** Two `apps/api` routes (BISO-Sites) write the student's `user_notifications` rows with the admin key; the table stays closed to clients. The Flutter app lists every announcement (broadcast, topic and targeted) from `announcements`, reads state rows for exactly those ids, drops cleared ones, and writes through a new API client. The inbox notifier lays in-flight reads and clears over every fetch so a refresh never undoes them.

**Tech Stack:** BISO-Sites: Next.js route handlers, `@repo/api` (node-appwrite), vitest, bun. BISO-Flutter: Flutter 3.32 / Dart 3.8, Riverpod `StateNotifier`, `appwrite` 26.2, `http`, gen-l10n.

**Spec:** `docs/superpowers/specs/2026-10-22-inbox-read-and-clear-design.md` (approved mockup in `docs/superpowers/specs/2026-10-22-inbox-read-and-clear/clear-flow.html`).

## Global Constraints

- Repos: BISO-Sites at `/Users/markus/Documents/dev/BISO-Sites` (Tasks 1-3), BISO-Flutter at `/Users/markus/Documents/dev/BISO-Flutter` (Tasks 4-7). Work on a branch `feat/inbox-read-and-clear` off `main` in each.
- Routes: `POST /api/notifications/read` and `POST /api/notifications/clear`, body `{"announcementIds": [...]}`, 1-100 ids, each matching `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$`, duplicates ignored.
- Responses: `200 {"ok":true}`, `400 {"error":"invalid_request"}`, `401 {"error":"not_authenticated"}`, `429 {"error":"rate_limited"}`, `503 {"error":"unavailable"}`; every response `Cache-Control: private, no-store` with CORS from `@/lib/cors`.
- The student is the JWT's account (`account.get()`); the body never names a user.
- Rows the API creates: `{user_id, announcement_id, read: true, cleared: <true for clear, false for read>}`, permissions exactly `[Permission.read(Role.user(userId))]` (`'read("user:<id>")'`).
- `read` writes only `{read: true}`; `clear` writes `{read: true, cleared: true}`. Nothing ever writes `false` to an existing row.
- Any existing announcement id is written, whatever its `status`; unknown ids are skipped without an error.
- `user_notifications` table-level permissions stay `[]`. No client `createRow`/`updateRow` on it remains in the app.
- New column: `cleared`, boolean, `required: false`, `default: false`.
- App batches: at most `kNotificationsApiBatchSize = 100` ids per request.
- Flutter design rules (`test/presentation/design_rules_test.dart`): CupertinoIcons only (no `Icons.`), colors from `BisoPalette.of(context)` / `BisoAccent`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Nothing in Tasks 1-7 touches the live Appwrite project or deploys. Task 8 does, and only after the user says go.

## Review Focus

1. A refresh whose fetch started before a clear succeeded, landing after it: the cleared rows stay hidden. (Task 6)
2. The inbox notifier is disposed (sign-out, campus or language change) while a read or clear is in flight: no state is written after dispose and nothing throws. (Task 6)
3. A read for a notification already cleared on another device: it stays cleared, because the read writes only `read`. (Task 2)
4. "Clear all" over more than 100 rows where a later batch fails: only that batch's rows come back. (Tasks 5 and 6)
5. Dragging a burst card strip sideways: the strip scrolls and the row is not cleared. (Task 7)

---

### Task 1: `cleared` column in the BISO-Sites schema config and types

**Files:**
- Modify: `packages/api/appwrite.config.json` (the `user_notifications` table, near line 2972)
- Modify: `packages/api/types/appwrite.ts` (`UserNotifications`, near line 808)

**Interfaces:**
- Produces: `UserNotifications` gains `cleared: boolean`.

- [ ] **Step 1: Create the branch**

Run: `cd /Users/markus/Documents/dev/BISO-Sites && git switch main && git pull && git switch -c feat/inbox-read-and-clear`
Expected: on `feat/inbox-read-and-clear`, clean tree.

- [ ] **Step 2: Add the column to the config**

After the `read` column of `user_notifications`, add `{"key": "cleared", "type": "boolean", "required": false, "array": false, "default": false}`. Leave `$permissions: []` and the indexes as they are.

- [ ] **Step 3: Regenerate the types**

Run: `cd packages/api && bun run types:generate && git diff --stat types/`
Expected: `UserNotifications` gains `cleared: boolean;`. If the run changes other types, keep only the `UserNotifications` change (`git checkout -p types/appwrite.ts`).

- [ ] **Step 4: Type-check**

Run: `cd packages/api && bun run check-types`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add packages/api/appwrite.config.json packages/api/types/appwrite.ts
git commit -m "feat(api): cleared column on user_notifications"
```

### Task 2: Notification state writes (`apps/api/src/lib/notification-state.ts`)

**Files:**
- Create: `apps/api/src/lib/notification-state.ts`
- Test: `apps/api/src/lib/notification-state.test.ts`

**Interfaces:**
- Consumes: `ID`, `Permission`, `Query`, `Role` from `@repo/api`.
- Produces:
  - `type NotificationStateAction = "read" | "clear"`
  - `const MAX_ANNOUNCEMENT_IDS = 100`
  - `function parseAnnouncementIds(body: unknown): string[] | null` - the deduplicated ids, in first-seen order, or null when the body is not `{announcementIds: string[]}` with 1-100 valid ids.
  - `interface NotificationStateDb { listRows<T>(table: string, queries: string[]): Promise<{ rows: T[] }>; createRow(table: string, id: string, data: Record<string, unknown>, permissions: string[]): Promise<unknown>; updateRow(table: string, id: string, data: Record<string, unknown>): Promise<unknown>; }` - bound to database `app`, as `RevealDb` is in `benefits/[id]/reveal/route.ts`.
  - `async function applyNotificationState(db: NotificationStateDb, input: { userId: string; announcementIds: string[]; action: NotificationStateAction }): Promise<void>` - resolves once every write landed; rejects if any failed.

- [ ] **Step 1: Write the failing tests**

A fake `NotificationStateDb` built from `vi.fn()`s; `listRows` answers by table (`announcements` → the known ids as `{ $id }`, `user_notifications` → existing rows `{ $id, announcement_id, read, cleared }`).

`describe("parseAnnouncementIds")`:
- `parseAnnouncementIds({ announcementIds: ["a", "b", "a"] })` → `["a", "b"]`
- 100 distinct valid ids → all 100
- each of these → `null`: `null`, `"x"`, `{}`, `{ announcementIds: "a" }`, `{ announcementIds: [] }`, 101 distinct ids, `{ announcementIds: ["bad id"] }`, `{ announcementIds: ["-a"] }`, `{ announcementIds: [7] }`, an id of 37 characters

`describe("applyNotificationState")`:
- `it("creates a row readable only by the student")`: no existing row for `a1`, action `read` → `createRow("user_notifications", expect.any(String), { user_id: "user-1", announcement_id: "a1", read: true, cleared: false }, ['read("user:user-1")'])`
- `it("clear creates the row read and cleared")` → same, with `read: true, cleared: true`
- `it("updates an existing fan-out row instead of creating one")`: existing `{ $id: "row-1", announcement_id: "a1" }`, action `clear` → `updateRow("user_notifications", "row-1", { read: true, cleared: true })`; `createRow` not called
- `it("a read never touches cleared")` (Review Focus 3): existing row `cleared: true`, action `read` → `updateRow` data is exactly `{ read: true }`
- `it("skips ids that are not announcements")`: ids `["a1", "ghost"]`, only `a1` known → one write, for `a1`
- `it("writes an announcement that has not been sent yet")`: the `announcements` queries contain no `status` filter
- `it("looks up announcements and state rows for the whole batch at once")`: `announcements` queries equal `[Query.equal("$id", ids), Query.select(["$id"]), Query.limit(ids.length)]`; `user_notifications` queries contain `Query.equal("user_id", "user-1")` and `Query.equal("announcement_id", knownIds)`
- `it("a create that loses the race becomes an update")`: `createRow` rejects `{ code: 409 }`, the re-read returns `{ $id: "row-9", announcement_id: "a1" }` → `updateRow("user_notifications", "row-9", { read: true })`
- `it("rejects when a write fails")`: `updateRow` rejects `{ code: 500 }` → `applyNotificationState(...)` rejects

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/notification-state.test.ts`
Expected: FAIL, cannot resolve `./notification-state`.

- [ ] **Step 3: Implement `parseAnnouncementIds` and `applyNotificationState`**

Look up known announcements, then the student's rows for them, then write every id in parallel (`Promise.all`). Already-satisfied rows may be skipped. On a create rejected with code 409, re-read that one row (`user_id` + `announcement_id`, limit 1) and update it.

- [ ] **Step 4: Run them to see them pass**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/notification-state.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/notification-state.ts apps/api/src/lib/notification-state.test.ts
git commit -m "feat(api): write a student's notification read and clear state"
```

### Task 3: The two routes

**Files:**
- Create: `apps/api/src/lib/notification-state-route.ts`
- Create: `apps/api/src/app/api/notifications/read/route.ts`
- Create: `apps/api/src/app/api/notifications/clear/route.ts`
- Test: `apps/api/src/app/api/notifications/read/route.test.ts`, `apps/api/src/app/api/notifications/clear/route.test.ts`

**Interfaces:**
- Consumes: Task 2's `parseAnnouncementIds`, `applyNotificationState`, `NotificationStateAction`; `createAuthenticatedClient` (`@/lib/auth`); `createAdminClient` (`@repo/api/server`); `createRateLimiter` (`@repo/shared/member-pass/rate-limit`); `applyCorsHeaders`, `corsPreflightResponse` (`@/lib/cors`).
- Produces: `function notificationStateRoute(action: NotificationStateAction): (req: NextRequest) => Promise<NextResponse>`. Each route file exports `dynamic = "force-dynamic"`, `POST = notificationStateRoute("read" | "clear")` and an `OPTIONS` returning `corsPreflightResponse(origin)`.

- [ ] **Step 1: Write the failing route tests**

Mock `@/lib/auth` and `@repo/api/server` as `apps/api/src/app/api/profile/route.test.ts` does (`account.get` resolves `{ $id: "user-1" }`; the admin `db` has `listRows`, `createRow`, `updateRow`; `listRows` for `announcements` returns the ids it was asked for).

`read/route.test.ts`:
- `it("requires a bearer token")` → 401 `{ error: "not_authenticated" }`, no `listRows` call
- `it("refuses a token Appwrite does not accept")`: `account.get` rejects → 401
- `it("refuses a body without valid ids")`: `{ announcementIds: [] }` → 400 `{ error: "invalid_request" }`
- `it("writes for the token's account, never one from the body")`: body `{ announcementIds: ["a1"], userId: "someone-else" }` → 200 `{ ok: true }`; `createRow` data has `user_id: "user-1"`
- `it("answers unavailable when a write fails")`: `createRow` rejects `{ code: 500 }` → 503 `{ error: "unavailable" }`
- `it("limits each student to 60 requests a minute")`: for a student id used only by this test, request 61 → 429 `{ error: "rate_limited" }`
- `it("is never cached")`: the 200's `Cache-Control` is `private, no-store`

`clear/route.test.ts`:
- `it("clears for the token's account")` → 200; `createRow` data has `read: true, cleared: true`

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/notifications`
Expected: FAIL, the route modules do not exist.

- [ ] **Step 3: Implement `notificationStateRoute` and the two route files**

Order inside the handler: bearer header present, then `account.get()`, then `parseAnnouncementIds(await req.json().catch(() => null))`, then the rate limiter (one module-level `createRateLimiter({ limit: 60, windowMs: 60_000 })` shared by both actions, keyed by user id), then `applyNotificationState` with the admin `db` bound to `"app"`. On a failed write, log only the error's code and type (as `errorSummary` does in the reveal route), never ids, then answer 503.

- [ ] **Step 4: Run them to see them pass, plus the API's own checks**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/notifications src/lib/notification-state.test.ts && bun run check-types && bun run lint`
Expected: PASS; no type or lint errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/notification-state-route.ts apps/api/src/app/api/notifications
git commit -m "feat(api): POST /api/notifications/read and /clear"
```

### Task 4: Flutter schema mirror and `NotificationsApiClient`

**Files:**
- Modify: `appwrite.config.json` (the `user_notifications` table)
- Modify: `lib/types/user_notifications.dart` (generated)
- Create: `lib/data/services/notifications_api_client.dart`
- Test: `test/data/services/notifications_api_client_test.dart`

**Interfaces:**
- Consumes: `ApiJwtProvider`, `ApiJwtInvalidator`, `appwriteJwt`, `clearAppwriteJwtCache`, `apiUri` from `lib/data/services/api_auth.dart`.
- Produces:
  - `const int kNotificationsApiBatchSize = 100;`
  - `abstract interface class NotificationsApi { Future<void> markRead(List<String> announcementIds); Future<void> clear(List<String> announcementIds); }`
  - `enum NotificationsApiErrorKind { notDeployed, notAuthenticated, invalidRequest, rateLimited, unavailable, network, unknown }`
  - `class NotificationsApiException implements Exception { const NotificationsApiException(this.kind, {this.statusCode}); final NotificationsApiErrorKind kind; final int? statusCode; }`, whose `toString` names only the status and kind
  - `class NotificationsApiClient implements NotificationsApi { NotificationsApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider, ApiJwtInvalidator? invalidateJwt}); }`

- [ ] **Step 1: Create the branch and mirror the column**

Run: `cd /Users/markus/Documents/dev/BISO-Flutter && git switch -c feat/inbox-read-and-clear`, then commit the design and this plan on it: `git add docs/superpowers/specs/2026-10-22-inbox-read-and-clear-design.md docs/superpowers/specs/2026-10-22-inbox-read-and-clear docs/superpowers/plans/2026-10-22-inbox-read-and-clear.md && git commit -m "docs: inbox read state and clearing design and plan"`. Add the same `cleared` column as Task 1 Step 2 to `appwrite.config.json`. Then run `appwrite types -l dart ./lib/types` and keep only the `lib/types/user_notifications.dart` change.
Expected: `UserNotifications` gains `bool? cleared` in its fields, `fromMap` and `toMap`.

- [ ] **Step 2: Write the failing client tests**

Follow `test/data/services/benefits_api_client_test.dart` (`MockClient`, `jwtProvider: () async => 'jwt-1'`, a `failsWith(kind)` matcher):
- `markRead(['a', 'b'])` sends `POST https://api.biso.no/api/notifications/read`, headers `Authorization: Bearer jwt-1` and a JSON content type, body `{"announcementIds":["a","b"]}`; a 200 `{"ok":true}` completes
- `clear(['a'])` sends `POST https://api.biso.no/api/notifications/clear`
- a 401 calls the invalidator and retries once with the provider's next token; a second 401 → `failsWith(notAuthenticated)`
- 404 with no error token → `notDeployed`; 400 `invalid_request` → `invalidRequest`; 429 `rate_limited` → `rateLimited`; 503 `unavailable` → `unavailable`; a `http.ClientException` → `network`
- an empty list completes without sending a request
- 101 ids → `throwsArgumentError`, nothing sent
- `NotificationsApiException(...).toString()` contains neither an id nor the token

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/data/services/notifications_api_client_test.dart`
Expected: FAIL, the library does not exist.

- [ ] **Step 4: Implement `NotificationsApiClient`**

Mirror `BenefitsApiClient`'s `_send`/`_sendOnce`/`_token`/`_failure` (one 401 retry with a fresh token, 20 s timeout, the `^[a-z_]{1,40}$` token check), sending a JSON body.

- [ ] **Step 5: Run them to see them pass**

Run: `flutter test test/data/services/notifications_api_client_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add appwrite.config.json lib/types/user_notifications.dart lib/data/services/notifications_api_client.dart test/data/services/notifications_api_client_test.dart
git commit -m "feat(notifications): API client for inbox read and clear"
```

### Task 5: Inbox service reads every announcement, then its state

**Files:**
- Modify: `lib/data/services/notification_inbox_service.dart` (`fetchInbox`, `markAsRead`, constructor; add `clear`)
- Modify: `lib/providers/notification/notification_provider.dart:567` (the one `markAsRead` call, to keep the build green)
- Test: `test/data/services/notification_inbox_service_test.dart`

**Interfaces:**
- Consumes: Task 4's `NotificationsApi`, `NotificationsApiClient`, `kNotificationsApiBatchSize`.
- Produces:
  - `NotificationInboxService({TablesDB? tablesDb, NotificationsApi? api})`, defaulting `api` to `NotificationsApiClient()`
  - `Future<void> markAsRead(String announcementId)`, which throws `NotificationInboxException` when the API fails (replaces `markAsRead(AppNotification, {required String userId})`)
  - `Future<Set<String>> clear(List<String> announcementIds)`, which returns the ids that were not cleared (empty when all were) and never throws for an API failure
  - `fetchInbox` keeps its signature

- [ ] **Step 1: Write the failing tests**

Extend `_FakeTablesDB` to record `user_notifications` reads the way it records `announcementReads`. Add a `_FakeNotificationsApi implements NotificationsApi` that records each call's ids and can fail chosen calls.

New `group('fetchInbox read state')`:
- `test('lists targeted announcements from announcements: sent, audience_type users or segment, newest sent_at first, limit 50, selected columns')`: one announcements read has `equal audience_type ['users','segment']`, `equal status ['sent']`, `orderDesc sent_at`, `limit 50` and a `select`
- `test('shows a targeted announcement that has no user_notifications row')`
- `test('shows a targeted announcement however many newer rows the student has')`: 60 newer rows for other announcements → the targeted one is still listed
- `test('reads state for exactly the announcements shown, at most 25 ids a read')`: every `user_notifications` read has `equal user_id ['u']`; its `announcement_id` lists have ≤ 25 values and together equal the shown ids
- `test('marks an announcement read from its row')`
- `test('drops cleared announcements: broadcast, topic and targeted')`
- `test('finds the state of an announcement whose row is older than 50 newer ones')`: its row says `cleared: true` → not listed

The existing `'a user_notifications row does not let a hidden broadcast back in, but a users-audience row still shows'` must still pass unchanged.

New `group('markAsRead and clear')`:
- `test('markAsRead sends the one id')` → api.markRead called with `['a']`
- `test('markAsRead throws NotificationInboxException when the API fails')`
- `test('clear sends the ids once each, in batches of 100, in order')`: 250 ids (with one duplicate) → calls of 100, 100, 50
- `test('clear returns only the ids of a batch that failed')` (Review Focus 4): the second call fails → the result equals that call's 100 ids
- `test('clear with no ids sends nothing')` → `{}` and no call

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/data/services/notification_inbox_service_test.dart`
Expected: FAIL (no `api` parameter, no `clear`, no targeted read).

- [ ] **Step 3: Implement the service changes**

In `fetchInbox`: drop step 1 (newest 50 `user_notifications` rows) and step 3 (missing announcements by id, with its audience re-check). Add a targeted read beside the broadcast and topic reads (`Future.wait` is fine). Then read state rows with `Query.equal('user_id', userId)`, `Query.equal('announcement_id', chunk)`, `Query.limit(chunk.length)` per `_idChunkSize` chunk. Skip `cleared == true`, take `read` and `userNotificationId` (`row.$id`) from the row, then apply `joinedAt` and the sort as before. Targeted rows skip the audience checks, as before. Update the class doc and `fetchInbox` doc to say `user_notifications` holds state only. Change the notifier's call to `_service.markAsRead(notification.id)`.

- [ ] **Step 4: Run the service tests and the analyzer**

Run: `flutter test test/data/services/notification_inbox_service_test.dart && flutter analyze lib/data/services lib/providers/notification`
Expected: PASS; no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/notification_inbox_service.dart lib/providers/notification/notification_provider.dart test/data/services/notification_inbox_service_test.dart
git commit -m "fix(notifications): inbox state comes from the API's rows, by announcement"
```

### Task 6: Inbox notifier: optimistic, honest, no flicker

**Files:**
- Modify: `lib/providers/notification/notification_provider.dart` (`NotificationInboxNotifier`, lines ~444-578)
- Test: `test/providers/notification/notification_inbox_notifier_test.dart` (new)

**Interfaces:**
- Consumes: Task 5's `markAsRead(String)` and `clear(List<String>) → Set<String>`.
- Produces:
  - `Future<void> markRead(AppNotification notification)` (same signature). Never sets `state.error`.
  - `Future<bool> clear(Iterable<String> announcementIds)` resolves `true` when every id was cleared and `false` when any came back. The rows leave `state.items` synchronously, before the first `await`, because a `Dismissible` must be gone by the next frame.

- [ ] **Step 1: Write the failing tests**

Fakes: an inbox service subclass overriding `fetchInbox` (queued results, optionally held by a `Completer`), `markAsRead` and `clear` (held or failing on demand), and `subscribe` (a `RealtimeSubscription` over a local `StreamController`). A `NotificationService` built with `NotificationService.withAccount`, as `notification_provider_test.dart` builds `_FakeNotificationService`, with `loadTopicIntent` → `{}` and `onForegroundMessage` → `Stream.empty()`. Include that file's `path_provider` channel mock.

- `test('markRead shows the row read at once and keeps it read once saved')`
- `test('a failed markRead puts the row back to unread without setting an error')`: `unreadCount` returns to its old value; `state.error` is null
- `test('clear removes the rows before its first await and resolves true once saved')`
- `test('a failed clear puts the rows back in their old places and resolves false')`
- `test('a refresh landing while a clear is in flight keeps the rows hidden')`
- `test('a refresh fetched before a clear succeeded keeps the rows hidden when it lands after')` (Review Focus 1)
- `test('a refresh landing while a read is in flight keeps the row read')`
- `test('only the failed batch\'s rows come back')` (Review Focus 4): the service returns a subset → exactly that subset is back
- `test('disposing while a read or clear is in flight writes no state and throws nothing')` (Review Focus 2)
- `test('unreadCount never counts a cleared notification')`

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/providers/notification/notification_inbox_notifier_test.dart`
Expected: FAIL (`clear` does not exist; the read is not reverted).

- [ ] **Step 3: Implement the notifier**

Keep the last fetched list and two id sets, `_readIds` and `_clearedIds`. Add an id when its request starts, and remove it only when its request fails; success leaves it there, since read and cleared are permanent. Every publish builds `state.items` from the fetched list: drop ids in `_clearedIds`, mark ids in `_readIds` read. `load`, `refresh`, `markRead` and `clear` all publish this way. Guard every state write after an `await` with `mounted`. `markRead` no longer refreshes after saving; the realtime subscription covers other devices. An unexpected throw from `clear` counts every id as failed.

- [ ] **Step 4: Run the provider tests and the earlier suites**

Run: `flutter test test/providers/notification test/data/services/notification_inbox_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification/notification_provider.dart test/providers/notification/notification_inbox_notifier_test.dart
git commit -m "fix(notifications): a read or clear shows at once and reverts only if it fails"
```

### Task 7: Swipe to clear, "Clear all", copy

**Files:**
- Modify: `lib/generated/l10n/app_en.arb`, `lib/generated/l10n/app_no.arb` (then regenerate the `app_localizations*.dart` files)
- Modify: `lib/presentation/screens/notifications/notifications_screen.dart` (`_buildSlivers`, `_group`, `_FilterChips`; add `_confirmClearAll`, `_clear`)
- Modify: `lib/presentation/screens/notifications/inbox_widgets.dart` (add `InboxClearBackground`)
- Modify: `test/presentation/screens/notifications/smart_inbox_test.dart:346`, `test/presentation/screens/notifications/notifications_design_test.dart:98` (new empty title)
- Modify: `CLAUDE.md` (a short "Notification inbox" entry under the implemented features)
- Test: `test/presentation/screens/notifications/inbox_clear_test.dart` (new)

**Interfaces:**
- Consumes: Task 6's `NotificationInboxNotifier.clear(Iterable<String>) → Future<bool>`; `pinUrgent`, `groupByDay`, `applyFilter` (`lib/core/utils/inbox_layout.dart`); `showBisoSheet`, `BisoListGroup`, `BisoListRow(destructive: true)`, `BisoIconTile`.
- Produces: `class InboxClearBackground extends StatelessWidget` (the red swipe background).

- [ ] **Step 1: Add the copy**

New keys in `app_en.arb` / `app_no.arb`, with `@` descriptions:

| key | en | no |
|---|---|---|
| `inboxClearAll` | `Clear all` | `Fjern alle` |
| `inboxClear` | `Clear` | `Fjern` |
| `inboxClearConfirmTitle` (`count`: int) | `{count, plural, =1{Clear 1 notification?} other{Clear {count} notifications?}}` | `{count, plural, =1{Fjerne 1 varsel?} other{Fjerne {count} varsler?}}` |
| `inboxClearConfirmMessage` | `They're removed from your inbox on all your devices.` | `De fjernes fra innboksen på alle enhetene dine.` |
| `inboxClearFailed` | `Couldn't clear. Try again.` | `Kunne ikke fjerne. Prøv igjen.` |

Change `inboxEmptyTitle` to `You're all caught up` / `Du er à jour`. Cancel reuses `cancel`. Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget tests**

In `inbox_clear_test.dart`, reuse `smart_inbox_test.dart`'s `_n`, `_pump` and `pumpBisoScreen` setup. Its fake inbox also implements `clear`: it records each call's ids, removes them from its state synchronously, and resolves a configurable bool. When that bool is `false`, it puts them back.

- `testWidgets('swiping a row right to left clears it')`: drag `'Fresh note'` by `Offset(-500, 0)`, settle → one call with `['a']`, the text is gone
- `testWidgets('swiping left to right does nothing')`
- `testWidgets('each row offers a Clear action to screen readers')`: invoking the row's `Clear` custom semantics action → one call with that row's id
- `testWidgets('Clear all under a filter clears only the rows on screen, pinned urgent rows included, after confirming')`: items event `e1`, news `n1`, urgent `u1` (unread, 1 h old), filter Events, tap `Clear all` → `Clear 2 notifications?` and `They're removed from your inbox on all your devices.` shown; tap `Clear` → one call with `{'u1', 'e1'}`; `n1` untouched
- `testWidgets('Cancel clears nothing')`
- `testWidgets('Clear all is hidden when nothing is on screen')`: an empty inbox, and a filter with no rows
- `testWidgets('a clear that fails says so')`: fake resolves `false` → `Couldn't clear. Try again.` shown
- `testWidgets('Norwegian copy')`: locale `no` → `Fjern alle`; after tapping it, `Fjerne 2 varsler?`
- `testWidgets('dragging the burst card strip sideways scrolls it and does not clear the row')` (Review Focus 5): a burst with three items; drag `'Bergen event 1'` by `Offset(-200, 0)` → no clear call
- `testWidgets('an empty inbox says You\'re all caught up')`

Update the two existing `'No notifications yet'` expectations to `'You\'re all caught up'`.

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/presentation/screens/notifications`
Expected: the new tests FAIL; the two updated expectations FAIL until the copy is in.

- [ ] **Step 4: Implement the UI**

- `_group`: wrap each row in `Dismissible(key: ValueKey('clear-${n.id}'), direction: DismissDirection.endToStart, background: const InboxClearBackground(), onDismissed: (_) => _clear([n.id]))`, around a `Semantics` carrying `CustomSemanticsAction(label: l10n.inboxClear)` → `_clear([n.id])`. The key moves from `InboxRow` to the `Dismissible`.
- `InboxClearBackground`: fills with `palette.error`, with `CupertinoIcons.trash` and `l10n.inboxClear` in `palette.onPrimary`, aligned to the trailing end.
- `_FilterChips` gets `VoidCallback? onClearAll`. The chips scroll inside an `Expanded`. When `onClearAll` is set, the `Clear all` link sits after them, outside the scroll, in `palette.link`, with a tap target at least 44 high.
- `_buildSlivers`: the rows on screen are `pinned` followed by every section's items. `onClearAll` is null when that list is empty or while loading.
- `_confirmClearAll(context, rows)`: `showBisoSheet` → `SafeArea` / `Padding(16, 12, 16, 16)` / `BisoListGroup`, laid out like `chat_info_screen.dart`'s `_showParticipantOptions`. A non-tappable row shows `inboxClearConfirmTitle(rows.length)` and `inboxClearConfirmMessage`. A destructive row (`BisoIconTile(CupertinoIcons.trash, accent: BisoAccent.coral)`, `inboxClear`) pops, then calls `_clear(ids)`. A `cancel` row only pops.
- `_clear(ids)`: `await notifier.clear(ids)`; on `false` and still `mounted`, show a `SnackBar` with `inboxClearFailed`.

- [ ] **Step 5: Run the screen tests, the design rules and the analyzer**

Run: `flutter test test/presentation && flutter analyze`
Expected: PASS; no issues.

- [ ] **Step 6: Document the behaviour in `CLAUDE.md`**

Add a "Notification inbox" entry beside the other implemented features. It should cover: read and cleared state live in `user_notifications` and are written only through `POST /api/notifications/read` and `/clear`; the table gives clients no create permission; the app lists every announcement from `announcements` and looks up state by id; cleared is permanent; swipe clears a row and "Clear all" clears the rows on screen. Locations: `lib/data/services/notifications_api_client.dart`, `notification_inbox_service.dart`, `lib/providers/notification/notification_provider.dart`, `lib/presentation/screens/notifications/`.

- [ ] **Step 7: Run the whole suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/generated/l10n lib/presentation/screens/notifications test/presentation/screens/notifications CLAUDE.md
git commit -m "feat(notifications): swipe to clear and Clear all in the inbox"
```

### Task 8: Rollout (needs the user's go-ahead for each step)

Each step changes production. Ask before each one, and report what it changed.

- [ ] **Step 1: Add the live column**

From `/Users/markus/Documents/dev/BISO-Sites/packages/api`, create only this column. Check the default flag's name with `appwrite tables-db create-boolean-column --help` first.
`appwrite tables-db create-boolean-column --database-id app --table-id user_notifications --key cleared --required false --xdefault false`
Verify: `appwrite tables-db get-table --database-id app --table-id user_notifications --json` lists `cleared` as `available` with `default: false`, and `$permissions` is still `[]`.

- [ ] **Step 2: Ship the API**

Open a PR for BISO-Sites `feat/inbox-read-and-clear` (body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`). The user merges and deploys it.
Verify: `curl -s -X POST https://api.biso.no/api/notifications/read -H 'content-type: application/json' -d '{"announcementIds":["x"]}'` → `401 {"error":"not_authenticated"}` (not 404).

- [ ] **Step 3: Check it end to end on a device**

Run the app from `feat/inbox-read-and-clear` against production. Open an inbox notification, swipe one away, and use "Clear all" on one filter. Then restart the app.
Verify: the opened notification is still read; the cleared ones are gone; the badge matches. `appwrite tables-db list-rows --database-id app --table-id user_notifications --json` shows the rows, each with only `read("user:<id>")`.

- [ ] **Step 4: Release the app**

Open a PR for BISO-Flutter `feat/inbox-read-and-clear`. The user merges and releases it, bumping the version as usual.
