# Member Pass and Membership Scanning — Design

**Date:** 2026-09-17
**Repo:** BISO-Flutter, branch `claude/biso-mobile-app-review-7080ff`. This builds on the membership and
BI-link work from `2026-09-15-app-launch-membership-expenses-design.md`.
**Backend:** BISO-Sites `apps/api`, branch `feat/member-pass-api`. It is not deployed yet. This spec
codes against brief v2. The contract doc generated from the finished routes wins where it differs.

**Decisions taken with the owner:**

- Scanner rights come from server-side **grants** that admins give to email addresses. The app asks
  `GET /api/member-pass/scanner` and does no role or team check of its own. The `validators` team is
  retired.
- BI linking stays on biso.no (`https://biso.no/membership/link`, which returns to
  `biso://membership?linked=1`). This is the flow already on this branch.
- iOS Wallet uses a **method channel** (`biso/wallet`) in `AppDelegate.swift` rather than a plugin. The
  reasons: no new dependency, the pass bytes never touch disk, the app already uses the same pattern
  for expense intake, and the available plugins are thinly maintained or want a URL or file path.
- "Scan memberships" is the **first** category tile in Explore, and only scanners see it.
- The purchase flow is kept.

## Goal

1. Members show a live, rotating, server-signed pass from Profile. It can also go into Apple or Google
   Wallet.
2. People holding a scanner grant check passes at the door from Explore.
3. The old token pass and controller mode are removed.

## Non-negotiables

- No signing, secrets or membership logic on the device. The server decides everything.
- The client never writes `student_id` or membership data. Verified on this branch: none remains
  (`student_service`, `flutter_appauth` and the `student_id` writes were removed in `a989442`/`bf9aac4`).
- Codes, JWTs and scanned strings live in memory only. They are never persisted and never passed to
  `AppLogger`/Talker. There is no HTTP interceptor in the app (verified), so the rule is enforced in
  the new client: exception messages carry only the server's `error` field, never a body, header or
  code.

## API seam

`abstract interface class MemberPassApi` has five methods:

| Method | Call | Success | Errors (typed `MemberPassApiException`) |
|---|---|---|---|
| `fetchPass()` | `GET /api/member-pass` | `ActivePass` or `NoPass(state)` | 401 unauthorized; 5xx, network error or timeout are transient; **404 → `NoPass(unavailable)`** while the route is not deployed |
| `fetchApplePass()` | `GET /api/member-pass/apple` | `Uint8List` | 401; 403 not a member; 404 `not_configured`; 500 failed |
| `fetchGoogleSaveUrl()` | `GET /api/member-pass/google` | `Uri saveUrl` | 401; 403; 404 `not_configured`; 502 `wallet_unavailable` |
| `fetchScannerAccess()` | `GET /api/member-pass/scanner` | `ScannerAccess(campusId?, expiresAt?, dayColor)` | 401 signed out; 403 `not_scanner`; **404 → not a scanner** while the route is not deployed; 503 `not_configured`; 5xx or network error is transient |
| `scan(code)` | `POST /api/member-pass/scan` | `ScanOutcome` | 400 `invalid_body`; 401; 403 `not_scanner`; 429 `rate_limited`; 503 `not_configured`; 5xx or network error is transient |

- `MemberPassApiClient` is the real implementation. It follows `MembershipApiClient`: an
  `ApiJwtProvider`, `apiUri`, an injectable `http.Client` and a 20 s timeout.
- `memberPassApiProvider` returns it by default, and tests override it with fakes. There is no dev
  flag: until the backend deploys, the two 404 rules above keep the app quiet (the pass shows
  "unavailable" and the scanner tile stays hidden). Switching on is just the deploy.
- The 404 rules apply **only** to those two endpoints. On the wallet routes, 404 keeps its real
  meaning, `not_configured`.
- Parsing is strict about `state`, `result` and `reason`. An unknown `state` maps to `unavailable`, an
  unknown `result` to `unavailable`, and an unknown `denied` reason to a generic "Not valid".

