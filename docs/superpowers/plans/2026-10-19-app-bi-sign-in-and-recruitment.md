# App BI Sign-in, Recruitment and Parity Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app signs students in with BI (Appwrite OIDC) instead of linking, lets them apply for jobs and follow their applications, and stops the parity bugs found in the 2026-10-19 audit.

**Architecture:** Server work lands in BISO-Sites so web and app share one code path: the BI student sync and the recruitment apply logic move into `@repo/shared`, the web keeps calling them directly, and `apps/api` exposes them to the app behind an Appwrite JWT. The app calls only `apps/api` for anything privileged.

**Tech Stack:** BISO-Sites: Bun 1.3.1, Next.js 16 (`apps/web`, `apps/api`), node-appwrite through `@repo/api`, vitest, Biome/Ultracite. BISO-Flutter: Flutter 3.47 / Dart 3.13, Riverpod 2, go_router 16, appwrite 26.2, http + `MockClient` tests.

**Spec:** This plan carries its own spec. Owner decisions (2026-10-19): sign-in is **BI + magic link only** (Google and Apple go, like the web); recruitment is **apply + My applications**; include **profile/avatar, expense ledger, AASA + `/auth/verify` page, AI tile + units filter** fixes. Ground truth: research reports of 2026-10-19 in this session, and `docs/superpowers/specs/2026-09-15-app-launch-membership-expenses-design.md` (D1, D4, D6 still hold except D4, which this plan replaces).

**Branches:** BISO-Flutter `feat/bi-sign-in-and-recruitment` (exists). BISO-Sites `feat/app-bi-sign-in-and-recruitment` (create from `main`).

## Global Constraints

- BISO-Sites: Bun only (`bun add … --filter=…`); never import `appwrite`/`node-appwrite` outside `@repo/api`; `bun run check-types` is the type gate (Next builds ignore type errors); `bun x ultracite fix` before finishing.
- `packages/api/appwrite.config.json` and `packages/api/types/appwrite.ts` are generated — no edits, no schema changes in this plan.
- `@repo/shared` must not depend on `@repo/ai` (`@repo/ai` already depends on `@repo/shared`). Pass AI functions in as parameters.
- apps/api user routes: `Authorization: Bearer <Appwrite JWT>`, 401 `{success:false, error:"Authentication required"}` when the `Bearer ` prefix is missing, CORS via `applyCorsHeaders`/`corsPreflightResponse` plus an `OPTIONS` export (pattern: `apps/api/src/app/api/expenses/attachments/route.ts`).
- Flutter: every privileged write goes through `apps/api` (`apiUri()`, `appwriteJwt()` in `lib/data/services/api_auth.dart`); API clients take `http.Client? httpClient` and `ApiJwtProvider? jwtProvider` for tests (pattern: `lib/data/services/profile_api_client.dart`).
- Flutter: new user-facing strings go in `lib/generated/l10n/app_en.arb` and `app_no.arb`; take Norwegian copy from `BISO-Sites/packages/i18n/messages/no/*.json` where the web has it. Files listed in `test/presentation/design_rules_test.dart` must keep passing it; add new screens to `migratedFiles`.
- BI sign-in constants: provider `oidc`; scopes `openid`, `email`, `profile`; success `appwrite-callback-biso://bi-sign-in/success`; failure `appwrite-callback-biso://bi-sign-in/failure`; callback scheme `appwrite-callback-biso` (both URLs verified accepted by `appwrite.biso.no` on 2026-10-19).
- Copy fixed by the web (use verbatim, English; Norwegian from `packages/i18n`):
  - BI button: "Sign in with BI student account"; under it: "BI students: your student membership and member prices follow your BI account."; divider: "Not a BI student? Use a login link".
  - BI failed: "We could not sign you in with BI. Please try again, or use a login link."
  - BI existing account (Appwrite error `type == "general_bad_request"`): "BI could not sign you into your existing BISO account. Use a login link to your student email below, and let us know at biso.no/contact so we can fix the sign-in."
  - `membership.join.needsBiLink` title/body/cta/linkFailed/alreadyLinked/invalidBiEmail and `needsDirectoryRecord` title/body/retry from `packages/i18n/messages/{en,no}/membership.json`.
