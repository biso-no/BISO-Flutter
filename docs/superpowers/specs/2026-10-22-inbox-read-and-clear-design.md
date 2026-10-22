# Inbox: read state that sticks, and clearing notifications

Date: 2026-10-22. Repos: this app (BISO-Flutter) and BISO-Sites (`apps/api`,
`packages/api/appwrite.config.json`). Approved mockup:
`docs/superpowers/specs/2026-10-22-inbox-read-and-clear/clear-flow.html`.

## Why

Opening a notification from the inbox drops the Home badge, but after a
restart every notification is unread again. The read state was designed to
live on the server, in the `user_notifications` table, and is never saved:

- Only person-targeted sends get a `user_notifications` row in advance
  (`fanOutUserNotifications` in BISO-Sites
  `packages/shared/utils/push-dispatch.ts`). Broadcast and topic
  announcements have none.
- For those, `NotificationInboxService.markAsRead` creates the row from the
  app. The table has no table-level permissions (`$permissions: []`, row
  security on), so Appwrite refuses every create from a client. Live, on
  2026-10-22, the table held 0 rows.
- `NotificationInboxNotifier.markRead` has already marked the item read on
  screen, catches the refusal into `state.error`, which the inbox only shows
  when it is empty, and keeps the false "read".

At the same time, students should be able to clean up the inbox. Opened
notifications stay in the inbox, shown as read (no blue dot, no urgent pin),
and the student can clear them.

## What the student gets

- **Read sticks.** A notification opened from the inbox, the detail screen
  or a burst card stays read after a restart and on every device signed in to
  the same account.
- **Swipe to clear.** Dragging a row towards the leading edge (right to
  left in English and Norwegian) clears it at once, with no confirmation.
  Clearing an unread row also counts it as read, so the Home badge drops.
- **Clear all.** A "Clear all" text link sits at the end of the filter chip
  row. It clears exactly the rows on screen under the current filter, and
  asks first ("Clear 2 notifications?"), because it cannot be undone. The
  link is hidden when there is nothing on screen to clear.
- **Cleared is permanent and follows the account.** A cleared notification
  never comes back in the inbox, on this phone or any other. There is no
  archive and no undo.
- **Cleared is not deleted.** The announcement itself is untouched: tapping
  its push banner later still opens the linked event, article or job, and
  `/announcements/:id` still opens it. It is only no longer listed.
- **Burst cards** (one notification holding several items) clear as a
  whole.
- **Urgent pinned rows** can be cleared like any other.

## Goals

1. Read and cleared state saved on the server, per account.
2. Swipe-to-clear per row, and filter-scoped "Clear all" with confirmation.
3. The badge never counts a cleared notification.
4. No client writes to `user_notifications`; every write goes through
   `apps/api`, as expenses, profile edits and benefit reveals already do.

## Non-goals

- Undo, an archive, or restoring cleared notifications.
- "Mark all as read" without clearing.
- Per-day "Clear" links (option C in the placement mockup, rejected).
- An offline queue: a clear made offline fails and the row returns.
- Assembling the inbox on the server. The app keeps reading `announcements`
  directly and applying its audience rules.
- Syncing which burst cards were opened. That stays per device in
  SharedPreferences (`inbox_opened_items_provider.dart`).
- Tightening the client `update`/`delete` permissions that
  `fanOutUserNotifications` grants on targeted rows. They are harmless here
  and can be revisited separately.
- Paging the inbox.

## Anti-goals (a failure even if it technically works)

- "Clear all" clearing anything the student could not see: other filters,
  or rows beyond the list on screen.
- A cleared notification reappearing, even briefly, after a refresh, a
  restart or a realtime event.
- The badge counting cleared notifications, or a read that did not save.
- Reintroducing a client `create` permission on `user_notifications`.

## Decisions

### D1. State lives in `user_notifications`, with a new `cleared` column

Add `cleared`: boolean, not required, default `false`, to
`user_notifications` in BISO-Sites `packages/api/appwrite.config.json`, and
deploy it to the live project. Mirror it in this repo's `appwrite.config.json`
and regenerate `lib/types/user_notifications.dart`
(`appwrite types -l dart ./lib/types`).