## Models (`lib/data/models/member_pass.dart`)

- `sealed class MemberPassResponse`
  - `ActivePass` holds `holder`, `codes`, `dayColor`, `serverNow`, `wallets`.
  - `NoPass` holds a `NoPassState`: `noBiIdentity`, `notMember`, `expired` or `unavailable`.
- `PassHolder` holds `name`, `membershipName`, `startDate`, `expiryDate` and an optional `term`.
- `PassTerm` holds `duration` (`semester`, `year` or `threeYears`), `season` (`spring`, `fall` or null),
  `fromYear` and `toYear`.
  - Label: for a semester, "Høst 2026" / "Fall 2026" (spring is "Vår" / "Spring"). Otherwise
    "2026–2027", or just "2026" when `fromYear == toYear`.
- `PassCode` holds `slot` and `code`. Its `toString` never prints the code.
- `DayColor` holds `name` (one of the 12 names) and `hex`. The localized name comes from l10n; an
  unknown name shows as the raw name.
- `WalletAvailability` holds `apple` and `google`.
- `ScannerAccess` holds `campusId`, `expiresAt` and `dayColor`.
- `ScanOutcome` holds `result` (`valid`, `duplicate`, `checkId`, `denied` or `unavailable`), `reason`
  (`badCode`, `stale`, `expired`, `notMember` or `notLinked`), `name`, `membershipName`, `expiryDate`
  and `secondsSincePrevious`.

## Pass logic

### `MemberPassSession` (pure, `lib/providers/member_pass/member_pass_session.dart`)

It has no timers, no Flutter imports, and takes `now` as an argument. It mirrors the web
`pass-refresh.ts` and should pass the same cases.

- `apply(MemberPassResponse r, int localNowMs)`
  - Replaces the view.
  - For an `ActivePass`, sets `drift = serverNow - localNowMs` and `offline = false`.
- `applyUnauthorized()` sets the view to signed-out and clears the codes.
- `applyTransientFailure(int nowMs)`
  - If an active pass still has a usable code (see `current`), it keeps the pass and sets
    `offline = true`.
  - Otherwise the view becomes `reconnect` and the codes are cleared.
- `slotAt(nowMs) = (nowMs + drift) ~/ 30000`.
- `current(nowMs)` returns the `PassCode` whose slot equals `slotAt(nowMs)`, or null. It also returns
  `msUntilNextSlot = 30000 - ((nowMs + drift) % 30000)`.
- `needsRefetch(nowMs)` is true when fewer than 4 codes have a slot at or after `slotAt(nowMs)`.
- `shouldRetry(nowMs, lastAttemptMs)` is true when the pass is offline or `needsRefetch` holds, no
  fetch is in flight, and at least 15 s have passed since the last attempt.

### `MemberPassNotifier` (`member_pass_provider.dart`)

- `AutoDisposeNotifier<MemberPassView>`.
- **Keep-alive:** the pass screen and the presentation route each hold a `KeepAliveLink` while
  mounted, taken on open and closed on dispose. Opening presentation mode therefore never disposes
  the provider or refetches. The codes are dropped once both routes close.
- **Fetching:**
  - It fetches on build, and on `AppLifecycleListener.onResume`.
  - It also fetches on any `connectivity_plus` change. This is a trigger only, because a changed
    interface does not mean the internet works.
  - Only one fetch runs at a time.
- **Tick:** a 1 s `Timer.periodic` updates the clock, ring and current code, and runs
  `shouldRetry`. The 15 s retry is the safety net.
- `retry()` is called by the Try again buttons and fetches immediately.
- **Signed-out:** watches `membershipUserIdProvider`. Signing out rebuilds the notifier to
  signed-out.

### View states → UI