- Commits: only once the owner has approved committing; then one commit per task on the feature branch, message ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.

## Review Focus

1. A student whose Safari/Chrome still holds an old `appwrite.biso.no` session taps "Sign in with BI": the BI identity must not attach to that stale account. Pinned by `preferEphemeral: true` and deleting the app's current session first (Task 4 test `startBiSignIn ends the current session and uses an ephemeral browser`).
2. The student cancels the BI browser sheet: no error banner, login screen stays usable (Task 4 test `a cancelled BI sign-in is silent`).
3. The app dies between BI sign-in and the sync call: the membership card's button re-runs the sync before offering BI sign-in again (Task 4 test `continueWithBi syncs first and only signs in again without a BI identity`).
4. A job with `cv_required` and required custom questions, submitted twice from a flaky connection: the second call returns `already_applied`, no second row (Task 2 test `a second application to the same job is refused`).
5. Editing only the profile name keeps the bank account and units (Task 6 test `a name edit sends neither bank_account nor departments`).

---

## BISO-Sites

### Task 1: Shared BI student sync and `POST /api/auth/bi-sync`

**Files:**
- Create: `packages/shared/utils/bi-identity-sync.ts` (moved from `apps/web/src/lib/bi-identity-sync.ts`)
- Create: `apps/api/src/app/api/auth/bi-sync/route.ts`, `apps/api/src/app/api/auth/bi-sync/route.test.ts`
- Create: `apps/api/src/lib/jwt-session.ts`, `apps/api/src/lib/jwt-session.test.ts`
- Delete: `apps/web/src/lib/bi-identity-sync.ts`
- Modify: `apps/web/src/app/(auth)/auth/oauth/route.ts`, `apps/web/src/lib/actions/bi-identity.ts`, `apps/web/src/lib/actions/bi-identity.test.ts` (import path + mocks), any existing tests of the moved module (move them next to it)
- Modify docs: `apps/web/CLAUDE.md` Auth bullet (BI + magic link only; OAuth return is `/auth/oauth`, magic link `/auth/callback`), `apps/docs/content/docs/public-website/authentication-and-sessions.mdx` (add "Mobile app" subsection: app signs in with the same OIDC provider, then calls `POST /api/auth/bi-sync`)

**Interfaces:**
- Produces (shared): `syncBiStudentIdentityAfterSignIn(userId: string, options?: { currentSessionId?: string }): Promise<BiIdentitySyncResult>`, `syncBiStudentIdentityFor(subject: SyncSubject)`, `BiIdentitySyncResult`, `SyncSubject`, `isFreshMergeIntoPasswordAccount`, `shouldMarkEmailVerified` — unchanged signatures, imported as `@repo/shared/utils/bi-identity-sync`. Drop `unstable_rethrow` (nothing inside throws Next control-flow errors); keep `import "server-only"`.
- Produces (API): `POST /api/auth/bi-sync`, no body. Responses:
  - 401 `{success:false, error:"Authentication required"}` — no Bearer, or `account.get()` fails.
  - 200 `{success:true, studentId:string, hasEmployeeId:boolean, campusHint:string|null}`
  - 200 `{success:false, error: "no_bi_identity"|"invalid_bi_email"|"directory_unavailable"|"already_linked"|"sync_failed"|"not_authenticated"}` (domain outcomes are 200 so the app reads one shape).
- Produces (lib): `sessionIdFromJwt(jwt: string): string | null` — base64url-decodes the payload's `sessionId`. Only call it after `account.get()` has accepted the JWT (Appwrite has then verified the signature), and only use it when the payload's `userId` equals `user.$id`.

