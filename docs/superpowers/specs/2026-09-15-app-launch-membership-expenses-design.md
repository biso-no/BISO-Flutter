# App Launch: Membership, Expenses and Platform Hardening — Design

**Date:** 2026-09-15
**Repos:** BISO-Flutter (this repo) and BISO-Sites (`apps/api`, `apps/web`, `packages/shared`,
`packages/connectors`, `packages/api`)
**Branches:**

- BISO-Flutter: `claude/biso-mobile-app-review-7080ff`.
- BISO-Sites: a new `feat/app-launch-hardening` branch in its own worktree, so `main` is untouched.
**Decisions taken with the owner:**

- Build all three phases.
- Stop students writing their own profile rows ("lock profile rows").
- The 24SevenOffice customer `Id` is the student number; `ExternalId` is the Azure employee id.
- BI's Azure tenant is reachable only through Appwrite's OIDC provider. There is no app registration
  the mobile app could sign in with directly.

## Goal

Launch the student app with four money- or trust-bearing features working safely:

1. Webshop purchases — already correct, kept as is.
2. Reimbursements — submitted through `apps/api`, with receipts uploaded through it too.
3. Membership purchase in the app, offering only payment providers the admin has enabled.
4. Membership verification at launch, against 24SevenOffice (Finago) as the source of truth.

Students still cannot apply for recruitment roles from the app. That stays out of scope.

## Verified ground truth

Everything below was read from code on 2026-09-15: BISO-Flutter `main` @ `77e1106` and BISO-Sites
`main` @ `333165b9`. Permissions come from `packages/api/appwrite.config.json`, which is pulled from
the live project.