| View | UI |
|---|---|
| loading (no pass yet) | Skeleton pass card |
| active (with a current code) | Pass card; an "Offline" chip when `offline` |
| active, but the clock is before the first code (clock skew) | Treated as `needsRefetch`: skeleton QR plus "Updating…" |
| `noBiIdentity` | Card "Link your BI student account" → the existing `_openLinkPage` flow (`membershipOverviewProvider.notifier.noteLinkStarted()` then `membershipLinkUrl`) |
| `notMember` / `expired` | Card "You're not a member" / "Your membership has ended" with a "Become a member" button → `/profile/membership` |
| `unavailable` | "Couldn't load your pass" with Try again |
| `reconnect` | "Reconnect to show your pass" with Try again |
| signed-out | Sign-in prompt (the existing auth prompt pattern) |

## Pass UI

- **Route:** `/profile/member-pass`, a child of `/profile`.
- **Entry points:**
  - A new Profile row, "Member pass" / "Medlemskort", placed next to the Membership row.
  - A "Show member pass" button on `membership_screen.dart` when the membership is active.
- **`PassCard`** (`lib/presentation/widgets/member_pass/`):
  - "MEDLEM" / "MEMBER" in large Museo Sans 300, with the term label beneath.
  - **Holographic band:** a `CustomPainter` sweeping a gradient shader.
    - The loop is 6 s normally. When `MediaQuery.disableAnimations` is set it slows to 24 s but never
      stops.
  - **Live clock:** HH:MM:SS in Oslo time from `osloNow(DateTime.now().add(drift))`, next to a pulsing
    live dot. The dot pulses slowly under reduced motion.
  - **Day stripe:** a full-width stripe in `dayColor.hex`, with the localized color name in a
    contrasting text color.
  - **QR:** `QrImageView(data: code, errorCorrectionLevel: M)` on a white quiet zone, sized to the card
    width.
  - **Countdown ring:** a ring around a small center label, driven by `msUntilNextSlot / 30000`.
  - The holder name, the membership name, and "Valid until {date}" as a localized medium date.
- **Presentation mode:**
  - Tapping the card opens a full-screen route with only the band, clock, stripe, a larger QR, the
    ring and the name.
  - **Entering and leaving:** entering calls `WakelockPlus.enable()` and
    `ScreenBrightness().setApplicationScreenBrightness(1.0)`, which sets app-level brightness and
    leaves the system setting alone. Both are undone on dispose.
  - **Backgrounding:** both are also undone on `inactive`, `hidden` and `paused`, and re-applied on
    `resumed` while the route is still showing.
  - Tapping anywhere or swiping down closes it.
- **Oslo time** (`lib/core/utils/oslo_time.dart`): `osloNow(DateTime utc)`.
  - It adds +2 h between 01:00 UTC on the last Sunday of March and 01:00 UTC on the last Sunday of
    October, and +1 h otherwise. This is the EU rule Norway follows.

## Wallet

- **Apple:**
  - Shown only when `defaultTargetPlatform == TargetPlatform.iOS`, `wallets.apple` is true and
    `WalletChannel.canAddPasses()` returns true. `defaultTargetPlatform` rather than `Platform`, so
    widget tests can switch platforms.
  - Tapping it calls `fetchApplePass()` and then `WalletChannel.addPass(bytes)`.
- **Google:**
  - Shown only when `defaultTargetPlatform == TargetPlatform.android` and `wallets.google` is true.
  - Tapping it calls `fetchGoogleSaveUrl()`, then `launchUrl(saveUrl, mode: externalApplication)`.