- [ ] **Step 1: Move the module.** `git mv` to `packages/shared/utils/bi-identity-sync.ts`, fix imports (`@repo/connectors/azure/bi-directory`, `./bi-student`, `./profile-fields`), update the three web importers. Run `bun run check-types --filter=web` → PASS, and `bun run test` in `apps/web` for `bi-identity.test.ts` → PASS.
- [ ] **Step 2: Failing tests** `jwt-session.test.ts`: `returns the sessionId claim`, `returns null for a malformed token`, `returns null when the claim is missing`. `route.test.ts` (mock `@/lib/auth`, `@repo/shared/utils/bi-identity-sync` like `membership/route.test.ts` mocks its deps):
  - `401 without a bearer token`
  - `401 when Appwrite rejects the JWT`
  - `syncs the JWT's user and passes the JWT's session as currentSessionId` → `syncBiStudentIdentityAfterSignIn` called with `("user-1", { currentSessionId: "session-1" })`, 200 body equals the sync result
  - `omits currentSessionId when the JWT names another user`
  - `returns sync_failed when the sync throws` → 200 `{success:false, error:"sync_failed"}`
  Run `cd apps/api && bun run test -- bi-sync jwt-session` → FAIL (modules missing).
- [ ] **Step 3: Implement** `sessionIdFromJwt` and the route (`runtime = "nodejs"`, CORS, `OPTIONS`).
- [ ] **Step 4: Verify** `cd apps/api && bun run test` → PASS; `bun run check-types --filter=api --filter=web` → PASS; `bun x ultracite fix`.
- [ ] **Step 5: Docs** edits listed above.
- [ ] **Step 6: Commit** `feat(api): expose the BI student sync to the app`.

### Task 2: Shared recruitment apply + `apps/api` application routes

**Files:**
- Create: `packages/shared/recruitment/apply.ts`, `packages/shared/recruitment/apply.test.ts`; add `"./recruitment/apply"` to `packages/shared/package.json#exports` (mirror the existing `./recruitment/application-documents` entry)
- Create: `apps/api/src/app/api/recruitment/applications/route.ts`, `route.test.ts`
- Modify: `apps/web/src/app/actions/jobs.ts` — `submitJobApplication` and `listMyApplications` become thin wrappers over the shared functions (same exported signatures and return shapes the web components use today)

**Interfaces:**
- Produces (shared):
  ```ts
  export type RecruitmentApplyErrorCode =
    | "invalid_data" | "vacancy_closed" | "members_only" | "answer_required"
    | "already_applied" | "cv_required" | "cover_letter_required"
    | "invalid_file" | "submit_failed";
  export interface RecruitmentApplicant { email: string; name?: string | null; userId: string }
  export interface RecruitmentApplyDeps {
    extractPdfText: (pdf: Buffer) => Promise<string>;
    isMember: () => Promise<boolean>; // called only for audience "members"
  }
  export type RecruitmentApplyResult =
    | { success: true; applicationId: string; screening: RecruitmentScreeningJob | null }
    | { success: false; code: RecruitmentApplyErrorCode; error: string };
  export function submitRecruitmentApplication(
    input: { applicant: RecruitmentApplicant; jobId: string; formData: FormData },
    deps: RecruitmentApplyDeps
  ): Promise<RecruitmentApplyResult>;
  export function runRecruitmentScreening(
    job: RecruitmentScreeningJob,
    screen: typeof import("@repo/ai/server/recruitment-screener").screenApplication // pass the function; type it structurally in shared
  ): Promise<void>;
  export function listApplicationsForApplicant(email: string): Promise<MyApplicationView[]>;
  export interface MyApplicationView { /* moved verbatim from apps/web/src/app/actions/jobs.ts */ }
  ```
  `RecruitmentScreeningJob` holds what the web's `after()` block reads today; `screening` is null when `auto_screen` is off. Callers run `runRecruitmentScreening` inside `after()`.