| Area | State | Evidence |
|---|---|---|
| Webshop | Correct. The app never writes orders. Quote, checkout (`client: "app"`), providers, stock holds and order verification all go through `apps/api` with a JWT. The server reprices, rejects a total mismatch, enforces the provider flags and credentials, and creates orders with the admin key. Buyers get `read` only. | `lib/data/services/shop_api_client.dart`, `apps/api/src/app/api/payment/[provider]/checkout/route.ts` |
| Direct-Appwrite migration (PR #8) | Moved reads only (events, jobs, webshop products). Its spec excluded orders, payments and expenses. | `docs/superpowers/specs/2026-09-07-appwrite-content-migration-design.md` |
| Expenses: submit | OCR, summary, draft and submit go through `apps/api`. Server enforces `expenses_module`. | `lib/data/services/expense_api_client.dart` |
| Expenses: receipts | **Broken.** Receipts upload straight to the `expenses` bucket, which has no user create grant. The web uploads through a server action with the admin key. `apps/api` has no upload route. | `expense_api_client.dart:30`, `apps/web/src/lib/actions/expense.ts:153` |
| Expenses: delete draft | **Broken.** Uses a direct `deleteRow`; submitters have no delete grant. | `expense_service_v2.dart:224,240` |
| Expenses: gating | Not wired to the admin toggle. Explore reads static `/api/config` (`expenses: false`). Profile reads `feature_flags` row id `expenses`, but the admin writes `key = expenses_module` with random row ids. | `explore_screen.dart:148`, `profile_screen.dart:22` |
| Expense rows | **Vulnerable.** The submitter keeps `update` on their expense row forever. Ledger posting pays out `total` to `bank_account` as read at posting time, and approvals store no amount. A student can change either after approval. | `apps/api/src/lib/expense-payload.ts:86`, `expense-posting.ts:187`, `expense-approval-chain.ts:27` |
| Membership purchase (app) | **Missing.** Legacy code calls the `vipps_checkout` Function with a client-supplied amount, reads a non-existent `biso_membership` table, and lives on a screen nothing routes to. | `lib/data/services/membership_service.dart`, `student_id_screen.dart` |
| Membership purchase (API) | `POST /api/payment/{provider}/membership-checkout` is sound: JWT, provider flag, credentials, plan from `memberships`, idempotent. It has no `client: "app"`, and the "already covered" gate exists only on the web page. | `membership-checkout/route.ts`, `apps/web/src/lib/membership-gate.ts` |
| Provider toggle | `feature_flags.payments_vipps` and `payments_stripe`. `GET /api/payment/providers` returns `available = flag && credentials`, and both checkout routes enforce the flag. | `apps/api/src/app/api/payment/providers/route.ts` |
| Membership verification (app) | **Missing.** Every profile load calls the retired `verify_biso_membership` Function. BI linking writes columns and tables users cannot write. | `auth_provider.dart:194`, `student_service.dart` |
| Membership verification (platform) | A live `GetCustomerCategories(customerId = student number)` call is matched against `memberships.category`. No `apps/api` route exposes it; the web route is cookie-only. | `packages/shared/utils/membership-status.ts`, `apps/web/src/app/api/membership/route.ts` |
| Profile rows | **Vulnerable.** The owner has `update` (web grant, and the app's default creator grant), and the table grants `create("users")`. Every membership check trusts `user.student_id`, so a student can claim another member's number. | `apps/web/src/lib/actions/profile-permissions.ts`, `auth_service.dart:366`, `checkout-pricing.ts:340` |
| 24SO customer ids | **Wrong in fulfilment.** Fulfilment looks up and creates customers as `Id = employeeId, ExternalId = student number`. The owner confirmed the real scheme is the reverse. The status check is already correct. | `packages/connectors/src/24sevenoffice/company.ts:387` |
| Recruitment | No apply path in the app, as intended. | `jobs_screen.dart` |

## Decisions

- **D1 — Profile rows are read-only to their owner.** Appwrite has no column permissions, so the
  self-service allow-list the web already has (`PROFILE_WRITABLE_FIELDS`) is enforced server-side
  instead of by row grants. `student_id` and the `bi_*` columns become server-only, which the code
  already assumes. No schema change.
- **D2 — Expense rows are read-only to their submitter.** Every expense write happens in `apps/api`
  with the admin key, after an ownership check.
- **D3 — 24SevenOffice ids:** customer `Id` = digits of the BI student email
  (`s1715738@bi.no` → `1715738`), and `ExternalId` = Azure `employeeId` from BI's tenant. A
  customer created on purchase gets both.
- **D4 — Students link their BI account on the website.** BI's tenant is reachable only through
  Appwrite's OIDC provider, so the existing web link flow is the only one that can create the link.
  - The app opens `https://biso.no/membership/link` in the browser.
  - The student signs in to biso.no with the same BISO account, if not already signed in.
  - They link through the existing flow (`createClientSessionToken` → OIDC → `/api/auth/bi-link`).
  - They return to the app, which re-verifies.
  - **Rejected: in-app AppAuth sign-in.** It needs a mobile app registration in BI's tenant, and
    none exists.
  - **Rejected: handing the app's session to a browser.** The app would mint an Appwrite session
    token and open a link page with it. Such a link is forwardable: its owner could send it to a
    member who, already signed in to Microsoft, would link *their* BI identity to the sender's
    account. The web flow is immune because the linking browser must hold the student's own
    session.
- **D5 — Membership semantics match the web exactly.** A matched 24SO category means member. The
  plan row's `expiryDate` is shown as the expiry. Expiry enforcement is not changed here (see
  Risks).

## Phase 1 — Platform hardening (BISO-Sites)

### 1.1 Expense rows (D2)

- `buildExpenseRowPermissions(userId)` returns `[read(user:<id>)]`.
- `POST /api/expenses/draft`, updating an existing draft:
  1. Read the row with the admin client.
  2. Require `userId === caller` (403) and `status === draft` (409).
  3. Write with the admin client.
- `POST /api/expenses/submit` changes two writes to the admin client:
  - the draft update in `saveDraftBeforeSubmission`, after the same ownership check;
  - the legacy email flow's final `status: pending` update.
- Reads that only serve the caller stay on the session client.
- New script `packages/api/scripts/revoke-expense-owner-writes.ts`:
  - Pages through every `expense` row and removes any `update("user:…")` or `delete("user:…")`
    grant. Nothing else changes.
  - Dry-run by default; `--apply` writes.
  - The permission filter is a pure, unit-tested function.

### 1.2 Profile rows (D1)

- `buildProfileRowPermissions(userId)` returns `[read(user:<id>)]`.
- The allow-list moves to `packages/shared/utils/profile-fields.ts`:
  - The existing fields: `name`, `phone`, `address`, `city`, `zip`, `bank_account`, `swift`,
    `avatar`, `bio`, `is_public`.
  - Plus `campus_id` and `departments`, which the app already self-serves. Nothing on the server
    authorises on them.
  - It also exports a zod schema whose string lengths match the table columns.
- Web `updateProfile` keeps `account.get()` and `account.updateName()` on the session. The row write
  moves to the admin client, after the allow-list.
- New `PUT /api/profile` (JWT) for the app:
  - Filters the body to the allow-list and validates it.
  - Updates the row with the admin client, or creates it when absent. A new row gets the account
    email and read-only permissions.
  - Mirrors `name` to the Appwrite account with `users.updateName`.
  - Returns `{ success: true, profile }`.
- The `user` table loses `create("users")`. The owner changes this in the Appwrite console and then
  runs `appwrite pull tables`. The repo config is edited to match, so a later push cannot re-add
  the grant.
- New script `packages/api/scripts/lock-profile-rows.ts`: same shape as 1.1, for `user` rows.

### 1.3 24SevenOffice customer ids (D3)

`upsertMembershipCustomer` changes as follows:

1. Look up `CompanyId = studentNumber`. If found, use that customer.
2. Otherwise create it with `Id = studentNumber` and `ExternalId = String(employeeId)`. The name,
   type and email are unchanged.

Search failures keep throwing `MembershipCustomerLookupError`, so fulfilment retries instead of
creating a duplicate. Connector and fulfilment tests, doc comments, and the membership-purchase
design spec are corrected to the confirmed scheme.

## Phase 2 — API for the app (BISO-Sites)

### 2.1 `GET /api/membership`

**Auth:** JWT required (401 otherwise).

**`resolveMembershipGate` and the purchasable-plan catalog move to `packages/shared`.** The web
imports them from there, so the app and the web apply identical rules.

**Response `200`:**

```json
{
  "state": "needs_bi_link | needs_directory_record | membership_check_unavailable | already_member | no_plans_available | eligible",
  "studentId": "s1715738",
  "isMember": true,
  "memberships": [{ "id": "…", "name": "…", "category": "113178", "startDate": "…", "expiryDate": "…" }],
  "currentExpiry": "2027-06-30",
  "reason": null,
  "checkedAt": "2026-09-15T08:00:00.000Z",
  "offeredPlans": [{ "id": "…", "name": "…", "price": 550, "duration": "year", "accrualMonths": 12, "startDate": "…", "expiryDate": "…" }],
  "defaultCampusId": "1",
  "campuses": [{ "id": "1", "name": "Oslo" }, { "id": "2", "name": "Bergen" }, { "id": "3", "name": "Trondheim" }, { "id": "4", "name": "Stavanger" }]
}
```

**Behaviour:**

- **Profile read:** admin client. Student number is `sanitizeStudentNumber(profile.student_id)`.
  When the read fails for any reason other than a missing row, the route returns
  `membership_check_unavailable` (`reason: "profile_unavailable"`), never "not linked".
- **Status cache:** `computeMembershipStatus` behind a 10-minute server cache keyed by student
  number, as on the web.
  - Transient failures are not cached; they come back as `membership_check_unavailable` with
    `reason`.
  - `?refresh=1` recomputes only when the cached result is older than 60 s, so a client cannot
    turn the endpoint into a 24SO load generator.
- **Campuses:** `CAMPUS_INVOICE_NAMES` without National (`"5"`), as the web wizard does.

### 2.2 Web page for linking from the app: `/membership/link`

**New page `apps/web/src/app/(public)/membership/link/page.tsx`.** It is deliberately not under
`/app/*`, which the Android app claims as verified App Links. It reuses the join page's gate
components, so there is no new linking logic.

| Situation | Rendered |
|---|---|
| Signed out | `SignedOutState`, returning here after sign-in |
| Signed in, no `student_id` | `NeedsBiLinkState` with `returnTo=/membership/link` |
| Linked, no `bi_employee_id` | `RetryDirectoryState` |
| Linked with an employee id | "Your BI student account is linked", the BISO account's email (so a student signed in with a different account notices), and "Return to the BISO app" → `biso://membership?linked=1` |

**Supporting changes:**

- `NeedsBiLinkState` gains an optional `returnTo` prop; its default stays `/membership/join`.
- `/membership/link` is added to `ALLOWED_RETURN_PATHS` in `apps/web/src/app/api/auth/bi-link/route.ts`.
- **No `apps/api` linking route is added.** The link writes `student_id` and the `bi_*` columns
  exactly as today, through the admin client (D1 keeps them server-only), and the app reads the
  result from `GET /api/membership`.

### 2.3 Membership checkout for the app

- The body accepts `client` (`"web"` or `"app"`). Anything else means `"web"`.
- Return URLs use `checkoutReturnUrl(apiBase, orderId, client)`. Stripe's cancel URL for the app is
  the return route with the cancelled marker, as in the shop route.
- New server-side gate, run after the identity and plan checks and before idempotency and order
  creation:
  1. Read the cached status (2.1).
  2. `resolveMembershipGate({ plans: [plan], … })` must be `eligible`.
  3. `membership_check_unavailable` answers 503 "We couldn't verify your membership right now".
     Any other non-eligible state answers 409 "Your membership already covers this period".
  4. This also protects web purchases against races.
- The return route gets a membership branch for app checkouts. It redirects to
  `biso://membership?orderId=…&status=…`, or `biso://membership?orderId=…&cancelled=1`, using a new
  `appMembershipDeepLink` in `packages/shared/utils/checkout-return.ts`. Shop orders are unchanged.

### 2.4 Expense attachments and draft deletion

**`POST /api/expenses/attachments`**

- JWT, multipart field `file`.
- Returns 403 when `expenses_module` is off.
- The type comes from magic bytes and must be PDF (`%PDF`), PNG or JPEG (the ledger merge accepts
  only these), otherwise 415.
- Maximum 10 MB (the bucket limit), otherwise 413.
- Uploaded to `expenses` with the admin client and `[read(user:<id>)]`.
- `201 { success: true, file: { fileId, name, mimeType, size, viewUrl } }`.

**`DELETE /api/expenses/draft?expenseId=…`**

- JWT; the owner must match (403) and the row must be a draft (409).
- The row is deleted with the admin client. `expenseAttachments` cascades.
- Receipt files the draft referenced (bare file ids in `url`) are deleted best-effort.
- `200 { success: true }`.

### 2.5 Live expenses flag

`GET /api/config` overlays `features.expenses = isFeatureEnabled("expenses_module")` onto the static
file. Response header: `Cache-Control: public, max-age=0, s-maxage=15`.

## Phase 3 — App (BISO-Flutter)

### 3.1 API clients

- **`MembershipApiClient`:** `fetchOverview({bool refresh})`,
  `startCheckout(provider, planId, campusId)`. Checkout sends `client: "app"`.
- **`ProfileApiClient`:** `upsert(Map<String, dynamic> fields)`.
- **`ExpenseApiClient`:** receipt upload becomes a multipart POST to `/api/expenses/attachments`,
  and it gains `deleteDraft(expenseId)`.
- All of them use `account.createJWT()` bearer tokens and `AppConstants.apiBaseUrl`, and surface
  the server's `message`/`error`.

### 3.2 Membership status and launch verification

- **`membershipOverviewProvider`** is an async notifier keyed on `signedInUserId`.
  - Signed out → a signed-out value.
  - Otherwise it emits the cached overview for that user (if any), then fetches a fresh one.
  - `refresh()` passes `refresh=1`.
- **Cache:** the last successful overview, per user, in SharedPreferences with `checkedAt`.
  - When a fetch fails or reports `membership_check_unavailable`, the cached value is kept and
    shown as "Last verified …".
  - Nothing is cached for signed-out users.
- **Verification at launch and on resume:** a `MembershipVerifier` built in `BisoApp.build`, like
  `CheckoutController`.
  - It starts the first verification as soon as a signed-in user is known, so a launch verifies
    even if no membership UI is open.
  - It re-verifies on resume when the last check is over 10 minutes old.
- **`hasValidMembershipProvider`** reads `overview.isMember`. It accepts a cached value up to 24 h
  old; this is presentation only, since the server prices.
- **Removed:** `AuthState.membershipVerification`, `studentRecord` and the
  `verify_biso_membership` call on profile load. Their getters are replaced by the overview.

### 3.3 BI account link

- **In the `needs_bi_link` state:**
  - The screen explains linking and shows which BISO account to sign in with (the app account's
    email).
  - "Link on biso.no" opens `https://biso.no/membership/link` with
    `url_launcher` in `LaunchMode.externalApplication`. That way an existing biso.no session in the
    student's browser is reused.
- **In `needs_directory_record`:** the same page, which renders the web's directory retry.
- **Returning to the app:**
  - `biso://membership?linked=1` routes to the membership screen and triggers `refresh()`.
  - Resuming the app after a link attempt does the same, even without the deep link: the screen
    records that a link was started, and refreshes on the next resume.

### 3.4 Membership screen and purchase

- **Route `/profile/membership`,** reached from:
  - the Profile row that replaces the static "We're improving Student ID" text, now showing a
    status subtitle;
  - the deep link `biso://membership` and `https://biso.no/app/membership`.
- **One `BisoPage` screen,** following the 2026-09 design system (`BisoPalette`, `BisoAccent`,
  CupertinoIcons, `design_rules_test.dart`). Content by state:

  | State | Shown |
  |---|---|
  | Signed out | Sign-in prompt |
  | `needs_bi_link` | What linking does, which account to use, and "Link on biso.no" (3.3) |
  | `needs_directory_record` | "We couldn't find your BI record", with "Retry on biso.no" and a contact route |
  | `membership_check_unavailable` | Cached card if any, plus retry |
  | Member (`already_member` or `eligible` with `isMember`) | Card with name, student id, plan, valid until and "Verified …". Renewal plans if offered. |
  | `no_plans_available` | Message |
  | `eligible`, not a member | Plans, then campus (default `defaultCampusId`), then provider buttons |

- **Provider buttons** come from `availablePaymentProvidersProvider`; only enabled and configured
  providers are shown. With none available, the screen says purchase is temporarily unavailable.
- **`MembershipCheckoutController`** is built in `BisoApp.build`.
  1. Starts the checkout and launches `checkoutUrl` externally.
  2. Persists a pending marker: order id and start time, stale after 2 h.
  3. Resolves the marker on resume, cold launch and deep link, through
     `ShopApiClient.fetchOrder`, which reconciles and settles server-side.
- **After a successful payment,** the overview is refreshed with `refresh=1`, retried a few times
  over ~30 s while fulfilment lands. The screen shows "Payment received — activating your
  membership" until `isMember`.
- **A cancelled or failed payment** shows a message and leaves the plan selectable.
- **Errors:**
  - 403 (provider disabled) refetches providers.
  - 409 (already covered) refreshes the overview.
  - 503 offers retry.

### 3.5 Expenses

- Receipts upload through `POST /api/expenses/attachments`; draft delete uses the new route.
- The Explore row, the Profile "Expense History" row, `ExpensesScreen` and `CreateExpenseScreen`
  all read the live `features.expenses` from `appConfigProvider`.
  - When off, the screens show "Reimbursements are currently unavailable" instead of a form.
  - This covers routes, deep links, shortcuts and share-sheet intake.
  - `FeatureFlagService('expenses')` is no longer used for this.
- The receipt picker must hand the API PDF, PNG or JPEG. Images are re-encoded to JPEG, and HEIC
  never reaches the server.

### 3.6 Profile writes

`AuthService.createUserProfile`, `updateUserProfile`, the payment-information update, and
`PrivacyService` `is_public` all call `ProfileApiClient.upsert`. The avatar file upload itself is
unchanged; only the resulting URL is saved through the API.

### 3.7 Removals

Removed from the app:

- `lib/data/services/membership_service.dart`
- `lib/providers/membership/membership_provider.dart`
- `lib/data/services/student_service.dart`
- `lib/data/services/oauth_service.dart`
- `lib/presentation/screens/profile/student_id_screen.dart`
- `lib/presentation/widgets/membership_purchase_modal.dart`
- `lib/presentation/widgets/show_membership_purchase_modal.dart`
- `ValidatorService.issuePassToken`

`ValidatorService.verifyPassToken` stays, since controller mode is out of scope. Tests of removed
code are removed; tests of changed code are updated.

Once `student_service.dart` and `oauth_service.dart` are removed, nothing uses `flutter_appauth`.
The package and its `com.biso.no` redirect-scheme registration are removed too, provided the iOS
and Android builds still succeed; otherwise that is left as a follow-up.

## Error handling

- **Server messages** are written for students and surfaced as-is, the pattern the shop already
  uses.
- **24SO, Graph and provider timeouts** keep their existing deadlines. The new routes answer 503
  rather than hang.
- **Failure behaviour:**
  - An unreadable profile or 24SO status → `membership_check_unavailable`, never "not a member".
  - A membership checkout whose status cannot be verified → 503, not a charge.
  - The expense flag read keeps the existing catalog default when Appwrite is unreadable.

## Testing

**BISO-Sites (vitest; typecheck; biome lint)**

- **New routes:**
  - membership overview: states, cache bypass floor, auth;
  - web `/membership/link`: state selection (signed out, needs link, needs directory record,
    linked), and the return-path allow-list accepting `/membership/link`;
  - expense attachments: magic bytes, size, flag, auth;
  - draft delete: ownership, status, file cleanup;
  - `PUT /api/profile`: allow-list, create vs update, permissions;
  - `/api/config` flag overlay.
- **Changed code:**
  - membership checkout: `client`, gate 409/503;
  - return route: membership deep links;
  - draft and submit: admin writes and ownership;
  - permission helpers;
  - `upsertMembershipCustomer`: id scheme;
  - web `updateProfile` and `syncBiStudentIdentity` against the shared helpers.
- **Scripts:** the permission filter functions.
- **Baseline:** `apps/api` 167 tests pass today; all existing suites must stay green.

**BISO-Flutter (`flutter test`, `flutter analyze`)**

- API clients with `MockClient`.
- Overview notifier: cache, offline and refresh.
- The link hand-off: the web URL, and a refresh on the `linked=1` deep link and on resume.
- `MembershipCheckoutController`: pending recovery on resume, cold launch and deep link.
- Deep link routing for `biso://membership`.
- Membership screen widget tests per state.
- Expenses: gating, upload and delete.
- Profile writes.
- `design_rules_test.dart`.
- **Baseline:** 721 tests pass today.

**Manual, by the owner after deployment**

- A real BI link started from the app on iOS and Android, returning through `biso://membership`.
- A Vipps test-mode membership purchase end to end, including the 24SO customer and invoice.
- A receipt upload and submit with ledger posting on.

## Rollout (ordered)

1. **Prerequisites (owner):**
   - Confirm the BI directory lookup works on the web today: `BI_AZURE_TENANT_ID`,
     `BI_AZURE_CLIENT_ID` and `BI_AZURE_CLIENT_SECRET` are set on `apps/web`.
   - Confirm `TFSO_*` is set on `apps/api`. Membership status, the member discount and fulfilment
     all run there.
2. Merge and deploy BISO-Sites (`apps/api`, `apps/web`). Every change is compatible with existing
   clients.
3. Run `revoke-expense-owner-writes` (dry-run, then `--apply`). Safe immediately.
4. When the new app build ships, or right away if no older build that writes profiles directly is
   in use:
   - remove `create("users")` from the `user` table in the console, then `appwrite pull tables`;
   - run `lock-profile-rows` (dry-run, then `--apply`).
5. Release the app.
6. **Follow-ups (owner):**
   - Review 24SO for customers created by web membership purchases under the old id scheme.
   - Delete the legacy `vipps_checkout` and `verify_biso_membership` Appwrite Functions if they
     still exist.

## Risks and open items

- **Linking leaves the app.** The student may have to sign in to biso.no, and must use the same BISO
  account as in the app. The link page shows the signed-in account to make a mismatch visible.
  In-app linking needs either a BI-tenant mobile app registration or a hand-off that is not
  forwardable (see D4).
- **Membership expiry is not enforced by the check.** It relies on `memberships.status`, which
  nothing maintains since `syncMembershipsFrom24SO` lost its caller. Unchanged here, for parity
  with the web; worth a follow-up with how categories are removed in 24SO.
- **One BI identity can be linked to several BISO accounts.** No uniqueness is enforced today.
  Follow-up.
- **Feature flags fail open to catalog defaults** when Appwrite is unreadable (`payments_vipps`
  defaults to on).
- **Out-of-scope breakage noticed:** validator mode calls Functions absent from the config; the AI
  chat calls `/api/public-assistant`, which BISO-Sites does not implement; marketplace "sell" has
  no create grant on `products`.

## Out of scope

- Recruitment applications in the app.
- Marketplace, chat, validator mode, AI assistant.
- Reworking membership expiry, or scheduling the catalog sync.
- Server-side enforcement of `member_only` products.