- **Button art:** the official badges Markus supplied, in `assets/wallet/`, with `en` and `no`
  variants. They are rendered with `flutter_svg`, which is already a dependency.
  - **Apple:** the app bundles `apple/flutter/add_to_wallet_{en,no}.svg`. These are generated from
    Apple's Illustrator SVGs by `tool/inline_svg_styles.py`, which moves the `<style>` class rules
    onto the elements as attributes. `flutter_svg` ignores `<style>`, so the unmodified files render
    without their fills. The artwork itself is unchanged; this was checked with a render. The
    original `.svg` and `.eps` files stay in the repo as sources and are not bundled. Only these
    four files are declared in `pubspec.yaml`, not the whole directory.
  - **Google:** `google/add_to_wallet_{en,no}.svg` are bundled as they are.
  - **After adding, Apple:** Apple offers only an "Add" badge, and its guidance is that the app's own
    UI handles the follow-up. That is the "Added to Wallet" state below.
  - **After adding, Google:** `google/view_in_wallet_{en,no}.svg` are **not used yet**. The save link
    never tells the app whether the pass was saved, and the brief's API gives no view URL. They get
    wired up once `/api/member-pass` reports that the pass is saved and returns a view link, which
    is a backend follow-up. Until then Android keeps the "Add" button; Google's save page itself
    shows an already-saved pass.
  - A widget test pumps each bundled badge, to catch a broken asset path.
- **iOS channel `biso/wallet`** (`AppDelegate.swift`):
  - `canAddPasses` returns `PKAddPassesViewController.canAddPasses()`.
  - `addPass(bytes)`:
    - builds a `PKPass(data:)`, and on a throw returns the error `invalid_pass`;
    - presents `PKAddPassesViewController` from the root view controller;
    - on dismiss, returns `added` if `PKPassLibrary().containsPass(pass)` is true, and `cancelled`
      otherwise.
- **After adding:** once `addPass` returns `added`, the button is replaced by an "Added to Wallet"
  label for the rest of that screen's life. There is no check when the screen opens, because that
  would mean downloading the pass. "View in Wallet" through `shoebox://` is left out, because the
  scheme is undocumented.
- **Entitlement caveat:** `PKPassLibrary.containsPass` can only see passes whose pass type identifier
  is in the app's entitlements. Until the Wallet capability with the server's pass type ID is added
  to `Runner.entitlements`, the check returns false and the sheet reports `cancelled`. The only
  effect is that the Add button stays visible. Adding the capability is a manual step for Markus.
- **Error messages:**
  - 403: "Your membership isn't active"
  - 404: "Wallet isn't available yet"
  - 500, 502 or a network error: "Couldn't reach Wallet — try again"
  - `invalid_pass`: "The pass couldn't be read"
  - 401: the sign-in prompt

## Scanner

### Access

- **`scannerAccessProvider`** is an `AsyncNotifier<ScannerAccessState>`. The states are:
  - `granted(ScannerAccess)`;
  - `denied` (403, or 404 before the deploy);
  - `signedOut` (401);
  - `notConfigured` (503);
  - `failed` (5xx or a network error).
- **Caching:**
  - The answer is kept in memory for 5 minutes and re-checked on resume once it is older than that.
  - It is refreshed whenever the scanner screen opens, so "Access until …" is current.
  - A new user id rebuilds it.