- Produces (API), both with CORS + `OPTIONS`:
  - `POST /api/recruitment/applications`, `multipart/form-data`: `job_id` plus the web's exact field names (`applicant_name`, `applicant_phone`, `linkedin_url`, `current_role`, `current_employer`, `availability` newline-separated, `gdpr_consent=true`, `answer.<qid>`, `answer_label.<qid>`, `answer_type.<qid>`, `resume` PDF, `cover_letter` PDF). Applicant email/name come from `account.get()`, never the form; require `isAuthenticatedAppwriteUser(user) && user.email`. `isMember` = profile `student_id` → `getMembershipStatusForStudent(…, refresh)` as in `apps/api/src/app/api/membership/route.ts`. Responses: 201 `{success:true, applicationId}`; 401 auth; `{success:false, code, error}` with 400 (`invalid_data`, `answer_required`, `cv_required`, `cover_letter_required`, `invalid_file`), 403 `members_only`, 404 `vacancy_closed`, 409 `already_applied`, 500 `submit_failed`.
  - `GET /api/recruitment/applications` → 200 `{applications: MyApplicationView[]}`; 401 auth.

- [ ] **Step 1: Failing tests** `apply.test.ts` (mock `@repo/api/server` admin client in-memory): `rejects a closed vacancy`, `asks a non-member for membership on a members-only job`, `requires every required custom answer`, `requires a CV when the job says so`, `requires a PDF cover letter`, `rejects a phone longer than 20 characters before uploading anything` (column `applicant_phone` is size 20), `a second application to the same job is refused` (`already_applied`, no upload, no row), `stores files, application and answers with staff-only permissions` (`buildRecruitmentStaffRowPermissions()`), `lists only the applicant's own applications`. Route tests: `401 without a bearer token`, `takes the email from the account, not the form`, `maps each error code to its status`, `201 with the application id`. Run → FAIL.
- [ ] **Step 2: Implement** by moving the body of `submitJobApplication`/`listMyApplications` into `apply.ts`; validate files and phone length before any upload and return a specific `code` (today they fall into a generic catch).
- [ ] **Step 3: Rewire web** `submitJobApplication(jobId, formData)` → session user → `submitRecruitmentApplication(…, { extractPdfText, isMember: async () => (await getLiveMembershipStatus()).isMember })`, run screening in `after()`, keep `revalidatePath` calls, map failure to `{success:false, error}`. `listMyApplications` → `listApplicationsForApplicant(user.email)`.
- [ ] **Step 4: Verify** `bun run test` in `packages/shared`, `apps/api`, `apps/web` → PASS; `bun run check-types` → PASS; `bun x ultracite fix`.
- [ ] **Step 5: Commit** `feat(api): let the app apply for jobs and list its applications`.

### Task 3: Universal links claim only the app's paths, and `/auth/verify` has a page

**Files:**
- Modify: `apps/web/public/.well-known/apple-app-site-association`, `apps/web/src/app/api/aasa/route.ts`
- Create: `apps/web/src/lib/app-links.ts` (exports `APP_LINK_COMPONENTS`, used by the route; the static file mirrors it), `apps/web/src/lib/app-links.test.ts`
- Create: `apps/web/src/app/(auth)/auth/verify/page.tsx`

**Interfaces:**
- `APP_LINK_COMPONENTS = [{ "/": "/auth/verify", comment: "app sign-in link" }, { "/": "/app/*", comment: "app shortcuts and returns" }]`.
- `/auth/verify?userId&secret`: renders, never consumes the token. Heading "Open BISO to finish signing in"; body "This sign-in link belongs to the BISO app. If the app did not open, open this email on the phone where BISO is installed."; primary link `biso://auth/verify?userId=…&secret=…` labelled "Open the BISO app"; secondary link "Sign in on the website instead" → `/auth/login`. Without both params: only the website link. Follow `components/login.tsx` styling conventions.

- [ ] **Step 1: Failing test** `app-links.test.ts`: `claims the app sign-in link and /app/*`, `does not claim the website's own auth returns` (no component matches `/auth/callback`, `/auth/oauth`, `/auth/login`, `/auth/*`), `the static association file matches APP_LINK_COMPONENTS` (read the JSON file). Run → FAIL.
- [ ] **Step 2: Implement** constant, route, static file, page.
- [ ] **Step 3: Verify** `bun run test` in `apps/web` → PASS; `bun run check-types --filter=web` → PASS.
- [ ] **Step 4: Commit** `fix(web): claim only the app's own links for universal links`.

## BISO-Flutter

### Task 0 (done): Flutter deep linking off, only `/auth/verify` signs the app in