One row per (student, announcement), as today; the unique index
`uniq_user_announcement` stays. `cleared = true` always comes with
`read = true`. Neither ever goes back to `false` (no endpoint lowers them).

Table-level permissions stay `[]`. Rows the API creates carry only
`read("user:<id>")` for their student, so the student can read their own rows
and receive realtime events for them, and nothing else.

There are no existing rows, so no backfill is needed.

### D2. Writes go through two `apps/api` routes

```
POST /api/notifications/read    { "announcementIds": ["…", …] }
POST /api/notifications/clear   { "announcementIds": ["…", …] }
```

- **Auth:** Appwrite JWT as `Authorization: Bearer`, resolved with
  `account.get()` as `api/profile/route.ts` does. The student is the
  account; the body never names a user. Missing or bad token → `401
  {"error":"not_authenticated"}`.
- **Input:** 1–100 ids, each a valid Appwrite id, duplicates ignored.
  Anything else → `400 {"error":"invalid_request"}`. The app sends larger
  sets in batches of 100.
- **Which ids are written:** only ids of existing `announcements` rows,
  whatever their `status`. Unknown ids are skipped without an error. *(My
  call, from the builder check: `status` is set to `sent` only after the
  pushes and the fan-out finish, so a student who taps a push during a large
  send would otherwise have their read dropped while the API answered
  `ok`.)* The server does not re-check audience visibility: a row for an
  announcement the student cannot read changes only their own inbox, and the
  app's audience rules still hide it.
- **Write:** for each id, update the student's existing row, or create one
  with the permissions in D1. `read` sets `read = true`; `clear` sets
  `read = true` and `cleared = true`. A create that loses a race to the
  unique index (409) is retried as an update. Both routes are idempotent.
- **Success:** `200 {"ok":true}` once every accepted id is written. A
  partial failure answers `503 {"error":"unavailable"}`; the app treats the
  whole request as failed and the server's idempotency makes a retry safe.
- **Rate limit:** per student, per instance, in the style of
  `benefits/[id]/reveal` (`createRateLimiter`). Over it → `429
  {"error":"rate_limited"}`.
- CORS and `OPTIONS` as on the other app-facing routes; responses
  `Cache-Control: private, no-store`.

### D3. Reading state in the app

`NotificationInboxService.fetchInbox` changes how it finds announcements and
how it reads `user_notifications`. From now on `user_notifications` only holds
state; it no longer decides which announcements are in the inbox.

- **Targeted announcements are listed from `announcements`**, like broadcasts
  and topics: `status = "sent"`, `audience_type` in `["users", "segment"]`,
  newest `sent_at` first, limit 50, with the same column select. Row security
  returns only the ones addressed to this student: `dispatchAnnouncement`
  (BISO-Sites `packages/shared/utils/push-dispatch.ts`) gives a targeted row
  `read` for its recipients only, before any push goes out. *(My call, from
  the builder check. Finding them through the student's newest 50 rows, as
  today, would break once the API writes a row for every broadcast read: 50
  opened broadcasts would push an unread targeted notification out of the
  inbox and the badge. This also shows a targeted notification whose fan-out
  row failed to write.)* The step that fetches "missing" announcements by the
  ids in the student's rows, and its audience re-check, go away.
- **State for the feed:** once the announcements to show are known, read the
  student's rows for exactly those ids (`user_id = me`, `announcement_id` in a
  chunk, in chunks of `_idChunkSize`). Today the app reads only the newest 50
  rows by `$createdAt`, which would let older cleared notifications come back.
- **Cleared announcements are dropped** from the list before it is
  returned.
- `fetchAnnouncementById` (the detail screen) is unchanged: it opens a
  cleared announcement normally.

### D4. App behaviour

- **New client:** `NotificationsApiClient` in
  `lib/data/services/notifications_api_client.dart`, following the existing
  API clients (`benefits_api_client.dart`): `appwriteJwt`/`apiUri` from
  `api_auth.dart`, an error enum, an exception without bodies or tokens, a
  401 clears the kept JWT. `markAsRead` stops creating rows itself and calls
  it. A 404 (API not deployed yet) is a failure like any other.
- **Read is optimistic and honest.** The row shows as read at once. If the
  request fails, it goes back to unread, silently: the badge shows the truth
  and the next open tries again.