- **Explore:** the tile is shown only for `granted`.
  - Icon `CupertinoIcons.qrcode_viewfinder`, accent gold (the design system's membership accent).
  - Text: "Scan memberships" / "Skann medlemskap", with the subtitle "Check member passes at the
    door" / "Sjekk medlemskort i døra".
  - Route: `/explore/scan`.

### Route guard

- **`ScannerGate`** is what `/explore/scan` builds. Because the route itself renders it, cold starts
  and deep links are guarded the same way.
- The route is a **top-level** `GoRoute` declared before the tab `ShellRoute`, so the camera is full
  screen with no tab bar. The Explore tile opens it with `context.push`.
- **Before access is known:** a spinner. The camera is never created.
- **Other states:**
  - `granted`: `MembershipScannerScreen`.
  - `denied`: "You don't have scanning access. Ask BISO staff for an invitation."
  - `signedOut`: "You've been signed out — sign in again", with a sign-in button.
  - `notConfigured`: "Scanning isn't available right now."
  - `failed`: "Couldn't check your access", with Try again.

### `ScanGate` (pure, `scan_gate.dart`)

It mirrors the web `scan-repeat.ts`.

- **`memberKey(code)`:**
  - The code is split on `.`.
  - For a `v1` or `a1` code with at least 4 parts, the key is `parts[1 .. len-2]` joined with `.`.
  - For a `g1` code with at least 3 parts, the key is `parts[1 .. len-1]` joined with `.`.
  - Anything else keys on the whole string.
- **`admit(code, nowMs)`**:
  - **While a request is in flight or a result is showing:** returns false, and refreshes
    `lastSeen[key]` only if that member is already in the map. A different person glimpsed during
    that time is not recorded, so they can be checked the moment the result clears.
  - **Otherwise:** records `lastSeen[key] = nowMs`, so the window restarts on every read. It then
    returns false if the member was seen less than 20 s ago. If not, it sets busy and returns true.
- `finish()` clears busy. It is called when the result is dismissed.
- Entries older than 20 s are pruned on each call.

### `MembershipScannerScreen`

- **Camera:** `MobileScannerController(formats: [BarcodeFormat.qrCode])`, full screen.
- **Top bar:**
  - A close button.
  - The day color swatch and its localized name.
  - "Access until {date time}" when `expiresAt` is set, shown in Oslo time.
- **On a detected string:**
  1. `ScanGate.admit` must pass.
  2. A string longer than 256 characters produces a local `denied/badCode` result, with no network
     call.
  3. Otherwise the app calls `api.scan(code)`.
- **Full-screen results:**

| Outcome | Color | Text |
|---|---|---|
| `valid` | green | name, membership, "Valid until {date}" |
| `duplicate` | orange | name, "Already scanned {n}s ago" (under 60 s), "{m} min ago" otherwise |
| `checkId` | amber | "Wallet pass — check ID", plus the name |
| `denied` + `badCode` | red | "Not a BISO pass" |
| `denied` + `stale` | red | "Old code — ask them to reopen the pass" |
| `denied` + `expired` | red | "Membership has ended" |
| `denied` + `notMember` | red | "Not a member" |
| `denied` + `notLinked` | red | "No linked student account" |
| `unavailable`, a network error or 5xx, or a 503 | grey | "Couldn't check — try again" |
| 400 `invalid_body` (should not happen, given the local length check) | red | "Not a BISO pass" |
| 429 | grey | "Too many scans — wait a moment" |

- **Haptics:**
  - `valid`: `HapticFeedback.mediumImpact`
  - `duplicate` and `checkId`: `HapticFeedback.heavyImpact`
  - `denied`: `HapticFeedback.vibrate`
  - Grey results: `selectionClick`
- **While a result shows:**
  - The camera is stopped with `controller.stop()`.
  - The result dismisses itself after 3 s or on a tap. The camera then restarts and
    `ScanGate.finish()` runs.
- **401:** the scanner closes and a "signed out — sign in again" message appears.
- **403 mid-shift:** the scanner closes and the no-access message appears.
  `scannerAccessProvider` is invalidated.
- **Presentation:** the scanner is its own logic and view. The "result" is a sealed `ScannerDisplay`:
  `idle`, `checking` or `result(kind, texts)`. A pure `mapScanOutcome()` maps an outcome or exception
  to a display, so it can be tested alone.

## Retirement

- **Deleted:**
  - `lib/data/services/validator_service.dart`
  - `lib/presentation/screens/validator/controller_mode_screen.dart`
  - `test/presentation/screens/validator/controller_mode_design_test.dart`
- **Removed:**
  - The `/controller-mode` route.
  - `controllerPermissionsProvider` and the Settings "Validator Mode" row, with its test cases in
    `settings_design_test.dart`.
  - The `showThisToValidatorsMessage` string and any other strings used only by the deleted screen.
- **Verified by grep:** no `issue_pass_token`, `verify_pass_token`, `verify_biso_membership`,
  `biso://verify` or `validators` is left in `lib/` or `test/`.
- **For the PR description:** the Appwrite functions `issue_pass_token` / `verify_pass_token` and the
  `validators` team can be removed on the server afterwards. They live outside both repos.

## New dependencies

- `wakelock_plus` keeps the screen awake.
- `screen_brightness` sets application brightness.
- `connectivity_plus` triggers a refetch.

All three are maintained by Flutter Community or widely used. No wallet plugin is added.

## Localization

- New keys go in `app_en.arb` and `app_no.arb`, then `flutter gen-l10n` runs.
- The keys cover:
  - the pass labels, states and wallet errors;
  - the 12 color names;
  - the scanner results and reasons, and the access messages;
  - the Explore tile;
  - the Profile row.
- Dates use `DateFormat.yMMMd(locale)`.

## Design system

The new screens build on `BisoPage`, get colors from `BisoPalette` and `BisoAccent`, and use
CupertinoIcons. They are added to `migratedFiles` in `test/presentation/design_rules_test.dart`.
There are two exceptions:

- the pass card's holographic band and day stripe;
- the scanner's full-screen result colors.

These are fixed semantic colors. They are declared in one file,
`lib/presentation/widgets/member_pass/pass_colors.dart`, which the rules test allows.

## Testing

**Unit**

- **`member_pass_session_test`:**
  - slot selection with positive and negative drift;
  - `msUntilNextSlot` at the edges;
  - `needsRefetch` with 4 and 3 codes remaining;
  - the `shouldRetry` 15 s spacing and in-flight rule;
  - a transient failure keeps a usable active pass (marked offline), or becomes `reconnect` when no
    code is left;
  - a 401 clears the pass, and a 200 `NoPass` replaces an active pass;
  - a clock before the first code triggers a refetch.
- **`member_pass_notifier_test`**, with a fake API and a fake clock/timers via `fakeAsync`:
  - resume and connectivity triggers each fetch;
  - only one fetch is in flight at a time;
  - the keep-alive links survive the swap between screen and presentation.
- **`scan_gate_test`:**
  - key parsing for `v1`, `a1` (including user ids that contain dots), `g1`, garbage and short codes;
  - the 20 s window, including a restart when the member is seen again;
  - the in-flight lock;
  - pruning.
- **`map_scan_outcome_test`:** every result and reason, plus 400, 401, 403, 429, 503 and network
  errors.
- **`member_pass_api_client_test`**, with `MockClient` from `package:http/testing.dart`:
  - every endpoint's success and error shapes, including the two deploy-time 404 rules and the wallet
    404;
  - the Bearer header is sent;
  - exception `toString` never contains a code or a JWT.
- **`oslo_time_test`:**
  - one millisecond before and after 01:00 UTC on the last Sunday of March and of October, for 2026
    and 2027;
  - one ordinary time in July and one in January.
- **`pass_term_test`:** semester labels in spring and fall (both locales), year, three years, and a
  null term.

**Widget** (`pumpBisoScreen` with fake overrides)

- The pass screen in each state: loading, active, active and offline, `noBiIdentity`, `notMember`,
  `expired`, `unavailable`, `reconnect` and signed-out.
- The active pass shows the current code in the QR and the day color name, in both locales.
- Wallet buttons follow the platform and the flags (via `debugDefaultTargetPlatformOverride`).
- Presentation mode applies and restores brightness and wakelock, through fake wrappers behind a
  small `ScreenPresentation` interface.
- **Scanner:**
  - each result display, and auto-dismiss after 3 s;
  - a 403 closes the scanner;
  - an overlong string is denied without an API call.

  The camera sits behind a `ScannerCamera` interface, so tests feed strings without
  `mobile_scanner`.
- **`ScannerGate`:** each access state; the camera is not built before `granted`.
- **Explore:** the scanner tile is shown for `granted`, hidden for `denied`, and hidden while
  loading.
- **Settings:** the Validator Mode row is gone.

**Gate before claiming done:** `flutter analyze` is clean for the new and changed files, and
`flutter test` passes.

## Out of scope

- Any change to BISO-Sites. Endpoint deployment is Markus's.
- An offline scanner.
- An in-app list of scan history.
- "View in Wallet" deep links.
- Removing the server-side functions and team.