Done in the working tree: `FlutterDeepLinkingEnabled=false`, `flutter_deeplinking_enabled=false`, `magicLinkRouteFor(Uri)` in `deep_link_service.dart`; tests `deep_link_platform_config_test.dart`, `deep_link_magic_link_route_test.dart`; verified on the iOS simulator (cold and warm). Commit `fix: route sign-in links through DeepLinkService alone`.

### Task 4: Sign in with BI; remove Google, Apple and account linking

**Files:**
- Create: `lib/data/services/bi_sign_in_service.dart`, `lib/data/services/bi_sync_api_client.dart`
- Create: `test/data/services/bi_sign_in_service_test.dart`, `test/data/services/bi_sync_api_client_test.dart`, `test/presentation/screens/auth/login_screen_bi_test.dart`
- Modify: `pubspec.yaml` (`flutter_web_auth_2: ^5.1.0` as a direct dependency — already resolved transitively at 5.1.0), `android/app/src/main/AndroidManifest.xml` (flutter_web_auth_2 `CallbackActivity`, scheme `appwrite-callback-biso`, `android:exported="true"`, `android:taskAffinity=""`)
- Modify: `lib/data/services/auth_service.dart` (delete `signInWithGoogle`/`signInWithApple`), `lib/providers/auth/auth_provider.dart` (replace them with `signInWithBi()`), `lib/presentation/screens/auth/login_screen.dart` (BI primary; magic link below; delete Google/Apple buttons and SVGs), `lib/data/services/deep_link_service.dart` (delete `oauth-callback`/`oauth-failed` handling and `linked` in `membershipRouteFor`), `lib/main.dart` (drop `linked:` from `MembershipScreen`), `lib/presentation/screens/profile/membership_screen.dart` (delete `membershipLinkUrl`, `linked`, `_openLinkPage`; `needsBiLink` and `needsDirectoryRecord` cards per below), `lib/presentation/screens/profile/member_pass_screen.dart` (`noBiIdentity` action), `lib/presentation/screens/profile/profile_screen.dart:413` label, `lib/providers/membership/membership_overview_provider.dart` (delete `noteLinkStarted`/`_linkStarted` if nothing else uses them), `test/data/services/deep_link_membership_route_test.dart` (delete the `linked` case), `CLAUDE.md` (membership section: BI sign-in, no linking)

**Interfaces:**
- `BiSyncApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})` → `Future<BiSyncResult> sync()` — `POST apiUri('/api/auth/bi-sync')` with Bearer; `BiSyncResult { bool success; String? studentId; String? campusHint; BiSyncError? error }`, `enum BiSyncError { noBiIdentity, invalidBiEmail, directoryUnavailable, alreadyLinked, syncFailed, notAuthenticated }` parsed from the API's snake_case codes; a non-200 or network failure → `syncFailed`.
- `typedef WebAuthenticate = Future<String> Function({required String url, required String callbackUrlScheme, required bool preferEphemeral});`
- `BiSignInService({WebAuthenticate? authenticate, Account? account, BiSyncApiClient? syncApi})`:
  - `Future<BiSignInOutcome> signIn()` → `deleteSession('current')` (ignore errors) + `clearAppwriteJwtCache()`; open `'${AppConstants.appwriteEndpoint}/account/tokens/oauth2/oidc?project=biso&success=…&failure=…&scopes[]=openid&scopes[]=email&scopes[]=profile'` (encode params) with `preferEphemeral: true`; parse with `parseBiCallback`; on success `account.createSession(userId, secret)`, `clearAppwriteJwtCache()`, then `syncApi.sync()`.
  - `Future<BiSyncResult> syncOnly()` → `syncApi.sync()`.
  - `sealed class BiSignInOutcome`: `BiSignedIn(BiSyncResult sync)`, `BiSignInCancelled()`, `BiSignInFailed(BiSignInFailure reason)` with `enum BiSignInFailure { failed, existingAccount }`.
  - `@visibleForTesting BiCallback parseBiCallback(Uri uri)`: success path with `userId`+`secret` → credentials; failure path whose `error` JSON has `type == "general_bad_request"` → `existingAccount`; anything else → `failed`.
  - A `PlatformException` with code `CANCELED` from `authenticate` → `BiSignInCancelled`.