- **Clear is optimistic and honest.** Swiped rows, or every row "Clear all"
  covered, leave the list at once. If the request fails, they come back in
  place and the inbox tells the student it could not clear them (a snackbar
  or the design system's equivalent).
- **No flicker.** A refresh that lands while a read or a clear is still in
  flight (realtime events, foreground pushes and pull-to-refresh all
  refresh) must not show those rows unread or back in the list. Keep the
  in-flight ids and lay them over every fetched result until their request
  resolves.
- **Other devices** update through the existing realtime subscription on
  `user_notifications`: the API's rows are readable by the student, so their
  events arrive and trigger a refresh.
- Clearing a burst may also drop its entry from the local opened-items store;
  not required.

### D5. Inbox UI

On `notifications_screen.dart` / `inbox_widgets.dart`, within the design
system rules that `test/presentation/design_rules_test.dart` already enforces
for these files (CupertinoIcons, `BisoPalette`, no new fonts).

- **Swipe:** Flutter's `Dismissible`, `DismissDirection.endToStart` only
  (right to left in English and Norwegian). Behind the row,
  `palette.error` with a trash icon and the word "Clear". The row clears when
  the drag passes the dismiss threshold; there is no stop that reveals a
  button to tap. No new package.
- **Screen readers:** each row offers a "Clear" custom semantics action, since
  swiping is not reachable with VoiceOver or TalkBack.
- **Clear all:** a text link at the trailing end of `_FilterChips`, in
  `palette.link`. The set it clears is the rows rendered for the current
  filter, pinned urgent rows included (they show under every filter). The
  confirmation uses `showBisoSheet` with a destructive `BisoListRow`, as the
  chat screens do: a message such as "Clear 2 notifications? They're removed
  from your inbox on all your devices.", a destructive "Clear" and "Cancel".
  Hidden while loading and when nothing is on screen.
- **Empty state:** the existing `BisoEmptyState`. Its title changes from "No
  notifications yet" to one that also fits an inbox the student just
  cleared ("You're all caught up").
- **Copy** in English and Norwegian (`app_en.arb`, `app_no.arb`, then
  `flutter gen-l10n`): "Clear all", "Clear", the confirmation message with a
  plural count, the clear-failed message, and the new empty title. Reuse
  existing `clear`/`cancel` keys where they fit.

### D6. Rollout

1. Schema (D1) to the live Appwrite project.
2. `apps/api` with both routes, deployed.
3. App release.

App versions already installed keep failing to save reads, as today, and
show cleared notifications as read. The new app against an API that has not
deployed yet gets 404s: reads revert and clears return with the error
message. Neither is new breakage.

## Testing

- **API (vitest, `apps/api`):** 401 without or with a bad token; 400 on empty,
  over 100 or malformed ids; creates a row with only the student's read
  permission; updates an existing fan-out row instead of creating;
  `clear` sets both flags; a 409 on create becomes an update; unknown ids are
  skipped and an announcement not yet `sent` is still written; rate limit
  answers 429.
- **App service/provider:** targeted announcements come from the
  `announcements` read, with or without a fan-out row, however many newer
  rows the student has; cleared announcements are dropped; state is found for
  announcements whose rows are older than the newest 50; a failed read
  reverts; a failed clear restores the rows and reports it;
  a refresh during an in-flight read or clear neither unreads nor restores
  those rows.
- **App widgets:** swiping a row clears it; "Clear all" under a filter clears
  only that filter's rows (plus pinned urgent rows on screen) after
  confirming, and nothing on Cancel; the link is hidden when the list is
  empty; the semantics action clears.
- Existing suites keep passing, including `design_rules_test.dart`.

## Left to the builder

- How the API finds existing rows (one query per request with
  `announcement_id` in the batch is enough) and the exact rate-limit numbers.
- Whether `read` and `clear` share one handler behind two routes.
- Whether the in-flight overlay lives in the notifier or the service.
- Snackbar versus another design-system way of reporting a failed clear.
- How a "Clear all" larger than one batch of 100 reports a batch that fails
  after an earlier one succeeded: only the failed batch's rows come back.
- Debouncing the refreshes that realtime events trigger.
- Keeping a horizontal drag on a burst card strip from starting a swipe of
  the row.