- `AuthNotifier.signInWithBi()` → returns `BiSignInOutcome`; on `BiSignedIn` runs `refreshAuthState()`.
- Create `lib/providers/auth/bi_sign_in_provider.dart`: `biSignInServiceProvider`, and `Future<BiSyncResult?> continueWithBi(WidgetRef ref)` for the membership/member-pass buttons: `syncOnly()` first; on `noBiIdentity` → `authStateProvider.notifier.signInWithBi()` (null result when cancelled); afterwards `membershipOverviewProvider.notifier.refresh()`. The caller shows `alreadyLinked`/`invalidBiEmail`/`syncFailed` with the web `needsBiLink.*` copy.
- Card copy: `needsBiLink` → web `needsBiLink.title`/`body`, button `needsBiLink.cta` → `continueWithBi`. `needsDirectoryRecord` → web `needsDirectoryRecord.title`/`body`, button `retry` → `continueWithBi`. Member pass `noBiIdentity` → same handler.
- Login routing after `BiSignedIn`: `needsOnboarding` → `/onboarding`, else `/home`; a sync error is shown as a snackbar with the web copy, the student stays signed in.

- [ ] **Step 1: Failing tests.** `bi_sync_api_client_test.dart`: `posts with a bearer token and parses success`, `maps each error code`, `a 500 is syncFailed`. `bi_sign_in_service_test.dart` (fake `authenticate`, fake account, fake sync): `startBiSignIn ends the current session and uses an ephemeral browser` (asserts URL contains `/account/tokens/oauth2/oidc`, the three scopes, both callback URLs; `preferEphemeral == true`; `deleteSession('current')` called first), `creates the session from the callback credentials then syncs`, `a cancelled BI sign-in is silent` (→ `BiSignInCancelled`, no session, no sync), `general_bad_request is existingAccount`, `any other failure is failed`, `continueWithBi syncs first and only signs in again without a BI identity`. `login_screen_bi_test.dart`: `shows the BI button above the login-link form`, `shows no Google or Apple button`, `a cancelled sign-in shows nothing`, `existing-account failure shows the web copy`. Run `flutter test <files>` → FAIL.
- [ ] **Step 2: Implement** service, client, notifier methods, login screen, Android activity, membership/member-pass/profile changes, deletions.
- [ ] **Step 3: Verify** `flutter test` → all PASS; `flutter analyze` → no new issues; `grep -rn "membership/link\|signInWithGoogle\|signInWithApple\|oauth-callback" lib` → no hits.
- [ ] **Step 4: Commit** `feat: sign in with BI and retire account linking`.

### Task 5: Apply for jobs and follow applications

**Files:**
- Modify: `lib/data/models/job_model.dart`, `lib/data/services/job_service.dart`, `lib/presentation/screens/explore/jobs_screen.dart` (rows push the detail route; delete `_JobDetailSheet` and the `openJobId` extra), `lib/main.dart` (routes below), `lib/data/services/deep_link_service.dart` (`biso://job?id=` → `/explore/volunteer/<id>`; `https://biso.no/jobs/<slug>` and `/app/jobs/<slug>` → `/explore/volunteer/<slug>`), `lib/presentation/screens/profile/profile_screen.dart` (row "My applications" → `/profile/applications`), ARB files
- Create: `lib/data/models/job_application.dart`, `lib/data/services/recruitment_api_client.dart`, `lib/presentation/screens/jobs/job_detail_screen.dart`, `lib/presentation/screens/jobs/job_application_screen.dart`, `lib/presentation/screens/jobs/my_applications_screen.dart`
- Test: `test/data/models/job_model_test.dart`, `test/data/services/recruitment_api_client_test.dart`, `test/presentation/screens/jobs/job_application_screen_test.dart`, extend `test/data/services/job_service_query_test.dart`

**Interfaces:**
- Consumes: Task 2's API contract.
- `JobModel` adds: `customQuestions: List<JobQuestion>` (parsed from the `custom_questions` JSON string; bad JSON → empty), `cvRequired`, `membersOnly` (`metadata.audience == "members"`), `paid`, `employmentType`, `company`, `location`, `contactName`, `contactEmail`, `commitment`, `term`, `startDate`, `departmentName`, `campusName`; `shortDescription` falls back to `metadata.short_description`. `JobQuestion { String id; String label; JobQuestionType type; bool required; List<String> options }`, `enum JobQuestionType { text, longText, select, multiSelect, boolean, number }` from `text|long_text|select|multi_select|boolean|number`.
- `JobService`: select adds `department.Name`, `department.type`, `campus.name`; adds `Future<JobModel?> getJob(String idOrSlug)` (open vacancies only: published and deadline null or ≥ now).
- Routes: `/explore/volunteer/:jobId` → `JobDetailScreen(idOrSlug)`, `/explore/volunteer/:jobId/apply` → `JobApplicationScreen(jobId)`, `/profile/applications` → `MyApplicationsScreen`.
- `RecruitmentApiClient({httpClient, jwtProvider})`: `Future<ApplicationSubmitResult> submit(JobApplicationDraft draft)` (multipart with Task 2's field names; `multi_select` joined with `,`, `boolean` as `"true"`/`""`), `Future<List<MyApplication>> listMine()`. `ApplicationSubmitResult` is `submitted(applicationId)` or `rejected(ApplicationError code, String message)` with `enum ApplicationError` mirroring Task 2's codes plus `notAuthenticated`, `network`.
- Apply flow mirrors the web's 4 steps (Contact, Questions — hidden without questions, Documents, Review). Gates: signed out → "Sign in to apply" → `/auth/login`; members-only and `!hasValidMembershipProvider` → "Become a member" → `/profile/membership`. Client checks: PDF only, ≤ 5 MB (5 242 880 bytes), cover letter required, CV required when `cvRequired`, phone ≤ 20 chars including country code (default `+47`), required answers, consent checkbox with the web's consent text verbatim. Server stays the real gate; show its message for each `ApplicationError`.
- Detail screen shows what the web detail shows (type, company, department, location, deadline with year, paid/volunteer, commitment/term/start date, campus, contact mailto, members-only badge) and an Apply button (hidden when the deadline has passed).
- My applications: status label (Submitted / Reviewed / Interview / Accepted / Not selected), job title + campus, next interview (time, location, `meeting_url` opens externally), answers, "Stored until".

- [ ] **Step 1: Failing tests:** `job_model_test.dart`: `parses custom questions of every type`, `bad custom_questions JSON gives no questions`, `members-only and cv_required come from metadata`, `short description falls back to metadata`. `recruitment_api_client_test.dart`: `sends the web's field names and both PDFs with a bearer token`, `maps 409 already_applied`, `maps 403 members_only`, `lists my applications`. `job_application_screen_test.dart`: `signed-out students are asked to sign in`, `members-only jobs ask non-members to join`, `continue stays disabled until required answers are filled`, `rejects a non-PDF and a file over 5 MB`, `submit needs consent`. `job_service_query_test.dart`: `getJob reads by slug or id and only open vacancies`. Run → FAIL.
- [ ] **Step 2: Implement** models, service, client, screens, routes, deep links, profile row, strings.
- [ ] **Step 3: Verify** `flutter test` → PASS; `flutter analyze` → no new issues.
- [ ] **Step 4: Commit** `feat: apply for jobs and follow applications in the app`.

### Task 6: Profile edits keep bank account and units; avatar upload works

**Files:** `lib/data/services/auth_service.dart` (`updateUserProfile`, `_uploadAvatar`), `lib/data/models/user_model.dart` (read `departments`, fall back to `department_ids`); tests `test/data/services/auth_service_profile_test.dart`, `test/data/models/user_model_test.dart` (create or extend).

**Interfaces:** `updateUserProfile` sends only fields that were passed (plus `avatar` when one was uploaded) — never a field copied from `getCurrentUser()`. `_uploadAvatar` uses `ID.unique()` as the file id (≤ 36 chars) and keeps `avatar_<userId>_<ms>.jpg` as the file name.

- [ ] **Step 1: Failing tests:** `a name edit sends neither bank_account nor departments`, `a departments edit sends departments`, `avatar file ids fit Appwrite's 36-character limit`, `UserModel reads departments`. Run → FAIL.
- [ ] **Step 2: Implement.** Check `avatars` bucket permissions in `BISO-Sites/packages/api/appwrite.config.json`; if users cannot create there, stop and report instead of changing the upload path.
- [ ] **Step 3: Verify** `flutter test` → PASS. **Step 4: Commit** `fix: keep bank account and units when editing the profile`.

### Task 7: Expenses post to the right ledger account

**Files:** `lib/data/models/expense_v2_models.dart`, `lib/presentation/screens/expense/create_expense_screen.dart`, create `lib/core/utils/expense_cost_types.dart`; tests `test/core/utils/expense_cost_types_test.dart`, extend `test/data/services/expense_api_client_test.dart`.

**Interfaces:** Dart port of `BISO-Sites/packages/shared/utils/expense-cost-types.ts`: `const defaultExpenseCostTypes` (slugs `travel`, `social`, `academic`, `other`, with the web labels) and `String defaultCostTypeSlugForCategory(String? category)` using the same OCR map (`travel→travel, accommodation→travel, meal→social, event-materials→academic, supplies/fee/other→other`). Receipt draft gains `costType` (defaults from its OCR category; the student can change it, as on web `expense-v3/expense-split-view.tsx`); submit payload sends `cost_type`, `sort_order` (receipt index) per attachment and `submitter_is_financial_manager` (checkbox with the web's label). If the web reads cost types from a configurable source rather than the defaults, use that same source through `apps/api` or report it.

- [ ] **Step 1: Failing tests:** `maps every OCR category like the web`, `submit sends cost_type and sort_order for each receipt`, `submit sends submitter_is_financial_manager`. Run → FAIL. **Step 2: Implement.** **Step 3: Verify** `flutter test` → PASS. **Step 4: Commit** `fix: send the cost type and approver flags with reimbursements`.

### Task 8: Hide the AI assistant; list only public units

**Files:** `lib/presentation/screens/explore/explore_screen.dart` (remove the AI tile), `lib/data/services/deep_link_service.dart` (drop the `ai`/`ai-chat` universal-link case), `lib/data/services/department_service.dart`, create `lib/core/utils/unit_visibility.dart`; tests `test/core/utils/unit_visibility_test.dart`, extend `test/data/services/department_service_test.dart`.

**Interfaces:** `bool isPublicUnit(...)` — a Dart port of `BISO-Sites/packages/shared/utils/unit-visibility.ts` with the same inputs and rules; port its existing test cases one-for-one. `DepartmentService` applies it after the `active == true` query.

- [ ] **Step 1: Failing tests** ported from the TS tests plus `the explore screen shows no AI assistant tile`. Run → FAIL. **Step 2: Implement.** **Step 3: Verify** `flutter test` → PASS. **Step 4: Commit** `fix: hide the retired assistant and list only public units`.

## Order and parallelism

- BISO-Sites Tasks 1, 2, 3 touch disjoint files and can run in parallel.
- Flutter Task 4 and Task 5 both edit `main.dart` and `deep_link_service.dart` (different functions); Task 7 is disjoint. Run 4, 5, 7 in parallel with localized edits; run 6 and 8 after 4 (6 shares `auth_service.dart`, 8 shares `deep_link_service.dart`).
- Release order: deploy `apps/api` (Tasks 1–2) and `apps/web` (Task 3) before shipping an app build with Tasks 4–5.

## Manual checks after merge (need real accounts/devices)

- iPhone + Android: BI sign-in for a new student, a returning student, and a student whose magic-link account uses their `s…@bi.no` email (lands in the same account, membership verified).
- Magic link opened from Outlook and Gmail, app closed and open.
- Apply to a members-only job with questions and a CV; see it under My applications and in admin.
