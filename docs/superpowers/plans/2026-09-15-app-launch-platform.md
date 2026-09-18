# App Launch — Platform Hardening and API (BISO-Sites) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the expense and profile permission holes, fix the 24SevenOffice customer id scheme, enforce membership expiry and one-account BI links, and add the API routes and web page the student app needs.

**Architecture:** Every write to an expense or profile row moves behind `apps/api` / web server code using the Appwrite admin key after an explicit ownership or allow-list check; row grants become read-only. Membership status stays a live 24SevenOffice category read, now filtered by the `memberships` row's expiry. The app gets a `GET /api/membership` overview (gate state, status, plans), an app-aware membership checkout, receipt upload and draft delete routes, and a web page it opens for BI linking.

**Tech Stack:** Bun 1.4 workspaces, Next.js 16 route handlers and server actions, node-appwrite 28 (TablesDB), zod, vitest (`bun test` in `packages/connectors`), Biome.

**Spec:** `/Users/markus/Documents/dev/BISO-Flutter/.claude/worktrees/problem-to-solve-3bff42/docs/superpowers/specs/2026-09-15-app-launch-membership-expenses-design.md` (Phases 1 and 2).

## Global Constraints

- Repo: BISO-Sites. Work on branch `feat/app-launch-hardening` created from `main` @ `333165b9`, in the worktree `/Users/markus/Documents/dev/BISO-Sites/.claude/worktrees/app-launch-hardening`. All paths below are relative to that root.
- Tests: `bun run test` inside the package (`apps/api` runs `NODE_ENV=test vitest run`; `packages/shared` and `apps/web` run `vitest run`; `packages/connectors` runs `bun test ./src`). Typecheck: `bun run check-types` in `apps/api`, `apps/web`, `packages/shared`. Lint: `bunx biome lint <changed paths>` from the repo root.
- Never run a lockdown script with `--apply`, never `appwrite push`, never change the Appwrite console. Those are owner steps listed in the spec's rollout.
- Commit messages: imperative sentence case, no type prefix (repo style, e.g. "Harden the posting guard and clearing account checks"), ending with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Row permissions are built with `Permission.read(Role.user(id))`, which serialises to `read("user:<id>")`.
- A membership counts only while its `memberships` row has `status == true` and an `expiryDate` on or after today's date in `Europe/Oslo`; an unreadable `expiryDate` counts as expired.
- 24SevenOffice membership customers: `Id` = digits of the BI student email (`s1715738@bi.no` → `1715738`); `ExternalId` = `String(employeeId)`.
- A `student_id` may sit on one `user` row only. A link is verified when the holder has an Appwrite OIDC identity whose email parses (strict `s<digits>@bi.no`) to that student id.
- API error messages are English sentences written for students; keep the existing `{ message }` (payment/membership routes) or `{ success: false, error }` (expense routes) shapes per route family.

## File map

| Area | Files |
|---|---|
| Expense rows | `apps/api/src/lib/expense-payload.ts`, `apps/api/src/app/api/expenses/draft/route.ts`, `apps/api/src/app/api/expenses/submit/route.ts` (+ tests) |
| Receipts | `apps/api/src/lib/receipt-file.ts`, `apps/api/src/app/api/expenses/attachments/route.ts` (+ tests) |
| App config | `apps/api/src/app/api/config/route.ts` (+ test) |
| Profile | `packages/shared/utils/profile-fields.ts`, `apps/web/src/lib/actions/user.ts`, `apps/web/src/lib/actions/bi-identity.ts`, delete `apps/web/src/lib/actions/profile-permissions.ts`, `apps/api/src/app/api/profile/route.ts`, `packages/api/appwrite.config.json`, `packages/api/appwrite-config-permissions.test.ts` |
| Expiry | `packages/shared/utils/membership-status.ts` (+ new test) |
| 24SO ids | `packages/connectors/src/24sevenoffice/company.ts` (+ new bun test), `packages/shared/utils/membership-fulfilment.ts`, docs |
| One link per BI account | `packages/shared/utils/bi-student.ts`, `apps/web/src/lib/actions/bi-identity.ts`, `apps/web/src/app/api/auth/bi-link/route.ts`, `apps/web/src/lib/account-link-return.ts`, `apps/web/src/components/account-link-session-cleanup.tsx`, `apps/web/src/app/(public)/membership/join/gate-states.tsx`, `apps/web/src/components/onboarding/onboarding-flow.tsx`, `apps/web/src/app/(public)/onboarding/page.tsx`, i18n messages |
| Lockdown scripts | `packages/shared/utils/row-permission-lockdown.ts` (+ test), `packages/shared/scripts/revoke-expense-owner-writes.ts`, `packages/shared/scripts/lock-profile-rows.ts`, `packages/shared/package.json` |
| Membership API | `packages/shared/utils/membership-gate.ts`, `packages/shared/utils/membership-catalog.ts` (moved from web), `apps/api/src/lib/membership-status-cache.ts`, `apps/api/src/app/api/membership/route.ts` (+ tests) |
| Link page | `apps/web/src/lib/membership-link-state.ts`, `apps/web/src/app/(public)/membership/link/page.tsx`, `apps/web/src/app/(public)/membership/link/linked-state.tsx` |
| App checkout | `apps/api/src/app/api/payment/[provider]/membership-checkout/route.ts`, `packages/shared/utils/checkout-return.ts`, `apps/api/src/app/api/payment/return/route.ts` (+ tests) |

The lockdown scripts live in `packages/shared` rather than `packages/api` (where the content cutover script lives) because the profile script needs `parseBiStudentEmail` from `packages/shared`, and `packages/shared` already depends on `packages/api` — the reverse import would be circular.

---

### Task 1: Keep expense rows read-only for their submitter

**Files:**
- Modify: `apps/api/src/lib/expense-payload.ts`
- Modify: `apps/api/src/lib/expense-payload.test.ts`
- Modify: `apps/api/src/app/api/expenses/draft/route.ts`
- Modify: `apps/api/src/app/api/expenses/draft/route.test.ts`
- Modify: `apps/api/src/app/api/expenses/submit/route.ts`
- Modify: `apps/api/src/app/api/expenses/submit/route.test.ts`

**Interfaces:**
- Produces: `buildExpenseRowPermissions(userId: string): string[]` returning `['read("user:<id>")']`. Draft and submit write existing drafts only through the admin client.

- [ ] **Step 1: Write the failing tests**

In `apps/api/src/lib/expense-payload.test.ts`, change the import to `import { buildExpenseRowInput, buildExpenseRowPermissions, parseExpensePayload } from "./expense-payload";` and add inside the `describe`:

```ts
  it("grants the submitter read access only, so an expense cannot be edited through Appwrite", () => {
    expect(buildExpenseRowPermissions("user-id")).toEqual([
      'read("user:user-id")',
    ]);
  });
```

Replace `apps/api/src/app/api/expenses/draft/route.test.ts` with:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const sessionDb = vi.hoisted(() => ({
  createRow: vi.fn(),
  getRow: vi.fn(),
  updateRow: vi.fn(),
}));

const adminDb = vi.hoisted(() => ({
  createRow: vi.fn(),
  deleteRow: vi.fn(),
  getRow: vi.fn(),
  updateRow: vi.fn(),
}));

const storage = vi.hoisted(() => ({
  deleteFile: vi.fn(),
}));

const account = vi.hoisted(() => ({
  get: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  createAuthenticatedClient: vi.fn(async () => ({ account, db: sessionDb })),
}));

vi.mock("@repo/api/server", () => ({
  createAdminClient: vi.fn(async () => ({ db: adminDb, storage })),
}));

vi.mock("@repo/shared/utils/feature-flags-server", () => ({
  isFeatureEnabled: vi.fn(async () => true),
}));

import { POST } from "./route";

const DRAFT_BODY = {
  bank_account: "1234.56.78901",
  campus: "1",
  department: "dept-1",
  total: 100,
};

function draftRequest(body: Record<string, unknown>) {
  return new Request("https://api.example/expenses/draft", {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
    method: "POST",
  }) as never;
}

describe("expense draft route", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    account.get.mockResolvedValue({ $id: "submitter-1" });
    adminDb.createRow.mockResolvedValue({ $id: "expense-1" });
    adminDb.updateRow.mockResolvedValue({ $id: "expense-1" });
  });

  it("creates new drafts through the admin client, readable by the submitter only", async () => {
    const response = await POST(draftRequest(DRAFT_BODY));

    expect(response.status).toBe(200);
    expect(sessionDb.createRow).not.toHaveBeenCalled();
    expect(adminDb.createRow).toHaveBeenCalledWith(
      "app",
      "expense",
      expect.any(String),
      expect.objectContaining({
        status: "draft",
        total: 100,
        userId: "submitter-1",
      }),
      ['read("user:submitter-1")']
    );
  });

  it("updates an owned draft through the admin client, never the caller's session", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      status: "draft",
      userId: "submitter-1",
    });

    const response = await POST(
      draftRequest({ ...DRAFT_BODY, expenseId: "expense-1", total: 250 })
    );

    expect(response.status).toBe(200);
    expect(sessionDb.updateRow).not.toHaveBeenCalled();
    expect(adminDb.updateRow).toHaveBeenCalledWith(
      "app",
      "expense",
      "expense-1",
      expect.objectContaining({ status: "draft", total: 250 })
    );
  });

  it("refuses to update an expense that belongs to someone else", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      status: "draft",
      userId: "someone-else",
    });

    const response = await POST(
      draftRequest({ ...DRAFT_BODY, expenseId: "expense-1" })
    );

    expect(response.status).toBe(403);
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });

  it("refuses to update an expense that has left draft", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      status: "pending",
      userId: "submitter-1",
    });

    const response = await POST(
      draftRequest({ ...DRAFT_BODY, expenseId: "expense-1" })
    );

    expect(response.status).toBe(409);
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });
});
```

In `apps/api/src/app/api/expenses/submit/route.test.ts`:
- change the hoisted `adminDb` to `{ createRow: vi.fn(), getRow: vi.fn(), updateRow: vi.fn() }`;
- in `beforeEach`, add `adminDb.getRow.mockReset(); adminDb.updateRow.mockReset(); adminDb.updateRow.mockResolvedValue({});`;
- change the expected permissions in the existing test from `['read("user:submitter-1")', 'update("user:submitter-1")']` to `['read("user:submitter-1")']`;
- add these tests inside the `describe`:

```ts
  it("updates an owned draft through the admin client before submitting it", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      status: ExpensesStatus.DRAFT,
      userId: "submitter-1",
    });

    const response = await POST(
      submitRequest({
        bank_account: "1234.56.78901",
        campus: "1",
        department: "dept-1",
        expenseId: "expense-1",
        total: 100,
      })
    );

    expect(response.status).toBe(200);
    expect(adminDb.updateRow).toHaveBeenCalledWith(
      "app",
      "expense",
      "expense-1",
      expect.objectContaining({ status: ExpensesStatus.DRAFT, total: 100 })
    );
    expect(sessionDb.updateRow).not.toHaveBeenCalled();
  });

  it("refuses to submit an expense that belongs to someone else", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      status: ExpensesStatus.DRAFT,
      userId: "someone-else",
    });

    const response = await POST(
      submitRequest({
        bank_account: "1234.56.78901",
        campus: "1",
        department: "dept-1",
        expenseId: "expense-1",
        total: 100,
      })
    );

    expect(response.status).toBe(403);
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });

  it("marks a legacy-flow submission pending through the admin client", async () => {
    const response = await POST(
      submitRequest({
        bank_account: "1234.56.78901",
        campus: "1",
        department: "dept-1",
        total: 100,
      })
    );

    expect(response.status).toBe(200);
    expect(adminDb.updateRow).toHaveBeenCalledWith(
      "app",
      "expense",
      "expense-1",
      { status: ExpensesStatus.PENDING }
    );
    expect(sessionDb.updateRow).not.toHaveBeenCalled();
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/expense-payload.test.ts src/app/api/expenses/draft src/app/api/expenses/submit`
Expected: FAIL — permissions still include `update("user:…")`, and draft/submit updates go through `sessionDb.updateRow`.

- [ ] **Step 3: Implement**

In `apps/api/src/lib/expense-payload.ts`, replace `buildExpenseRowPermissions`:

```ts
/**
 * Row permissions for an expense: the submitter can read it, nothing more.
 *
 * Ledger posting pays out the row's `total` to its `bank_account` as they
 * stand at posting time, and approvals do not record the amount, so a
 * submitter who could edit the row could change either after approval. Every
 * change therefore goes through apps/api with the admin key, after an
 * ownership check.
 */
export function buildExpenseRowPermissions(userId: string): string[] {
  return [Permission.read(Role.user(userId))];
}
```

In `apps/api/src/app/api/expenses/draft/route.ts`:
1. Below the imports, add `type AdminDb = Awaited<ReturnType<typeof createAdminClient>>["db"];`.
2. Change the first parameter of `assertDraftOwnership` from `db: Awaited<ReturnType<typeof createAuthenticatedClient>>["db"],` to `db: AdminDb,` (body unchanged).
3. In `POST`, change `const { db, account } = await createAuthenticatedClient(req);` to `const { account } = await createAuthenticatedClient(req);` and the update call to `? await updateDraftExpense(payload.expenseId, user.$id, expenseBody)`.
4. Replace `updateDraftExpense` with:

```ts
/**
 * Expense rows are read-only to their submitter, so this ownership check is
 * the only thing between the caller and the row: the read and the write both
 * use the admin client.
 */
async function updateDraftExpense(
  expenseId: string,
  userId: string,
  expenseBody: ExpenseRowInput
) {
  const { db } = await createAdminClient();
  const ownershipError = await assertDraftOwnership(db, expenseId, userId);

  if (ownershipError) {
    return ownershipError;
  }

  return db.updateRow<DraftExpenseRow>(
    "app",
    "expense",
    expenseId,
    expenseBody
  );
}
```

In `apps/api/src/app/api/expenses/submit/route.ts`:
1. Below the imports, add `type AdminDb = Awaited<ReturnType<typeof createAdminClient>>["db"];`.
2. Change `checkDraftOwnership`'s first parameter type to `db: AdminDb,`.
3. Replace `saveDraftBeforeSubmission` with:

```ts
async function saveDraftBeforeSubmission(
  adminDb: AdminDb,
  expenseId: string | undefined,
  userId: string,
  expenseBody: ExpenseRowInput
): Promise<CreateExpenseData | ExpenseOwnershipError> {
  if (!expenseId) {
    return adminDb.createRow<CreateExpenseData>(
      "app",
      "expense",
      ID.unique(),
      expenseBody,
      buildExpenseRowPermissions(userId)
    );
  }

  // Expense rows are read-only to their submitter: ownership is checked here
  // and the write goes through the admin client.
  const ownership = await checkDraftOwnership(adminDb, expenseId, userId);

  if (!ownership.ok) {
    return ownership;
  }

  return adminDb.updateRow<CreateExpenseData>(
    "app",
    "expense",
    expenseId,
    expenseBody
  );
}
```

4. In `POST`, change the call to `saveDraftBeforeSubmission(adminDb, expenseData.expenseId, user.$id, expenseBody)`.
5. Change the legacy flow's final write from `await db.updateRow<ExpenseStatusUpdateRow>(` to `await adminDb.updateRow<ExpenseStatusUpdateRow>(` (same arguments). The session `db` stays for the profile and `fetchedExpense` reads.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/expense-payload.test.ts src/app/api/expenses/draft src/app/api/expenses/submit`
Expected: PASS.

Run: `cd apps/api && bun run check-types && cd ../.. && bunx biome lint apps/api/src/lib/expense-payload.ts apps/api/src/app/api/expenses`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/expense-payload.ts apps/api/src/lib/expense-payload.test.ts apps/api/src/app/api/expenses/draft apps/api/src/app/api/expenses/submit
git commit -m "Keep expense rows read-only for the student who submitted them

Ledger posting pays out the row's total to its bank account as they stand
at posting time, so a submitter who kept update rights could change either
after approval. Drafts are now edited and submitted through the admin client
after an ownership check.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Delete draft expenses through the API

**Files:**
- Modify: `apps/api/src/lib/expense-payload.ts`
- Modify: `apps/api/src/lib/expense-payload.test.ts`
- Modify: `apps/api/src/app/api/expenses/draft/route.ts`
- Modify: `apps/api/src/app/api/expenses/draft/route.test.ts`

**Interfaces:**
- Consumes: the admin-client draft route from Task 1.
- Produces: `DELETE /api/expenses/draft?expenseId=<id>` → `200 { success: true }`, `400`, `401`, `403`, `404`, `409`, `500` with `{ success: false, error }`. `receiptFileIds(attachments): string[]`.

- [ ] **Step 1: Write the failing tests**

Add to `apps/api/src/lib/expense-payload.test.ts` (extend the import with `receiptFileIds`):

```ts
  it("returns only bare storage file ids, once each", () => {
    expect(
      receiptFileIds([
        { url: "file-1" },
        { url: "file-1" },
        { url: "https://appwrite.biso.no/v1/storage/buckets/expenses/files/x/view" },
        { url: "" },
        { url: null },
        { url: " file-2 " },
      ])
    ).toEqual(["file-1", "file-2"]);
    expect(receiptFileIds(undefined)).toEqual([]);
  });
```

Add to `apps/api/src/app/api/expenses/draft/route.test.ts` — change the import line to `import { DELETE, POST } from "./route";` and append:

```ts
function deleteRequest(query: string) {
  return new Request(`https://api.example/api/expenses/draft${query}`, {
    method: "DELETE",
  }) as never;
}

describe("expense draft deletion", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    account.get.mockResolvedValue({ $id: "submitter-1" });
    adminDb.deleteRow.mockResolvedValue({});
    storage.deleteFile.mockResolvedValue({});
    vi.spyOn(console, "error").mockImplementation(() => undefined);
  });

  it("requires a signed-in caller", async () => {
    account.get.mockRejectedValue(new Error("no session"));

    const response = await DELETE(deleteRequest("?expenseId=expense-1"));

    expect(response.status).toBe(401);
    expect(adminDb.deleteRow).not.toHaveBeenCalled();
  });

  it("requires an expense id", async () => {
    const response = await DELETE(deleteRequest(""));

    expect(response.status).toBe(400);
  });

  it("answers 404 for an expense that does not exist", async () => {
    adminDb.getRow.mockRejectedValue(
      Object.assign(new Error("row_not_found"), { code: 404 })
    );

    const response = await DELETE(deleteRequest("?expenseId=expense-1"));

    expect(response.status).toBe(404);
  });

  it("refuses to delete someone else's expense", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      expenseAttachments: [],
      status: "draft",
      userId: "someone-else",
    });

    const response = await DELETE(deleteRequest("?expenseId=expense-1"));

    expect(response.status).toBe(403);
    expect(adminDb.deleteRow).not.toHaveBeenCalled();
  });

  it("refuses to delete an expense that has been submitted", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      expenseAttachments: [],
      status: "pending",
      userId: "submitter-1",
    });

    const response = await DELETE(deleteRequest("?expenseId=expense-1"));

    expect(response.status).toBe(409);
    expect(adminDb.deleteRow).not.toHaveBeenCalled();
  });

  it("deletes an owned draft and its receipt files, even if a file is already gone", async () => {
    adminDb.getRow.mockResolvedValue({
      $id: "expense-1",
      expenseAttachments: [{ url: "file-1" }, { url: "file-2" }],
      status: "draft",
      userId: "submitter-1",
    });
    storage.deleteFile
      .mockRejectedValueOnce(new Error("file not found"))
      .mockResolvedValueOnce({});

    const response = await DELETE(deleteRequest("?expenseId=expense-1"));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(adminDb.deleteRow).toHaveBeenCalledWith(
      "app",
      "expense",
      "expense-1"
    );
    expect(storage.deleteFile).toHaveBeenCalledWith("expenses", "file-1");
    expect(storage.deleteFile).toHaveBeenCalledWith("expenses", "file-2");
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/expense-payload.test.ts src/app/api/expenses/draft`
Expected: FAIL — `receiptFileIds` and `DELETE` are not exported.

- [ ] **Step 3: Implement**

Append to `apps/api/src/lib/expense-payload.ts`:

```ts
const APPWRITE_FILE_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;

/**
 * The `expenses` bucket file ids a draft's attachments point at.
 *
 * Attachment `url` holds a bare file id for receipts uploaded through the web
 * or `POST /api/expenses/attachments`. Anything else — a legacy full URL, an
 * empty value — is not a file this API may delete.
 */
export function receiptFileIds(
  attachments: ReadonlyArray<{ url?: string | null }> | null | undefined
): string[] {
  const ids = (attachments ?? [])
    .map((attachment) => attachment.url?.trim() ?? "")
    .filter((url) => APPWRITE_FILE_ID_RE.test(url));
  return [...new Set(ids)];
}
```

In `apps/api/src/app/api/expenses/draft/route.ts`, extend the `@/lib/expense-payload` import with `receiptFileIds`, and add before `OPTIONS`:

```ts
function isNotFound(error: unknown): boolean {
  return (error as { code?: number } | null)?.code === 404;
}

/**
 * Deletes one of the caller's own drafts, and the receipt files it
 * referenced. Submitted expenses are never deletable here: once a draft has
 * left draft, it belongs to the approval and posting flow.
 */
export async function DELETE(req: NextRequest) {
  const origin = req.headers.get("origin");
  const json = (data: unknown, status = 200) =>
    applyCorsHeaders(NextResponse.json(data, { status }), origin);

  const expenseId = new URL(req.url).searchParams.get("expenseId")?.trim();
  if (!expenseId) {
    return json({ success: false, error: "Missing expenseId" }, 400);
  }

  let userId: string;
  try {
    const { account } = await createAuthenticatedClient(req);
    userId = (await account.get()).$id;
  } catch {
    return json({ success: false, error: "Authentication required" }, 401);
  }

  try {
    const { db, storage } = await createAdminClient();
    const expense = await db
      .getRow<Expenses>("app", "expense", expenseId, [
        Query.select(["$id", "status", "userId", "expenseAttachments.*"]),
      ])
      .catch((error: unknown) => {
        if (isNotFound(error)) {
          return null;
        }
        throw error;
      });

    if (!expense) {
      return json({ success: false, error: "Expense not found" }, 404);
    }
    if (expense.userId !== userId) {
      return json({ success: false, error: "Unauthorized access" }, 403);
    }
    if (expense.status !== ExpensesStatus.DRAFT) {
      return json(
        { success: false, error: "Only draft expenses can be deleted" },
        409
      );
    }

    // `expenseAttachments` cascades, so the attachment rows go with the draft.
    await db.deleteRow("app", "expense", expenseId);

    await Promise.all(
      receiptFileIds(expense.expenseAttachments).map((fileId) =>
        storage.deleteFile("expenses", fileId).catch((error: unknown) => {
          console.error(
            `[expenses/draft] Could not delete receipt ${fileId}:`,
            error
          );
        })
      )
    );

    return json({ success: true });
  } catch (error) {
    console.error("Error deleting expense draft:", error);
    return json({ success: false, error: "Failed to delete draft" }, 500);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/expense-payload.test.ts src/app/api/expenses/draft && bun run check-types`
Expected: PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/expense-payload.ts apps/api/src/lib/expense-payload.test.ts apps/api/src/app/api/expenses/draft
git commit -m "Let students delete their own draft expenses through the API

Students have no delete grant on expense rows, so the app's direct delete
always failed. The route checks ownership and draft status, deletes the row
with the admin client, and removes the receipt files the draft referenced.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 3: Upload expense receipts through the API

**Files:**
- Create: `apps/api/src/lib/receipt-file.ts`
- Create: `apps/api/src/lib/receipt-file.test.ts`
- Create: `apps/api/src/app/api/expenses/attachments/route.ts`
- Create: `apps/api/src/app/api/expenses/attachments/route.test.ts`

**Interfaces:**
- Produces: `POST /api/expenses/attachments` (multipart field `file`, `Authorization: Bearer <JWT>`) → `201 { success: true, file: { fileId: string, name: string, mimeType: "application/pdf" | "image/png" | "image/jpeg", size: number, viewUrl: string } }`; errors `{ success: false, error }` with 401, 400, 403, 413, 415, 500. The Flutter app's `ExpenseApiClient.uploadExpenseAttachment` parses exactly these field names.

- [ ] **Step 1: Write the failing tests**

Create `apps/api/src/lib/receipt-file.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  receiptFileName,
  receiptViewUrl,
  sniffReceiptMimeType,
} from "./receipt-file";

const PDF = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0]);
const HEIC = new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

describe("sniffReceiptMimeType", () => {
  it("recognises the formats the ledger merge can embed", () => {
    expect(sniffReceiptMimeType(PDF)).toBe("application/pdf");
    expect(sniffReceiptMimeType(PNG)).toBe("image/png");
    expect(sniffReceiptMimeType(JPEG)).toBe("image/jpeg");
  });

  it("rejects anything else, whatever it claims to be", () => {
    expect(sniffReceiptMimeType(HEIC)).toBeNull();
    expect(sniffReceiptMimeType(new Uint8Array())).toBeNull();
  });
});

describe("receiptFileName", () => {
  it("gives the stored file an extension matching its real type", () => {
    expect(receiptFileName("IMG_0001.HEIC", "image/jpeg")).toBe("IMG_0001.jpg");
    expect(receiptFileName("kvittering.pdf", "application/pdf")).toBe("kvittering.pdf");
    expect(receiptFileName("", "image/png")).toBe("receipt.png");
    expect(receiptFileName("../../etc/passwd", "image/png")).toBe("passwd.png");
  });
});

describe("receiptViewUrl", () => {
  afterEach(() => vi.unstubAllEnvs());

  it("points at the expenses bucket on the configured Appwrite project", () => {
    vi.stubEnv("NEXT_PUBLIC_APPWRITE_ENDPOINT", "https://appwrite.example/v1/");
    vi.stubEnv("NEXT_PUBLIC_APPWRITE_PROJECT", "biso-test");

    expect(receiptViewUrl("file-1")).toBe(
      "https://appwrite.example/v1/storage/buckets/expenses/files/file-1/view?project=biso-test"
    );
  });
});
```

Create `apps/api/src/app/api/expenses/attachments/route.test.ts`:

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const account = vi.hoisted(() => ({ get: vi.fn() }));
const storage = vi.hoisted(() => ({ createFile: vi.fn() }));
const isFeatureEnabled = vi.hoisted(() => vi.fn());
const fromBuffer = vi.hoisted(() => vi.fn(() => ({ input: "file" })));

vi.mock("@/lib/auth", () => ({
  createAuthenticatedClient: vi.fn(async () => ({ account })),
}));
vi.mock("@repo/api/server", () => ({
  createAdminClient: vi.fn(async () => ({ storage })),
}));
vi.mock("@repo/shared/utils/feature-flags-server", () => ({
  isFeatureEnabled,
}));
vi.mock("@repo/api/file", () => ({ InputFile: { fromBuffer } }));

import { POST } from "./route";

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);
const HEIC = new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

function uploadRequest(file?: File) {
  const form = new FormData();
  if (file) {
    form.append("file", file);
  }
  return new Request("https://api.example/api/expenses/attachments", {
    body: form,
    method: "POST",
  }) as never;
}

describe("expense receipt upload", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("NEXT_PUBLIC_APPWRITE_ENDPOINT", "https://appwrite.example/v1");
    vi.stubEnv("NEXT_PUBLIC_APPWRITE_PROJECT", "biso-test");
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    isFeatureEnabled.mockResolvedValue(true);
    account.get.mockResolvedValue({ $id: "submitter-1" });
    storage.createFile.mockResolvedValue({
      $id: "file-1",
      name: "IMG_0001.png",
      sizeOriginal: 12,
    });
  });

  afterEach(() => vi.unstubAllEnvs());

  it("refuses uploads while reimbursements are switched off", async () => {
    isFeatureEnabled.mockResolvedValue(false);

    const response = await POST(uploadRequest(new File([PNG], "a.png")));

    expect(response.status).toBe(403);
    expect(isFeatureEnabled).toHaveBeenCalledWith("expenses_module");
    expect(storage.createFile).not.toHaveBeenCalled();
  });

  it("requires a signed-in caller", async () => {
    account.get.mockRejectedValue(new Error("no session"));

    const response = await POST(uploadRequest(new File([PNG], "a.png")));

    expect(response.status).toBe(401);
  });

  it("requires a file", async () => {
    const response = await POST(uploadRequest());

    expect(response.status).toBe(400);
  });

  it("refuses files over the bucket's 10 MB limit", async () => {
    const big = new File([new Uint8Array(10 * 1024 * 1024 + 1)], "big.pdf");

    const response = await POST(uploadRequest(big));

    expect(response.status).toBe(413);
    expect(storage.createFile).not.toHaveBeenCalled();
  });

  it("refuses a HEIC photo even when it is labelled as a JPEG", async () => {
    const response = await POST(
      uploadRequest(new File([HEIC], "IMG_0001.jpg", { type: "image/jpeg" }))
    );

    expect(response.status).toBe(415);
    expect(storage.createFile).not.toHaveBeenCalled();
  });

  it("stores a receipt readable by its uploader only and returns its id", async () => {
    const response = await POST(
      uploadRequest(new File([PNG], "IMG_0001.HEIC", { type: "image/heic" }))
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({
      success: true,
      file: {
        fileId: "file-1",
        mimeType: "image/png",
        name: "IMG_0001.png",
        size: 12,
        viewUrl:
          "https://appwrite.example/v1/storage/buckets/expenses/files/file-1/view?project=biso-test",
      },
    });
    expect(fromBuffer).toHaveBeenCalledWith(expect.any(Buffer), "IMG_0001.png");
    expect(storage.createFile).toHaveBeenCalledWith(
      "expenses",
      expect.any(String),
      { input: "file" },
      ['read("user:submitter-1")']
    );
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/receipt-file.test.ts src/app/api/expenses/attachments`
Expected: FAIL — modules not found.

- [ ] **Step 3: Implement**

Create `apps/api/src/lib/receipt-file.ts`:

```ts
import type { AllowedReceiptMimeType } from "@repo/shared/utils/expense-attachments";

/** The `expenses` bucket rejects anything larger. */
export const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

const PDF_SIGNATURE = [0x25, 0x50, 0x44, 0x46];
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG_SIGNATURE = [0xff, 0xd8, 0xff];

const EXTENSION_BY_TYPE: Record<AllowedReceiptMimeType, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
};

const TRAILING_SLASHES_RE = /\/+$/;
const PATH_PREFIX_RE = /^.*[\\/]/;
const EXTENSION_RE = /\.[^.]*$/;
const UNSAFE_NAME_CHARS_RE = /[^\p{L}\p{N} ._-]/gu;

function startsWith(bytes: Uint8Array, signature: number[]): boolean {
  return (
    bytes.length >= signature.length &&
    signature.every((byte, index) => bytes[index] === byte)
  );
}

/**
 * A receipt's real type, read from its first bytes.
 *
 * The declared content type is not trusted: the ledger merge can only embed
 * PDF, PNG and JPEG, and a mislabelled file (a HEIC photo named `.jpg`) would
 * only fail at posting time, long after the student submitted it.
 */
export function sniffReceiptMimeType(
  bytes: Uint8Array
): AllowedReceiptMimeType | null {
  if (startsWith(bytes, PDF_SIGNATURE)) {
    return "application/pdf";
  }
  if (startsWith(bytes, PNG_SIGNATURE)) {
    return "image/png";
  }
  if (startsWith(bytes, JPEG_SIGNATURE)) {
    return "image/jpeg";
  }
  return null;
}

/**
 * The stored file name: the original base name, stripped of any path and of
 * characters that do not belong in a file name, with the extension of the
 * sniffed type — the bucket's extension allow-list checks the name.
 */
export function receiptFileName(
  originalName: string | null | undefined,
  mimeType: AllowedReceiptMimeType
): string {
  const base = (originalName ?? "")
    .replace(PATH_PREFIX_RE, "")
    .replace(EXTENSION_RE, "")
    .replace(UNSAFE_NAME_CHARS_RE, "")
    .trim()
    .slice(0, 80);
  return `${base || "receipt"}.${EXTENSION_BY_TYPE[mimeType]}`;
}

/** Same endpoint and project resolution as `@repo/api/server`. */
export function receiptViewUrl(fileId: string): string {
  const endpoint = (
    process.env.NEXT_PUBLIC_APPWRITE_ENDPOINT ||
    process.env.APPWRITE_ENDPOINT ||
    "https://appwrite.biso.no/v1"
  ).replace(TRAILING_SLASHES_RE, "");
  const project =
    process.env.NEXT_PUBLIC_APPWRITE_PROJECT ||
    process.env.APPWRITE_PROJECT_ID ||
    "biso";
  return `${endpoint}/storage/buckets/expenses/files/${encodeURIComponent(fileId)}/view?project=${encodeURIComponent(project)}`;
}
```

Create `apps/api/src/app/api/expenses/attachments/route.ts`:

```ts
import { ID, Permission, Role } from "@repo/api";
import { InputFile } from "@repo/api/file";
import { createAdminClient } from "@repo/api/server";
import { ALLOWED_RECEIPT_LABEL } from "@repo/shared/utils/expense-attachments";
import { isFeatureEnabled } from "@repo/shared/utils/feature-flags-server";
import { type NextRequest, NextResponse } from "next/server";
import { createAuthenticatedClient } from "@/lib/auth";
import { applyCorsHeaders, corsPreflightResponse } from "@/lib/cors";
import {
  MAX_RECEIPT_BYTES,
  receiptFileName,
  receiptViewUrl,
  sniffReceiptMimeType,
} from "@/lib/receipt-file";

export const runtime = "nodejs";

const EXPENSES_BUCKET_ID = "expenses";

/**
 * Stores one receipt for a reimbursement.
 *
 * The `expenses` bucket has no user create grant, so a client cannot upload
 * there directly — the web uploads through a server action with the admin
 * key, and this route does the same for the app. The file is readable by its
 * uploader only; reviewers and ledger posting read it with the admin key.
 */
export async function POST(req: NextRequest) {
  const origin = req.headers.get("origin");
  const json = (data: unknown, status = 200) =>
    applyCorsHeaders(NextResponse.json(data, { status }), origin);

  if (!(await isFeatureEnabled("expenses_module"))) {
    return json(
      { success: false, error: "Reimbursements are currently unavailable" },
      403
    );
  }

  let userId: string;
  try {
    const { account } = await createAuthenticatedClient(req);
    userId = (await account.get()).$id;
  } catch {
    return json({ success: false, error: "Authentication required" }, 401);
  }

  const form = await req.formData().catch(() => null);
  const file = form?.get("file");
  if (!(file instanceof File)) {
    return json({ success: false, error: "No file provided" }, 400);
  }
  if (file.size > MAX_RECEIPT_BYTES) {
    return json({ success: false, error: "File size exceeds 10MB limit" }, 413);
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const mimeType = sniffReceiptMimeType(bytes);
  if (!mimeType) {
    return json(
      {
        success: false,
        error: `Unsupported file type. Please upload a ${ALLOWED_RECEIPT_LABEL} file.`,
      },
      415
    );
  }

  try {
    const { storage } = await createAdminClient();
    const name = receiptFileName(file.name, mimeType);
    const created = await storage.createFile(
      EXPENSES_BUCKET_ID,
      ID.unique(),
      InputFile.fromBuffer(Buffer.from(bytes), name),
      [Permission.read(Role.user(userId))]
    );

    return json(
      {
        success: true,
        file: {
          fileId: created.$id,
          mimeType,
          name: created.name,
          size: created.sizeOriginal,
          viewUrl: receiptViewUrl(created.$id),
        },
      },
      201
    );
  } catch (error) {
    console.error("[expenses/attachments] Upload failed:", error);
    return json({ success: false, error: "Failed to upload receipt" }, 500);
  }
}

export function OPTIONS(req: NextRequest) {
  return corsPreflightResponse(req.headers.get("origin"));
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/receipt-file.test.ts src/app/api/expenses/attachments && bun run check-types`
Expected: PASS, no type errors. If `bunx biome lint` flags the long URL template in `receiptViewUrl`, keep the template and wrap it as Biome's formatter suggests (`bunx biome format --write apps/api/src/lib/receipt-file.ts`).

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/receipt-file.ts apps/api/src/lib/receipt-file.test.ts apps/api/src/app/api/expenses/attachments
git commit -m "Accept expense receipt uploads for the app through the API

The expenses bucket has no user create grant, so the app's direct uploads
always failed. The route sniffs the file's real type, stores it with the
admin key and makes it readable by the uploader only.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Report the live expenses switch in the app config

**Files:**
- Modify: `apps/api/src/app/api/config/route.ts`
- Create: `apps/api/src/app/api/config/route.test.ts`

**Interfaces:**
- Produces: `GET /api/config` → `{ content: {...}, features: { departures: boolean, expenses: boolean, marketplace: boolean } }` where `features.expenses` equals the `expenses_module` flag. The app's `AppConfig.expensesEnabled` reads `features.expenses`.

- [ ] **Step 1: Write the failing test**

Create `apps/api/src/app/api/config/route.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const isFeatureEnabled = vi.hoisted(() => vi.fn());

vi.mock("@repo/shared/utils/feature-flags-server", () => ({
  isFeatureEnabled,
}));

import { GET } from "./route";

describe("app config", () => {
  beforeEach(() => {
    isFeatureEnabled.mockReset();
  });

  it("reports reimbursements as available when the admin switch is on", async () => {
    isFeatureEnabled.mockResolvedValue(true);

    const response = await GET();
    const body = await response.json();

    expect(isFeatureEnabled).toHaveBeenCalledWith("expenses_module");
    expect(body.features).toEqual({
      departures: true,
      expenses: true,
      marketplace: true,
    });
    expect(response.headers.get("cache-control")).toBe(
      "public, max-age=0, s-maxage=15"
    );
  });

  it("reports reimbursements as unavailable when the admin switch is off", async () => {
    isFeatureEnabled.mockResolvedValue(false);

    const body = await (await GET()).json();

    expect(body.features.expenses).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/config`
Expected: FAIL — `features.expenses` is the static `false` and no cache header is set.

- [ ] **Step 3: Implement**

Replace `apps/api/src/app/api/config/route.ts` with:

```ts
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { isFeatureEnabled } from "@repo/shared/utils/feature-flags-server";
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface AppConfigFile {
  content: Record<string, string>;
  features: Record<string, boolean>;
}

const FALLBACK_CONFIG: AppConfigFile = {
  content: {
    events_source: "wordpress",
    jobs_source: "wordpress",
    products_source: "woocommerce",
  },
  features: {
    departures: true,
    expenses: false,
    marketplace: false,
  },
};

function readStaticConfig(): AppConfigFile {
  try {
    const configPath = join(process.cwd(), "config", "app-config.json");
    return JSON.parse(readFileSync(configPath, "utf-8")) as AppConfigFile;
  } catch {
    return FALLBACK_CONFIG;
  }
}

/**
 * The student app's remote config.
 *
 * `features.expenses` follows the admin's `expenses_module` switch — the same
 * flag the expense routes enforce — so the app offers reimbursements exactly
 * when the server will accept them.
 */
export async function GET() {
  const config = readStaticConfig();
  const expenses = await isFeatureEnabled("expenses_module");

  return NextResponse.json(
    { ...config, features: { ...config.features, expenses } },
    { headers: { "Cache-Control": "public, max-age=0, s-maxage=15" } }
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/config && bun run check-types`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/app/api/config
git commit -m "Report the live reimbursements switch in the app config

The app hid expenses based on a hard-coded flag that nothing in the admin
could change. The config now carries the expenses_module flag the expense
routes already enforce.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 5: Enforce the profile allow-list on the server

**Files:**
- Create: `packages/shared/utils/profile-fields.ts`
- Create: `packages/shared/utils/profile-fields.test.ts`
- Delete: `apps/web/src/lib/actions/profile-permissions.ts`
- Modify: `apps/web/src/lib/actions/user.ts`
- Modify: `apps/web/src/lib/actions/user.test.ts`
- Modify: `apps/web/src/lib/actions/bi-identity.ts` (import and comments only)
- Modify: `packages/api/appwrite.config.json`
- Modify: `packages/api/appwrite-config-permissions.test.ts`

**Interfaces:**
- Produces (in `@repo/shared/utils/profile-fields`):
  - `SELF_SERVICE_PROFILE_FIELDS: readonly ["name","phone","address","city","zip","bank_account","swift","avatar","bio","is_public","campus_id","departments"]`
  - `pickSelfServiceProfileFields(input: Partial<Users>): Partial<Pick<Users, SelfServiceProfileField>>`
  - `selfServiceProfileSchema` (zod object; unknown keys are stripped) and `type SelfServiceProfileInput`
  - `buildProfileRowPermissions(userId: string): string[]` → `['read("user:<id>")']`

- [ ] **Step 1: Write the failing tests**

Create `packages/shared/utils/profile-fields.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  buildProfileRowPermissions,
  pickSelfServiceProfileFields,
  selfServiceProfileSchema,
} from "./profile-fields";

describe("profile self-service fields", () => {
  it("keeps editable fields and drops identity and role columns", () => {
    expect(
      pickSelfServiceProfileFields({
        bank_account: "12345678903",
        bi_employee_id: "1015882",
        campus_id: "1",
        name: "Ada",
        roles: ["globaladmin"],
        student_id: "s1715738",
      } as never)
    ).toEqual({ bank_account: "12345678903", campus_id: "1", name: "Ada" });
  });

  it("strips unknown keys and enforces the table's column lengths", () => {
    const parsed = selfServiceProfileSchema.safeParse({
      departments: ["dept-1"],
      name: "Ada",
      student_id: "s1715738",
    });
    expect(parsed.success).toBe(true);
    expect(parsed.success && parsed.data).toEqual({
      departments: ["dept-1"],
      name: "Ada",
    });

    expect(
      selfServiceProfileSchema.safeParse({ name: "x".repeat(31) }).success
    ).toBe(false);
    expect(selfServiceProfileSchema.safeParse({ zip: 1234 }).success).toBe(
      false
    );
  });

  it("makes a profile row readable by its owner only", () => {
    expect(buildProfileRowPermissions("user-1")).toEqual([
      'read("user:user-1")',
    ]);
  });
});
```

In `apps/web/src/lib/actions/user.test.ts`:
- add `updateName: vi.fn(),` to the hoisted `account` object and `createRow: vi.fn(),` to the hoisted `adminDb` object;
- change the import to `import { removeIdentity, updateProfile } from "./user";`;
- append:

```ts
describe("updateProfile", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    account.get.mockResolvedValue({ $id: "user-1" });
    account.updateName.mockResolvedValue({});
    adminDb.updateRow.mockResolvedValue({ $id: "user-1" });
    adminDb.createRow.mockResolvedValue({ $id: "user-1" });
    vi.spyOn(console, "error").mockImplementation(() => undefined);
  });

  it("writes only self-service fields to an existing row, through the admin client", async () => {
    adminDb.getRow.mockResolvedValue({ $id: "user-1" });

    await updateProfile({
      bi_employee_id: "1015882",
      name: "Ada",
      phone: "12345678",
      student_id: "s1715738",
    } as never);

    expect(adminDb.updateRow).toHaveBeenCalledWith("app", "user", "user-1", {
      name: "Ada",
      phone: "12345678",
    });
    expect(account.updateName).toHaveBeenCalledWith("Ada");
  });

  it("creates a missing row readable by its owner only", async () => {
    adminDb.getRow.mockRejectedValue(
      Object.assign(new Error("not found"), { code: 404 })
    );

    await updateProfile({ name: "Ada", student_id: "s1715738" } as never);

    expect(adminDb.createRow).toHaveBeenCalledWith(
      "app",
      "user",
      "user-1",
      { name: "Ada" },
      ['read("user:user-1")']
    );
  });

  it("does not create a row when the lookup fails for another reason", async () => {
    adminDb.getRow.mockRejectedValue(
      Object.assign(new Error("timeout"), { code: 500 })
    );

    await expect(updateProfile({ name: "Ada" } as never)).resolves.toBeNull();
    expect(adminDb.createRow).not.toHaveBeenCalled();
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });
});
```

Append to `packages/api/appwrite-config-permissions.test.ts`:

```ts
describe("profile table permissions", () => {
  test("signed-in users cannot create profile rows themselves", () => {
    const table = loadAppwriteConfig().tables.find(
      (candidate) => candidate.databaseId === "app" && candidate.$id === "user"
    );

    expect(table).toBeDefined();
    expect(table?.$permissions).not.toContain('create("users")');
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shared && bunx vitest run utils/profile-fields.test.ts`
Expected: FAIL — module not found.
Run: `cd apps/web && bunx vitest run src/lib/actions/user.test.ts`
Expected: FAIL — `updateProfile` writes through the session client.
Run: `cd packages/api && bunx vitest run appwrite-config-permissions.test.ts`
Expected: FAIL — the `user` table still grants `create("users")`.

- [ ] **Step 3: Implement**

Create `packages/shared/utils/profile-fields.ts`:

```ts
import { Permission, Role } from "@repo/api";
import type { Users } from "@repo/api/types/appwrite";
import { z } from "zod";

/**
 * Profile columns a signed-in person may set on their own `user` row.
 *
 * Everything else on the row — `student_id`, the `bi_*` link columns,
 * `roles`, `membership_ids` — is written only by server code after its own
 * checks. Appwrite has no column permissions, so profile rows are read-only
 * to their owner (`buildProfileRowPermissions`) and this list is the whole of
 * self-service: the web's `updateProfile` and the API's `PUT /api/profile`
 * both write through it with the admin client.
 */
export const SELF_SERVICE_PROFILE_FIELDS = [
  "name",
  "phone",
  "address",
  "city",
  "zip",
  "bank_account",
  "swift",
  "avatar",
  "bio",
  "is_public",
  "campus_id",
  "departments",
] as const satisfies readonly (keyof Users)[];

export type SelfServiceProfileField =
  (typeof SELF_SERVICE_PROFILE_FIELDS)[number];

export function pickSelfServiceProfileFields(
  input: Partial<Users>
): Partial<Pick<Users, SelfServiceProfileField>> {
  const result: Partial<Pick<Users, SelfServiceProfileField>> = {};
  for (const key of SELF_SERVICE_PROFILE_FIELDS) {
    if (key in input) {
      // The conditional cast keeps the narrow per-key type from Users.
      result[key] = input[key] as never;
    }
  }
  return result;
}

const optionalText = (maxLength: number) =>
  z.string().trim().max(maxLength).nullable().optional();

/**
 * Request-body validation for self-service profile writes. Lengths match the
 * `user` table's columns; unknown keys (including identity columns) are
 * stripped rather than rejected, so an older client sending extra fields
 * still saves what it may save.
 */
export const selfServiceProfileSchema = z.object({
  address: optionalText(100),
  avatar: optionalText(200),
  bank_account: optionalText(20),
  bio: optionalText(500),
  campus_id: optionalText(5),
  city: optionalText(50),
  departments: z.array(z.string().trim().min(1).max(36)).max(50).optional(),
  is_public: z.boolean().optional(),
  name: z.string().trim().min(1).max(30).optional(),
  phone: optionalText(20),
  swift: optionalText(15),
  zip: optionalText(20),
});

export type SelfServiceProfileInput = z.infer<typeof selfServiceProfileSchema>;

/** A `user` profile row is readable by its owner and writable by no client. */
export function buildProfileRowPermissions(userId: string): string[] {
  return [Permission.read(Role.user(userId))];
}
```

Delete `apps/web/src/lib/actions/profile-permissions.ts` (`git rm`). Run `rg -n "profile-permissions" apps packages` and replace every import with `import { buildProfileRowPermissions } from "@repo/shared/utils/profile-fields";` (expected: `apps/web/src/lib/actions/user.ts` and `apps/web/src/lib/actions/bi-identity.ts`).

In `apps/web/src/lib/actions/user.ts`:
1. Remove the local `PROFILE_WRITABLE_FIELDS` constant, the `WritableProfileField` type and the `pickWritableProfileFields` function.
2. Add `import { pickSelfServiceProfileFields } from "@repo/shared/utils/profile-fields";` next to the `buildProfileRowPermissions` import from the same module (one import statement).
3. Replace `updateProfile` with:

```ts
function isRowNotFound(error: unknown): boolean {
  return (error as { code?: number } | null)?.code === 404;
}

/**
 * Saves the signed-in person's own profile.
 *
 * Profile rows are read-only to their owner, so the self-service allow-list
 * is what stands between this request and the row; the write itself uses the
 * admin client. A missing row is created here, because onboarding creates the
 * profile lazily at its last step.
 */
export async function updateProfile(profile: Partial<Users>) {
  try {
    const { account } = await createSessionClient();
    const user = await account.get();
    const writable = pickSelfServiceProfileFields(profile);
    const { db: adminDb } = await createAdminClient();

    const existing = await adminDb
      .getRow<Users>("app", "user", user.$id)
      .catch((error: unknown) => {
        if (isRowNotFound(error)) {
          return null;
        }
        throw error;
      });

    if (!existing) {
      // createRow's typed signature wants the full row; we're seeding a
      // partial profile that the user will fill in over time. Omit the
      // generic so the Appwrite SDK accepts the partial payload.
      return await adminDb.createRow(
        "app",
        "user",
        user.$id,
        writable,
        buildProfileRowPermissions(user.$id)
      );
    }

    if (typeof writable.name === "string" && writable.name.length > 0) {
      await account.updateName(writable.name);
    }
    return await adminDb.updateRow<Users>("app", "user", user.$id, writable);
  } catch (error) {
    console.error("Error in updateProfile:", error);
    return null;
  }
}
```

4. Replace every remaining mention of `PROFILE_WRITABLE_FIELDS` in comments in `user.ts` and `bi-identity.ts` with `SELF_SERVICE_PROFILE_FIELDS` (`rg -n PROFILE_WRITABLE_FIELDS apps/web` must print nothing afterwards).

In `packages/api/appwrite.config.json`, edit the `user` table's permissions exactly:

```
                "delete(\"team:sg-app-dept-operationsunit\")",
                "create(\"users\")"
            ],
            "databaseId": "app",
            "name": "Users",
```

becomes

```
                "delete(\"team:sg-app-dept-operationsunit\")"
            ],
            "databaseId": "app",
            "name": "Users",
```

(This keeps the repo config in step with the owner's console change, so a later `appwrite push` cannot re-grant it. Do not push it.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shared && bunx vitest run utils/profile-fields.test.ts && bun run check-types`
Run: `cd apps/web && bunx vitest run src/lib/actions && bun run check-types`
Run: `cd packages/api && bunx vitest run`
Expected: all PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add packages/shared/utils/profile-fields.ts packages/shared/utils/profile-fields.test.ts apps/web/src/lib/actions packages/api/appwrite.config.json packages/api/appwrite-config-permissions.test.ts
git commit -m "Enforce the profile allow-list on the server instead of by row grants

Appwrite has no column permissions, so a student with update rights on their
own profile could write any student_id and claim that student's membership.
Profile rows are now read-only to their owner, and self-service edits go
through a shared allow-list with the admin client.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Save app profile edits through `PUT /api/profile`

**Files:**
- Create: `apps/api/src/app/api/profile/route.ts`
- Create: `apps/api/src/app/api/profile/route.test.ts`

**Interfaces:**
- Consumes: `selfServiceProfileSchema`, `buildProfileRowPermissions` from Task 5.
- Produces: `PUT /api/profile` with `Authorization: Bearer <JWT>` and a JSON body of self-service fields → `200 { success: true, profile: <user row> }`; `401 { success: false, error: "Authentication required" }`; `400 { success: false, error: "Invalid profile", issues: [{ path, message }] }`; `500 { success: false, error: "Failed to save profile" }`. The Flutter `ProfileApiClient.upsert` calls this.

- [ ] **Step 1: Write the failing test**

Create `apps/api/src/app/api/profile/route.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const account = vi.hoisted(() => ({ get: vi.fn() }));
const adminDb = vi.hoisted(() => ({
  createRow: vi.fn(),
  getRow: vi.fn(),
  updateRow: vi.fn(),
}));
const users = vi.hoisted(() => ({ updateName: vi.fn() }));

vi.mock("@/lib/auth", () => ({
  createAuthenticatedClient: vi.fn(async () => ({ account })),
}));
vi.mock("@repo/api/server", () => ({
  createAdminClient: vi.fn(async () => ({ db: adminDb, users })),
}));

import { PUT } from "./route";

function profileRequest(body: unknown, authorization = "Bearer jwt") {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) {
    headers.set("authorization", authorization);
  }
  return new Request("https://api.example/api/profile", {
    body: JSON.stringify(body),
    headers,
    method: "PUT",
  }) as never;
}

describe("PUT /api/profile", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    account.get.mockResolvedValue({
      $id: "user-1",
      email: "ada@example.com",
      name: "Ada",
    });
    adminDb.updateRow.mockResolvedValue({ $id: "user-1", name: "Ada L" });
    adminDb.createRow.mockResolvedValue({ $id: "user-1", name: "Ada" });
    users.updateName.mockResolvedValue({});
  });

  it("requires a bearer token", async () => {
    const response = await PUT(profileRequest({ name: "Ada" }, ""));

    expect(response.status).toBe(401);
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });

  it("rejects values the profile columns cannot hold", async () => {
    const response = await PUT(profileRequest({ name: "x".repeat(31) }));

    expect(response.status).toBe(400);
    expect(adminDb.updateRow).not.toHaveBeenCalled();
  });

  it("updates an existing row with self-service fields only and mirrors a changed name", async () => {
    adminDb.getRow.mockResolvedValue({ $id: "user-1" });

    const response = await PUT(
      profileRequest({
        bi_employee_id: "1015882",
        is_public: true,
        name: "Ada L",
        student_id: "s1715738",
      })
    );

    expect(response.status).toBe(200);
    expect(adminDb.updateRow).toHaveBeenCalledWith("app", "user", "user-1", {
      is_public: true,
      name: "Ada L",
    });
    expect(users.updateName).toHaveBeenCalledWith({
      name: "Ada L",
      userId: "user-1",
    });
  });

  it("creates a missing row with the account email, readable by its owner only", async () => {
    adminDb.getRow.mockRejectedValue(
      Object.assign(new Error("not found"), { code: 404 })
    );

    const response = await PUT(profileRequest({ campus_id: "1", name: "Ada" }));

    expect(response.status).toBe(200);
    expect(adminDb.createRow).toHaveBeenCalledWith(
      "app",
      "user",
      "user-1",
      { campus_id: "1", email: "ada@example.com", name: "Ada" },
      ['read("user:user-1")']
    );
    expect(users.updateName).not.toHaveBeenCalled();
  });

  it("answers 500 without creating anything when the lookup fails", async () => {
    adminDb.getRow.mockRejectedValue(
      Object.assign(new Error("timeout"), { code: 500 })
    );

    const response = await PUT(profileRequest({ name: "Ada" }));

    expect(response.status).toBe(500);
    expect(adminDb.createRow).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/profile`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `apps/api/src/app/api/profile/route.ts`:

```ts
import { createAdminClient } from "@repo/api/server";
import {
  buildProfileRowPermissions,
  selfServiceProfileSchema,
} from "@repo/shared/utils/profile-fields";
import { type NextRequest, NextResponse } from "next/server";
import { createAuthenticatedClient } from "@/lib/auth";
import { applyCorsHeaders, corsPreflightResponse } from "@/lib/cors";

function isRowNotFound(error: unknown): boolean {
  return (error as { code?: number } | null)?.code === 404;
}

/**
 * Saves the caller's own profile from the app.
 *
 * Profile rows are read-only to their owner, so this is the app's only way to
 * change one. The body is cut down to the self-service allow-list — identity
 * columns such as `student_id` are dropped, never written — and the row is
 * updated, or created when absent, with the admin client.
 */
export async function PUT(req: NextRequest) {
  const origin = req.headers.get("origin");
  const json = (data: unknown, status = 200) =>
    applyCorsHeaders(NextResponse.json(data, { status }), origin);

  if (!req.headers.get("authorization")?.startsWith("Bearer ")) {
    return json({ success: false, error: "Authentication required" }, 401);
  }

  let user: { $id: string; email: string; name: string };
  try {
    const { account } = await createAuthenticatedClient(req);
    user = await account.get();
  } catch {
    return json({ success: false, error: "Authentication required" }, 401);
  }

  const parsed = selfServiceProfileSchema.safeParse(
    await req.json().catch(() => null)
  );
  if (!parsed.success) {
    return json(
      {
        success: false,
        error: "Invalid profile",
        issues: parsed.error.issues.map((issue) => ({
          message: issue.message,
          path: issue.path.join("."),
        })),
      },
      400
    );
  }
  const fields = parsed.data;

  try {
    const { db, users } = await createAdminClient();
    const existing = await db
      .getRow("app", "user", user.$id)
      .catch((error: unknown) => {
        if (isRowNotFound(error)) {
          return null;
        }
        throw error;
      });

    const profile = existing
      ? await db.updateRow("app", "user", user.$id, fields)
      : await db.createRow(
          "app",
          "user",
          user.$id,
          { ...fields, email: user.email },
          buildProfileRowPermissions(user.$id)
        );

    if (existing && fields.name && fields.name !== user.name) {
      await users
        .updateName({ name: fields.name, userId: user.$id })
        .catch((error: unknown) => {
          console.error("[profile] Could not mirror the account name:", error);
        });
    }

    return json({ success: true, profile });
  } catch (error) {
    console.error("[profile] Saving the profile failed:", error);
    return json({ success: false, error: "Failed to save profile" }, 500);
  }
}

export function OPTIONS(req: NextRequest) {
  return corsPreflightResponse(req.headers.get("origin"));
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/app/api/profile && bun run check-types`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/app/api/profile
git commit -m "Add a profile route the app saves through

Profile rows are read-only to their owner, so the app needs a server route
for edits. It applies the shared self-service allow-list and writes with the
admin client, creating the row on first save.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 7: Stop counting expired memberships

**Files:**
- Modify: `packages/shared/utils/membership-status.ts`
- Create: `packages/shared/utils/membership-status.test.ts`

**Interfaces:**
- Produces (in `@repo/shared/utils/membership-status`):
  - `osloToday(now?: Date): string` — `YYYY-MM-DD` in `Europe/Oslo`
  - `isMembershipRowActive(expiryDate: string | null | undefined, now?: Date): boolean`
  - `MembershipStatus.expiredMemberships?: MembershipInfo[]` (always set by `computeMembershipStatus`, newest expiry first)
  - `computeMembershipStatus(numericId: number, now?: Date)`; `reason: "expired"` when every matched row has expired
  - `emptyMembershipStatus(reason)` now also returns `expiredMemberships: []`

- [ ] **Step 1: Write the failing test**

Create `packages/shared/utils/membership-status.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const getCustomerCategories = vi.hoisted(() => vi.fn());
const listRows = vi.hoisted(() => vi.fn());

vi.mock("@repo/connectors/24sevenoffice", () => ({ getCustomerCategories }));
vi.mock("@repo/api/server", () => ({
  createAdminClient: vi.fn(async () => ({ db: { listRows } })),
}));
vi.mock("@repo/api/client", () => ({
  Query: {
    equal: (key: string, value: unknown) => `equal(${key},${String(value)})`,
    limit: (count: number) => `limit(${count})`,
  },
}));

import {
  computeMembershipStatus,
  isMembershipRowActive,
  osloToday,
} from "./membership-status";

function row(id: string, category: string, expiryDate: string) {
  return {
    $id: id,
    category,
    expiryDate,
    name: `BISO Membership ${id}`,
    startDate: "2026-01-01",
  };
}

describe("isMembershipRowActive", () => {
  it("keeps a membership valid through the whole of its expiry day in Oslo", () => {
    // 23:30 in Oslo (UTC+2 in summer) on the expiry day.
    expect(
      isMembershipRowActive("2026-06-30", new Date("2026-06-30T21:30:00Z"))
    ).toBe(true);
    // 00:30 in Oslo the next day, while it is still 30 June in UTC.
    expect(
      isMembershipRowActive("2026-06-30", new Date("2026-06-30T22:30:00Z"))
    ).toBe(false);
  });

  it("reads a date-time expiry by its date part", () => {
    expect(
      isMembershipRowActive(
        "2026-12-31T00:00:00.000+00:00",
        new Date("2026-12-31T12:00:00Z")
      )
    ).toBe(true);
  });

  it("treats an unreadable expiry as expired", () => {
    expect(isMembershipRowActive("", new Date())).toBe(false);
    expect(isMembershipRowActive("fall 2026", new Date())).toBe(false);
    expect(isMembershipRowActive(null, new Date())).toBe(false);
  });

  it("formats today's Oslo date as YYYY-MM-DD", () => {
    expect(osloToday(new Date("2026-01-01T23:30:00Z"))).toBe("2026-01-02");
  });
});

describe("computeMembershipStatus", () => {
  const now = new Date("2026-09-15T10:00:00Z");

  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
  });

  it("counts only unexpired rows whose category the customer holds", async () => {
    getCustomerCategories.mockResolvedValue([113_176, 113_178, 999]);
    listRows.mockResolvedValue({
      rows: [
        row("spring-2026", "113176", "2026-06-30"),
        row("year-2026", "113178", "2027-06-30"),
        row("not-held", "113177", "2029-06-30"),
      ],
      total: 3,
    });

    const status = await computeMembershipStatus(1_715_738, now);

    expect(getCustomerCategories).toHaveBeenCalledWith(1_715_738);
    expect(listRows).toHaveBeenCalledWith("app", "memberships", [
      "equal(status,true)",
      "limit(200)",
    ]);
    expect(status.isMember).toBe(true);
    expect(status.memberships.map((m) => m.id)).toEqual(["year-2026"]);
    expect(status.expiredMemberships?.map((m) => m.id)).toEqual([
      "spring-2026",
    ]);
    expect(status.reason).toBeUndefined();
  });

  it("reports an expired membership, newest expiry first", async () => {
    getCustomerCategories.mockResolvedValue([1, 2]);
    listRows.mockResolvedValue({
      rows: [row("older", "1", "2025-12-31"), row("newer", "2", "2026-06-30")],
      total: 2,
    });

    const status = await computeMembershipStatus(1_715_738, now);

    expect(status.isMember).toBe(false);
    expect(status.reason).toBe("expired");
    expect(status.memberships).toEqual([]);
    expect(status.expiredMemberships?.map((m) => m.id)).toEqual([
      "newer",
      "older",
    ]);
  });

  it("does not count a matched row with an unreadable expiry", async () => {
    getCustomerCategories.mockResolvedValue([1]);
    listRows.mockResolvedValue({ rows: [row("bad", "1", "soon")], total: 1 });

    const status = await computeMembershipStatus(1_715_738, now);

    expect(status.isMember).toBe(false);
    expect(status.expiredMemberships?.map((m) => m.id)).toEqual(["bad"]);
  });

  it("still reports a customer with no categories as not a member", async () => {
    getCustomerCategories.mockResolvedValue([]);

    const status = await computeMembershipStatus(1_715_738, now);

    expect(status).toMatchObject({
      expiredMemberships: [],
      isMember: false,
      reason: "no_categories",
    });
    expect(listRows).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/shared && bunx vitest run utils/membership-status.test.ts`
Expected: FAIL — `isMembershipRowActive` and `osloToday` are not exported, and expired rows still count.

- [ ] **Step 3: Implement**

In `packages/shared/utils/membership-status.ts`:

1. Replace the `MembershipStatus` interface with:

```ts
export interface MembershipStatus {
  checkedAt: number;
  /**
   * Matched memberships whose expiry has passed, newest expiry first. Lets a
   * client say when a membership ran out. Optional so existing callers that
   * build a status by hand stay valid.
   */
  expiredMemberships?: MembershipInfo[];
  finagoCategoryIds: number[];
  isMember: boolean;
  memberships: MembershipInfo[];
  reason?: string;
}
```

2. Add below `withDeadline`:

```ts
const EXPIRY_DATE_RE = /^(\d{4}-\d{2}-\d{2})/;

const osloDateFormat = new Intl.DateTimeFormat("en-CA", {
  day: "2-digit",
  month: "2-digit",
  timeZone: "Europe/Oslo",
  year: "numeric",
});

/** Today's calendar date in Oslo, as `YYYY-MM-DD`. */
export function osloToday(now: Date = new Date()): string {
  return osloDateFormat.format(now);
}

/**
 * Whether a `memberships` row still covers `now`: a membership is valid
 * through the whole of its expiry day in Oslo.
 *
 * A date that cannot be read counts as expired. This check exists so expired
 * memberships stop counting; an unreadable date must not slip through it.
 */
export function isMembershipRowActive(
  expiryDate: string | null | undefined,
  now: Date = new Date()
): boolean {
  const match = EXPIRY_DATE_RE.exec(expiryDate?.trim() ?? "");
  if (!match) {
    return false;
  }
  return match[1] >= osloToday(now);
}
```

3. In `emptyMembershipStatus`, add `expiredMemberships: [],` to the returned object.

4. Replace `computeMembershipStatus` (keep its doc comment, adding one sentence: "A category counts only while its row has not expired — see `isMembershipRowActive`.") with:

```ts
export async function computeMembershipStatus(
  numericId: number,
  now: Date = new Date()
): Promise<MembershipStatus> {
  // 1. Fetch category IDs from Finago (bounded by the per-request deadline).
  let finagoCategoryIds: number[];
  try {
    finagoCategoryIds = await withDeadline(
      getCustomerCategories(numericId),
      membershipFinagoTimeoutMs(),
      "Finago membership category lookup timed out"
    );
  } catch (error) {
    console.error("[Membership] Failed to fetch from Finago:", error);
    throw new MembershipComputationError("finago_error");
  }

  // 2. If no categories, user is (legitimately) not a member — cache this.
  if (!finagoCategoryIds || finagoCategoryIds.length === 0) {
    return emptyMembershipStatus("no_categories");
  }

  // 3. Query active memberships. Uses the admin client so the cached callback
  //    has no dependency on the request session cookie (the `memberships`
  //    table is read("users"); the service key bypasses row permissions).
  const { db } = await createAdminClient();
  const membershipsResponse = await db.listRows<Memberships>(
    "app",
    "memberships",
    [Query.equal("status", true), Query.limit(200)]
  );

  const heldCategories = new Set(finagoCategoryIds.map((id) => String(id)));
  const matched = membershipsResponse.rows.filter(
    (membership) =>
      membership.category !== null &&
      membership.category !== undefined &&
      heldCategories.has(membership.category)
  );

  // 4. A held category counts only while its row has not expired.
  const active: Memberships[] = [];
  const expired: Memberships[] = [];
  for (const membership of matched) {
    if (isMembershipRowActive(membership.expiryDate, now)) {
      active.push(membership);
      continue;
    }
    if (!EXPIRY_DATE_RE.test(membership.expiryDate?.trim() ?? "")) {
      console.warn(
        `[Membership] memberships row ${membership.$id} has an unreadable expiryDate "${membership.expiryDate}"; treating it as expired`
      );
    }
    expired.push(membership);
  }
  expired.sort((a, b) => (b.expiryDate ?? "").localeCompare(a.expiryDate ?? ""));

  const toInfo = (membership: Memberships): MembershipInfo => ({
    category: membership.category,
    expiryDate: membership.expiryDate,
    id: membership.$id,
    name: membership.name,
    startDate: membership.startDate,
  });

  const isMember = active.length > 0;

  return {
    checkedAt: Date.now(),
    expiredMemberships: expired.map(toInfo),
    finagoCategoryIds,
    isMember,
    memberships: active.map(toInfo),
    ...(isMember || expired.length === 0 ? {} : { reason: "expired" }),
  };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shared && bunx vitest run && bun run check-types`
Run: `cd apps/web && bunx vitest run && bun run check-types`
Run: `cd apps/api && bun run test && bun run check-types`
Expected: all PASS (existing callers of `computeMembershipStatus` and hand-built `MembershipStatus` objects still typecheck because `expiredMemberships` is optional).

- [ ] **Step 5: Commit**

```bash
git add packages/shared/utils/membership-status.ts packages/shared/utils/membership-status.test.ts
git commit -m "Stop counting memberships whose catalog row has expired

A 24SevenOffice category now makes someone a member only while its
memberships row has not passed its expiry date, read in Oslo time. The
status also lists the expired matches, so clients can say when cover ran out.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Create 24SevenOffice membership customers under the student number

**Files:**
- Modify: `packages/connectors/src/24sevenoffice/company.ts`
- Create: `packages/connectors/src/24sevenoffice/company.test.ts`
- Modify: `packages/shared/utils/membership-fulfilment.ts`
- Modify: `packages/shared/utils/membership-fulfilment.test.ts` (comment only)
- Modify: `packages/connectors/src/azure/bi-directory.ts` (comment only)
- Modify: `apps/web/src/lib/actions/bi-identity.ts` (comment only)
- Modify: `docs/superpowers/specs/2026-08-12-membership-purchase-design.md`

**Interfaces:**
- Consumes: `UpsertMembershipCustomerParams { email?: string; employeeId: number; firstName: string; lastName: string; studentNumber: number }` (unchanged).
- Produces: `upsertMembershipCustomer` looks up `CompanyId = studentNumber`; creates `{ Id: studentNumber, ExternalId: String(employeeId), … }`.

- [ ] **Step 1: Write the failing test**

Create `packages/connectors/src/24sevenoffice/company.test.ts`:

```ts
import { beforeEach, describe, expect, mock, test } from "bun:test";

const GetCompaniesAsync = mock();
const SaveCompaniesAsync = mock();

mock.module("./auth", () => ({
  getValidSession: async () => "session-token",
}));
mock.module("./client", () => ({
  createAuthenticatedClient: async () => ({
    GetCompaniesAsync,
    SaveCompaniesAsync,
  }),
}));

const { MembershipCustomerLookupError, upsertMembershipCustomer } =
  await import("./company");

const params = {
  email: "s1715738@bi.no",
  employeeId: 1_015_882,
  firstName: "Ola",
  lastName: "Nordmann",
  studentNumber: 1_715_738,
};

describe("upsertMembershipCustomer", () => {
  beforeEach(() => {
    GetCompaniesAsync.mockReset();
    SaveCompaniesAsync.mockReset();
  });

  test("uses the existing customer whose Id is the student number", async () => {
    GetCompaniesAsync.mockResolvedValue([
      { GetCompaniesResult: { Company: { Id: 1_715_738 } } },
    ]);

    await expect(upsertMembershipCustomer(params)).resolves.toBe(1_715_738);
    expect(GetCompaniesAsync).toHaveBeenCalledTimes(1);
    expect(GetCompaniesAsync.mock.calls[0][0].searchParams).toEqual({
      CompanyId: 1_715_738,
    });
    expect(SaveCompaniesAsync).not.toHaveBeenCalled();
  });

  test("creates a missing customer with Id = student number and ExternalId = employee id", async () => {
    GetCompaniesAsync.mockResolvedValue([{ GetCompaniesResult: {} }]);
    SaveCompaniesAsync.mockResolvedValue([
      { SaveCompaniesResult: { Company: { Id: 1_715_738 } } },
    ]);

    await expect(upsertMembershipCustomer(params)).resolves.toBe(1_715_738);

    const saved = SaveCompaniesAsync.mock.calls[0][0].companies.Company;
    expect(saved).toMatchObject({
      Country: "NO",
      CurrencyId: "NOK",
      ExternalId: "1015882",
      FirstName: "Ola",
      Id: 1_715_738,
      Name: "(Student) Nordmann, Ola",
      Private: true,
      Type: "Consumer",
    });
    expect(saved.EmailAddresses).toEqual({
      Primary: { Value: "s1715738@bi.no" },
    });
  });

  test("never creates when the lookup itself fails", async () => {
    GetCompaniesAsync.mockRejectedValue(new Error("24SO timeout"));

    await expect(upsertMembershipCustomer(params)).rejects.toBeInstanceOf(
      MembershipCustomerLookupError
    );
    expect(SaveCompaniesAsync).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/connectors && bun test src/24sevenoffice/company.test.ts`
Expected: FAIL — the lookup uses `CompanyId: 1015882` and the created customer has `Id: 1015882, ExternalId: "1715738"`.

- [ ] **Step 3: Implement**

In `packages/connectors/src/24sevenoffice/company.ts`:

1. In the `MembershipCustomerLookupError` doc comment, change "creates with an explicit, pinned `Id` (the Azure employee id)" to "creates with an explicit, pinned `Id` (the student number)".
2. Replace the `upsertMembershipCustomer` doc comment and function with:

```ts
/**
 * Resolve the Finago customer for a membership purchase, creating it when
 * absent.
 *
 * BI keys its student customers by student number: `Id` is the digits of the
 * student's BI email address (`s1715738@bi.no` → 1715738) — the same number
 * the membership check reads categories from — and `ExternalId` is the
 * student's Azure `employeeId`. A customer created here gets both, so it is
 * indistinguishable from one BI's own app created.
 *
 * The lookup uses `throwOnError` and lets a search failure propagate as
 * `MembershipCustomerLookupError` rather than falling through to create — see
 * that error's doc comment for why a false "not found" here is unsafe.
 */
export async function upsertMembershipCustomer(
  params: UpsertMembershipCustomerParams
): Promise<number> {
  const session = await getValidSession();

  let existing: Company[];
  try {
    existing = await getCompanies(
      session,
      { CompanyId: params.studentNumber },
      { throwOnError: true }
    );
  } catch (error) {
    throw new MembershipCustomerLookupError(error);
  }
  if (existing[0]?.Id) {
    return existing[0].Id;
  }

  const client = await createAuthenticatedClient("company", session);
  const newCompany: Company = {
    Id: params.studentNumber,
    Name: `(Student) ${params.lastName}, ${params.firstName}`,
    FirstName: params.firstName,
    ExternalId: String(params.employeeId),
    Type: "Consumer",
    Private: true,
    Country: "NO",
    CurrencyId: "NOK",
  };

  if (params.email) {
    newCompany.EmailAddresses = { Primary: { Value: params.email } };
  }

  const [result]: [SaveCompaniesResult] = await client.SaveCompaniesAsync({
    companies: { Company: newCompany },
  });

  const saved = result.SaveCompaniesResult?.Company;
  const company = Array.isArray(saved) ? saved[0] : saved;
  if (!company?.Id) {
    throw new Error(
      "[24SO Company] Failed to create membership customer - no id returned"
    );
  }

  console.log(
    `[24SO Company] Created membership customer ${company.Id} (ExternalId: ${params.employeeId})`
  );
  return company.Id;
}
```

In `packages/shared/utils/membership-fulfilment.ts`:
1. In the `resolveBuyerIdentity` doc comment, change "the employee id is the Finago customer number and the student number is its `ExternalId`." to "the student number is the Finago customer number and the employee id is its `ExternalId`."
2. In `prepareFulfilment`, rename the parameter `employeeId: number,` to `studentNumber: number,` and change `customerId: employeeId,` to `customerId: studentNumber,`. At its call site in `fulfilMembershipOrder`, change `identity.employeeId,` to `identity.studentNumber,`. (`postToFinago` still overrides `CustomerId` with the id `upsertMembershipCustomer` resolves.)

In `packages/shared/utils/membership-fulfilment.test.ts`, replace the comment above `upsertMembershipCustomer.mockResolvedValue(5_550_001);` with:

```ts
    // Deliberately different from both the student number and the employee
    // id: the invoice and category must use whatever customer id
    // upsertMembershipCustomer resolves, never an id recomputed from the
    // profile.
```

In `packages/connectors/src/azure/bi-directory.ts`, change "only value this flow needs is `employeeId`, which becomes the Finago customer number." to "only value this flow needs is `employeeId`, which Finago stores as the customer's `ExternalId`."

In `apps/web/src/lib/actions/bi-identity.ts`, change "the Azure employee id that Finago uses as the customer number." to "the Azure employee id that Finago stores as the customer's ExternalId."

In `docs/superpowers/specs/2026-08-12-membership-purchase-design.md`:
- Replace "This design requires the customer number to *be* the Azure employee id, so `Id` must be sent explicitly on create." with "The customer number must *be* the student number from the BI email address, with the Azure employee id as `ExternalId`, so `Id` must be sent explicitly on create. (Corrected 2026-09-15: BI keys student customers by student number.)"
- In the schema table, replace "Azure `employeeId`. This is the Finago CustomerId." with "Azure `employeeId`. Stored as the Finago customer's `ExternalId`."
- Replace the fulfilment step text "Resolve the Finago customer: by `CompanyId` = employee id; failing that by\n   `ExternalId` = sanitized student number; failing that create one with `Id`\n   set explicitly to the employee id, `ExternalId` set to the student number," with "Resolve the Finago customer by `CompanyId` = sanitized student number;\n   failing that create one with `Id` set explicitly to the student number,\n   `ExternalId` set to the employee id,".
- Replace "- customer create sends `Id` equal to the employee id;" with "- customer create sends `Id` equal to the student number and `ExternalId` equal to the employee id;".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/connectors && bun test src && bun run check-types`
Run: `cd packages/shared && bunx vitest run utils/membership-fulfilment.test.ts && bun run check-types`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/connectors/src/24sevenoffice/company.ts packages/connectors/src/24sevenoffice/company.test.ts packages/connectors/src/azure/bi-directory.ts packages/shared/utils/membership-fulfilment.ts packages/shared/utils/membership-fulfilment.test.ts apps/web/src/lib/actions/bi-identity.ts docs/superpowers/specs/2026-08-12-membership-purchase-design.md
git commit -m "Create membership customers under the student number in 24SevenOffice

BI keys student customers by the number in their BI email address and stores
the Azure employee id as ExternalId. Fulfilment had it the other way round,
so a membership bought on our platform landed on a customer the membership
check never reads.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 9: Link a BI student account to one BISO account only

**Files:**
- Modify: `packages/shared/utils/bi-student.ts`
- Modify: `packages/shared/utils/bi-student.test.ts`
- Modify: `apps/web/src/lib/actions/bi-identity.ts`
- Modify: `apps/web/src/lib/actions/bi-identity.test.ts`
- Modify: `apps/web/src/app/api/auth/bi-link/route.ts`
- Create: `apps/web/src/app/api/auth/bi-link/route.test.ts`
- Create: `apps/web/src/lib/account-link-return.ts`
- Create: `apps/web/src/lib/account-link-return.test.ts`
- Modify: `apps/web/src/components/account-link-session-cleanup.tsx`
- Modify: `apps/web/src/app/(public)/onboarding/page.tsx`
- Modify: `apps/web/src/components/onboarding/onboarding-flow.tsx`
- Modify: `apps/web/src/app/(public)/membership/join/gate-states.tsx`
- Modify: `packages/i18n/messages/en/membership.json`, `packages/i18n/messages/no/membership.json`

**Interfaces:**
- Produces: `identityBacksStudentId(identities: readonly LinkedIdentityLike[], studentId: string | null | undefined): boolean` and `interface LinkedIdentityLike { provider?: string | null; providerEmail?: string | null; providerUid?: string | null }` in `@repo/shared/utils/bi-student`.
- Produces: `BiIdentitySyncResult` error union gains `"already_linked"`.
- Produces: `/api/auth/bi-link` redirects to `<returnTo>?link_error=already_linked` on refusal and accepts `returnTo=/membership/link` (used by Task 13).
- Produces: `readAccountLinkReturn(params): { error: "already_linked" | null; isReturnLeg: boolean }` in `@/lib/account-link-return`.

Two link buttons (`NeedsBiLinkState` on `/membership/join` and onboarding's `triggerOidc`) start OIDC without `ensureClientAppwriteSession()`. Per `apps/web/src/lib/account-link-client.ts`, that makes Appwrite create a new account instead of linking. This task fixes both, since the app sends students through `NeedsBiLinkState`.

- [ ] **Step 1: Write the failing tests**

Append to `packages/shared/utils/bi-student.test.ts` (extend the import with `identityBacksStudentId`):

```ts
describe("identityBacksStudentId", () => {
  const oidc = (providerEmail: string, providerUid = providerEmail) => ({
    provider: "oidc",
    providerEmail,
    providerUid,
  });

  it("accepts an OIDC identity whose BI email is that student", () => {
    expect(identityBacksStudentId([oidc("s1715738@bi.no")], "s1715738")).toBe(
      true
    );
    expect(
      identityBacksStudentId([oidc("", "S1715738@BI.NO")], " S1715738 ")
    ).toBe(true);
  });

  it("rejects other students, other providers and staff addresses", () => {
    expect(identityBacksStudentId([oidc("s1000000@bi.no")], "s1715738")).toBe(
      false
    );
    expect(
      identityBacksStudentId(
        [{ provider: "email", providerEmail: "s1715738@bi.no" }],
        "s1715738"
      )
    ).toBe(false);
    expect(
      identityBacksStudentId([oidc("ola.nordmann@bi.no")], "s1715738")
    ).toBe(false);
    expect(identityBacksStudentId([oidc("s1715738@bi.no")], null)).toBe(false);
  });
});
```

In `apps/web/src/lib/actions/bi-identity.test.ts`:
- add `listRows: vi.fn(),` to the hoisted `db`;
- add `const users = vi.hoisted(() => ({ deleteIdentity: vi.fn(), listIdentities: vi.fn() }));`;
- change the mock to `createAdminClient: vi.fn(async () => ({ db, users })),`;
- in `beforeEach` add:

```ts
    db.listRows.mockReset();
    users.deleteIdentity.mockReset();
    users.listIdentities.mockReset();
    db.listRows.mockResolvedValue({ rows: [], total: 0 });
    users.deleteIdentity.mockResolvedValue({});
    users.listIdentities.mockResolvedValue({ identities: [] });
```

- append inside `describe("syncBiStudentIdentity", …)`:

```ts
  it("refuses a BI account already linked to another BISO account and removes the new identity", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    account.listIdentities.mockResolvedValue({
      identities: [oidcIdentity("s1715738@bi.no")],
    });
    db.listRows.mockResolvedValue({
      rows: [{ $id: "user-2", student_id: "s1715738" }],
      total: 1,
    });
    users.listIdentities.mockResolvedValue({
      identities: [
        {
          $id: "identity-9",
          provider: "oidc",
          providerEmail: "s1715738@bi.no",
          providerUid: "s1715738@bi.no",
        },
      ],
    });

    const result = await syncBiStudentIdentity();

    expect(result).toEqual({ success: false, error: "already_linked" });
    expect(users.deleteIdentity).toHaveBeenCalledWith({
      identityId: "identity-1",
    });
    expect(db.updateRow).not.toHaveBeenCalled();
    expect(getBiDirectoryUser).not.toHaveBeenCalled();
  });

  it("clears an unverified claim on another account and links the verified student", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    account.listIdentities.mockResolvedValue({
      identities: [oidcIdentity("s1715738@bi.no")],
    });
    db.listRows.mockResolvedValue({
      rows: [{ $id: "user-2", student_id: "s1715738" }],
      total: 1,
    });
    getBiDirectoryUser.mockResolvedValue({
      campusHint: null,
      displayName: "Ola Nordmann",
      employeeId: "1015882",
      givenName: "Ola",
      mail: "s1715738@bi.no",
      surname: "Nordmann",
    });

    const result = await syncBiStudentIdentity();

    expect(result).toMatchObject({ success: true, studentId: "s1715738" });
    expect(db.updateRow).toHaveBeenCalledWith("app", "user", "user-2", {
      bi_campus_id: null,
      bi_employee_id: null,
      bi_linked_at: null,
      student_id: null,
    });
    expect(db.updateRow).toHaveBeenCalledWith(
      "app",
      "user",
      "user-1",
      expect.objectContaining({ student_id: "s1715738" })
    );
    expect(users.deleteIdentity).not.toHaveBeenCalled();
  });
```

Create `apps/web/src/app/api/auth/bi-link/route.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const syncBiStudentIdentity = vi.hoisted(() => vi.fn());

vi.mock("@/lib/actions/bi-identity", () => ({ syncBiStudentIdentity }));

import { GET } from "./route";

function linkReturn(returnTo: string) {
  return new Request(
    `https://biso.no/api/auth/bi-link?returnTo=${encodeURIComponent(returnTo)}`
  );
}

describe("BI link return leg", () => {
  beforeEach(() => {
    syncBiStudentIdentity.mockReset();
  });

  it("marks a completed link on the page that started it", async () => {
    syncBiStudentIdentity.mockResolvedValue({
      campusHint: null,
      hasEmployeeId: true,
      studentId: "s1715738",
      success: true,
    });

    const response = await GET(linkReturn("/membership/join"));

    expect(response.headers.get("location")).toBe(
      "https://biso.no/membership/join?linked=1"
    );
  });

  it("reports a refused link instead of marking it linked", async () => {
    syncBiStudentIdentity.mockResolvedValue({
      error: "already_linked",
      success: false,
    });

    const response = await GET(linkReturn("/membership/link"));

    expect(response.headers.get("location")).toBe(
      "https://biso.no/membership/link?link_error=already_linked"
    );
  });

  it("still returns a directory failure as linked, for the page's retry state", async () => {
    syncBiStudentIdentity.mockResolvedValue({
      error: "directory_unavailable",
      success: false,
    });

    const response = await GET(linkReturn("/onboarding"));

    expect(response.headers.get("location")).toBe(
      "https://biso.no/onboarding?linked=1"
    );
  });

  it("sends an unknown return path to the profile", async () => {
    syncBiStudentIdentity.mockResolvedValue({
      campusHint: null,
      hasEmployeeId: true,
      studentId: "s1715738",
      success: true,
    });

    const response = await GET(linkReturn("https://evil.example"));

    expect(response.headers.get("location")).toBe(
      "https://biso.no/profile?linked=1"
    );
  });
});
```

Create `apps/web/src/lib/account-link-return.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { readAccountLinkReturn } from "./account-link-return";

describe("readAccountLinkReturn", () => {
  it("recognises a completed link", () => {
    expect(readAccountLinkReturn(new URLSearchParams("linked=1"))).toEqual({
      error: null,
      isReturnLeg: true,
    });
  });

  it("recognises a refused link as a return leg with its error", () => {
    expect(
      readAccountLinkReturn(new URLSearchParams("link_error=already_linked"))
    ).toEqual({ error: "already_linked", isReturnLeg: true });
  });

  it("ignores ordinary visits and unknown errors", () => {
    expect(readAccountLinkReturn(new URLSearchParams(""))).toEqual({
      error: null,
      isReturnLeg: false,
    });
    expect(
      readAccountLinkReturn(new URLSearchParams("link_error=<script>"))
    ).toEqual({ error: null, isReturnLeg: false });
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shared && bunx vitest run utils/bi-student.test.ts`
Run: `cd apps/web && bunx vitest run src/lib/actions/bi-identity.test.ts src/app/api/auth/bi-link src/lib/account-link-return.test.ts`
Expected: FAIL — helper, refusal logic, `link_error` redirect and `readAccountLinkReturn` do not exist.

- [ ] **Step 3: Implement**

Append to `packages/shared/utils/bi-student.ts`:

```ts
export interface LinkedIdentityLike {
  provider?: string | null;
  providerEmail?: string | null;
  providerUid?: string | null;
}

/**
 * Whether an account's Appwrite identities include a BI (OIDC) identity for
 * `studentId`.
 *
 * This is what separates a verified link from a bare claim: Appwrite only
 * creates an OIDC identity after BI's Microsoft sign-in succeeds, while a
 * `user.student_id` value on its own proves nothing about who wrote it.
 */
export function identityBacksStudentId(
  identities: readonly LinkedIdentityLike[],
  studentId: string | null | undefined
): boolean {
  const expected = studentId?.trim().toLowerCase();
  if (!expected) {
    return false;
  }
  return identities.some((identity) => {
    if ((identity.provider ?? "").toLowerCase() !== "oidc") {
      return false;
    }
    const parsed =
      parseBiStudentEmail(identity.providerEmail) ??
      parseBiStudentEmail(identity.providerUid);
    return parsed?.studentId === expected;
  });
}
```

In `apps/web/src/lib/actions/bi-identity.ts`:
1. Add imports: `import { Query } from "@repo/api";` and extend the `@repo/shared/utils/bi-student` import with `identityBacksStudentId`.
2. Add `| "already_linked"` to the `error` union in `BiIdentitySyncResult`.
3. Add below `isRowNotFoundError`:

```ts
type AdminClients = Awaited<ReturnType<typeof createAdminClient>>;

/**
 * One BISO account per BI student account, checked before a link is written.
 *
 * Another account holding the same `student_id` blocks the link only when
 * that hold is verified — the other account has a BI (OIDC) identity for the
 * same student. The identity Appwrite just attached to the current account is
 * then removed, so it is not left holding a BI identity with no link. A hold
 * nothing verifies (written before profile rows were locked, or by the retired
 * app flow) is not a link: it is cleared and the verified student proceeds.
 *
 * Returns true when the link must be refused.
 */
async function refuseIfLinkedElsewhere(
  { db, users }: Pick<AdminClients, "db" | "users">,
  {
    currentUserId,
    identityId,
    studentId,
  }: { currentUserId: string; identityId: string; studentId: string }
): Promise<boolean> {
  const holders = await db.listRows<BiUser>("app", "user", [
    Query.equal("student_id", studentId),
    Query.notEqual("$id", currentUserId),
    Query.limit(25),
  ]);

  for (const holder of holders.rows) {
    const { identities } = await users.listIdentities({
      queries: [Query.equal("userId", holder.$id), Query.limit(25)],
    });

    if (identityBacksStudentId(identities, studentId)) {
      await users.deleteIdentity({ identityId }).catch((error: unknown) => {
        console.error(
          "[BI Identity] Could not remove the refused identity:",
          error
        );
      });
      console.warn(
        `[BI Identity] ${studentId} is already linked to ${holder.$id}; refused the link for ${currentUserId}`
      );
      return true;
    }

    await db.updateRow<BiUser>("app", "user", holder.$id, {
      bi_campus_id: null,
      bi_employee_id: null,
      bi_linked_at: null,
      student_id: null,
    });
    console.warn(
      `[BI Identity] Cleared an unverified claim to ${studentId} on ${holder.$id}`
    );
  }

  return false;
}
```

4. In `syncBiStudentIdentity`, directly after the `if (!parsed) { return … "invalid_bi_email" }` block and before `let employeeId`, insert:

```ts
    const { db, users } = await createAdminClient();
    if (
      await refuseIfLinkedElsewhere(
        { db, users },
        {
          currentUserId: user.$id,
          identityId: biIdentity.$id,
          studentId: parsed.studentId,
        }
      )
    ) {
      return { success: false, error: "already_linked" };
    }
```

and delete the later line `const { db } = await createAdminClient();` (the `db` above is reused).

In `apps/web/src/app/api/auth/bi-link/route.ts`:
1. Add `"/membership/link",` to `ALLOWED_RETURN_PATHS` (keep alphabetical order).
2. Replace the end of `GET` (from `await syncBiStudentIdentity();`) with:

```ts
  const result = await syncBiStudentIdentity();

  const destination = new URL(returnTo, SITE_URL);
  if (!result.success && result.error === "already_linked") {
    // The link was refused and the new identity removed again; the
    // destination shows why (see AccountLinkSessionCleanup).
    destination.searchParams.set("link_error", "already_linked");
  } else {
    destination.searchParams.set("linked", "1");
  }
  return NextResponse.redirect(destination);
```

Create `apps/web/src/lib/account-link-return.ts`:

```ts
export type AccountLinkError = "already_linked";

export interface AccountLinkReturn {
  error: AccountLinkError | null;
  isReturnLeg: boolean;
}

/**
 * Reads a BI link return leg off the query string.
 *
 * `/api/auth/bi-link` sends the browser back with `?linked=1`, or with
 * `?link_error=already_linked` when the link was refused. Both end the flow,
 * so both must close the browser-side Appwrite session the link opened.
 */
export function readAccountLinkReturn(params: {
  get(name: string): string | null;
}): AccountLinkReturn {
  const error =
    params.get("link_error") === "already_linked" ? "already_linked" : null;
  return { error, isReturnLeg: params.get("linked") === "1" || error !== null };
}
```

Replace the body of `apps/web/src/components/account-link-session-cleanup.tsx` below its doc comment (update the comment's "Every link return leg lands on `?linked=1`" sentence to "Every link return leg lands on `?linked=1` or `?link_error=…`"):

```tsx
"use client";

import { useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { endClientAppwriteSession } from "@/lib/account-link-client";
import { readAccountLinkReturn } from "@/lib/account-link-return";

export function AccountLinkSessionCleanup() {
  const searchParams = useSearchParams();
  const { error, isReturnLeg } = readAccountLinkReturn(searchParams);
  const t = useTranslations("membership.join.needsBiLink");
  const handled = useRef(false);

  useEffect(() => {
    if (!isReturnLeg || handled.current) {
      return;
    }
    // A ref rather than state: this must fire once per return leg, and
    // re-running it on a re-render would be a pointless extra 401.
    handled.current = true;
    if (error === "already_linked") {
      toast.error(t("alreadyLinked"));
    }
    endClientAppwriteSession().catch(() => {
      // Already swallowed inside; nothing actionable for the visitor here.
    });
  }, [error, isReturnLeg, t]);

  return null;
}
```

(Keep the existing doc comment block above `export function`; the imports move to the top of the file as shown.)

In `apps/web/src/app/(public)/onboarding/page.tsx`: add `link_error?: string;` to the `searchParams` type, and change the redirect guard to `if (userData.profile && params.linked !== "1" && !params.link_error) {`.

In `apps/web/src/components/onboarding/onboarding-flow.tsx`: add `import { ensureClientAppwriteSession } from "@/lib/account-link-client";` and replace `triggerOidc` with:

```tsx
  const triggerOidc = async () => {
    setState((prev) => ({ ...prev, pendingOAuth: true }));
    try {
      // Without a browser-side Appwrite session the OAuth redirect creates a
      // brand-new account instead of linking this one — see
      // ensureClientAppwriteSession.
      await ensureClientAppwriteSession();
      const base = window.location.origin;
      // Success routes through /api/auth/bi-link, which runs the sync + cache
      // invalidation outside the render path and only then redirects back
      // here with ?linked=1 — see that route's doc comment for why.
      await clientAccount.createOAuth2Session(
        OAuthProvider.Oidc,
        `${base}/api/auth/bi-link?returnTo=/onboarding`,
        `${base}/onboarding?oidc_failed=1`,
        ["openid", "email", "profile"]
      );
    } catch {
      setState((prev) => ({ ...prev, pendingOAuth: false }));
      setSubmitError(t("errors.unknown"));
    }
  };
```

In `apps/web/src/app/(public)/membership/join/gate-states.tsx`: change `import { useTransition } from "react";` to `import { useState, useTransition } from "react";`, add `import { ensureClientAppwriteSession } from "@/lib/account-link-client";`, and replace `NeedsBiLinkState` with:

```tsx
export function NeedsBiLinkState({
  linkFailed = false,
}: {
  linkFailed?: boolean;
}) {
  const t = useTranslations("membership.join.needsBiLink");
  const [isLinking, startLink] = useTransition();
  const [startFailed, setStartFailed] = useState(false);

  const link = () => {
    setStartFailed(false);
    startLink(async () => {
      try {
        // Without a browser-side Appwrite session the OAuth redirect creates
        // a brand-new account instead of linking this one — see
        // ensureClientAppwriteSession.
        await ensureClientAppwriteSession();
        const base = window.location.origin;
        // Success routes through /api/auth/bi-link, which runs the sync +
        // cache invalidation outside the render path and only then redirects
        // back here — see that route's doc comment for why.
        await clientAccount.createOAuth2Session(
          OAuthProvider.Oidc,
          `${base}/api/auth/bi-link?returnTo=/membership/join`,
          `${base}/membership/join?oidc_failed=1`,
          ["openid", "email", "profile"]
        );
      } catch {
        setStartFailed(true);
      }
    });
  };

  return (
    <StateCard
      alert={
        linkFailed || startFailed ? (
          <Alert className="text-left" variant="destructive">
            <AlertDescription>{t("linkFailed")}</AlertDescription>
          </Alert>
        ) : null
      }
      body={t("body")}
      icon={Link2}
      title={t("title")}
    >
      <Button disabled={isLinking} onClick={link}>
        {t("cta")}
      </Button>
    </StateCard>
  );
}
```

In `packages/i18n/messages/en/membership.json`, inside `join.needsBiLink`, after the `"linkFailed"` entry add:

```json
      "alreadyLinked": "This BI student account is already linked to another BISO account. Unlink it there, or contact BISO."
```

In `packages/i18n/messages/no/membership.json`, same place:

```json
      "alreadyLinked": "Denne BI-studentkontoen er allerede koblet til en annen BISO-konto. Koble den fra der, eller kontakt BISO."
```

(Add the comma after the preceding `"linkFailed"` value in both files.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shared && bunx vitest run utils/bi-student.test.ts && bun run check-types`
Run: `cd apps/web && bunx vitest run && bun run check-types`
Expected: PASS. Then `bunx biome lint apps/web/src packages/shared/utils` from the root: no errors.

- [ ] **Step 5: Commit**

```bash
git add packages/shared/utils/bi-student.ts packages/shared/utils/bi-student.test.ts apps/web/src/lib/actions/bi-identity.ts apps/web/src/lib/actions/bi-identity.test.ts apps/web/src/app/api/auth/bi-link apps/web/src/lib/account-link-return.ts apps/web/src/lib/account-link-return.test.ts apps/web/src/components/account-link-session-cleanup.tsx "apps/web/src/app/(public)/onboarding/page.tsx" apps/web/src/components/onboarding/onboarding-flow.tsx "apps/web/src/app/(public)/membership/join/gate-states.tsx" packages/i18n/messages/en/membership.json packages/i18n/messages/no/membership.json
git commit -m "Allow a BI student account to be linked to one BISO account only

A link is refused when another account already holds the student id through
a verified BI identity, and an unverified claim is cleared instead of
blocking the real student. The join page and onboarding now open a browser
Appwrite session before starting the link, which they skipped, so those
buttons created new accounts instead of linking.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 10: Scripts that strip old write grants and audit student links

**Files:**
- Create: `packages/shared/utils/row-permission-lockdown.ts`
- Create: `packages/shared/utils/row-permission-lockdown.test.ts`
- Create: `packages/shared/scripts/revoke-expense-owner-writes.ts`
- Create: `packages/shared/scripts/lock-profile-rows.ts`
- Modify: `packages/shared/package.json` (scripts)

**Interfaces:**
- Consumes: `identityBacksStudentId` from Task 9.
- Produces (in `@repo/shared/utils/row-permission-lockdown`):
  - `withoutOwnerWriteGrants(permissions: readonly string[]): string[]`
  - `revokeOwnerWriteGrants(db: LockdownDb, tableId: "expense" | "user", options: { apply: boolean }): Promise<OwnerWriteRevocationReport>`
  - `auditStudentLinks(db: LockdownDb, users: IdentityLister, options: { clearUnverified: boolean }): Promise<StudentLinkReport>`
- Produces package scripts `lockdown:expense-rows` and `lockdown:profile-rows` (dry-run unless `--apply`). The owner runs them; the implementer only runs the tests.

- [ ] **Step 1: Write the failing test**

Create `packages/shared/utils/row-permission-lockdown.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  auditStudentLinks,
  revokeOwnerWriteGrants,
  withoutOwnerWriteGrants,
} from "./row-permission-lockdown";

function page<T>(rows: T[]) {
  return { rows, total: rows.length };
}

describe("withoutOwnerWriteGrants", () => {
  it("drops per-user write grants and keeps reads and team grants", () => {
    expect(
      withoutOwnerWriteGrants([
        'read("user:u1")',
        'update("user:u1")',
        'delete("user:u1")',
        'write("user:u1")',
        'update("team:finance")',
        'read("any")',
      ])
    ).toEqual(['read("user:u1")', 'update("team:finance")', 'read("any")']);
  });
});

describe("revokeOwnerWriteGrants", () => {
  const db = { listRows: vi.fn(), updateRow: vi.fn() };

  beforeEach(() => {
    vi.clearAllMocks();
    db.updateRow.mockResolvedValue({});
  });

  it("reports what it would change without writing in a dry run", async () => {
    db.listRows.mockResolvedValueOnce(
      page([
        { $id: "e1", $permissions: ['read("user:u1")', 'update("user:u1")'] },
        { $id: "e2", $permissions: ['read("user:u2")'] },
      ])
    );

    const report = await revokeOwnerWriteGrants(db, "expense", {
      apply: false,
    });

    expect(report).toEqual({
      changed: [{ removed: ['update("user:u1")'], rowId: "e1" }],
      errors: [],
      scanned: 2,
    });
    expect(db.updateRow).not.toHaveBeenCalled();
  });

  it("pages through every row and rewrites only rows that change", async () => {
    const fullPage = Array.from({ length: 100 }, (_, index) => ({
      $id: `e${index}`,
      $permissions: ['read("user:u")'],
    }));
    db.listRows
      .mockResolvedValueOnce(page(fullPage))
      .mockResolvedValueOnce(
        page([
          {
            $id: "e100",
            $permissions: ['read("user:u")', 'delete("user:u")'],
          },
        ])
      );

    const report = await revokeOwnerWriteGrants(db, "user", { apply: true });

    expect(report.scanned).toBe(101);
    expect(db.listRows).toHaveBeenCalledTimes(2);
    expect(db.updateRow).toHaveBeenCalledTimes(1);
    expect(db.updateRow).toHaveBeenCalledWith({
      databaseId: "app",
      permissions: ['read("user:u")'],
      rowId: "e100",
      tableId: "user",
    });
  });

  it("records a failed write and carries on", async () => {
    db.listRows.mockResolvedValueOnce(
      page([
        { $id: "e1", $permissions: ['update("user:u1")'] },
        { $id: "e2", $permissions: ['update("user:u2")'] },
      ])
    );
    db.updateRow
      .mockRejectedValueOnce(new Error("rate limited"))
      .mockResolvedValueOnce({});

    const report = await revokeOwnerWriteGrants(db, "expense", {
      apply: true,
    });

    expect(report.errors).toEqual([{ message: "rate limited", rowId: "e1" }]);
    expect(db.updateRow).toHaveBeenCalledTimes(2);
  });
});

describe("auditStudentLinks", () => {
  const db = { listRows: vi.fn(), updateRow: vi.fn() };
  const users = { listIdentities: vi.fn() };
  const verified = (studentId: string) => ({
    identities: [
      {
        provider: "oidc",
        providerEmail: `${studentId}@bi.no`,
        providerUid: `${studentId}@bi.no`,
      },
    ],
  });

  beforeEach(() => {
    vi.clearAllMocks();
    db.updateRow.mockResolvedValue({});
  });

  it("reports unverified links and duplicates, clearing nothing in a dry run", async () => {
    db.listRows.mockResolvedValueOnce(
      page([
        { $id: "u1", $permissions: [], student_id: "s1" },
        { $id: "u2", $permissions: [], student_id: "s1" },
        { $id: "u3", $permissions: [], student_id: "s2" },
      ])
    );
    users.listIdentities
      .mockResolvedValueOnce(verified("s1"))
      .mockResolvedValueOnce(verified("s1"))
      .mockResolvedValueOnce({ identities: [] });

    const report = await auditStudentLinks(db, users, {
      clearUnverified: false,
    });

    expect(report.unverified).toEqual([{ rowId: "u3", studentId: "s2" }]);
    expect(report.duplicates).toEqual([
      { rowIds: ["u1", "u2"], studentId: "s1" },
    ]);
    expect(report.cleared).toEqual([]);
    expect(db.updateRow).not.toHaveBeenCalled();
  });

  it("clears the link columns on unverified rows when asked", async () => {
    db.listRows.mockResolvedValueOnce(
      page([{ $id: "u3", $permissions: [], student_id: "s2" }])
    );
    users.listIdentities.mockResolvedValueOnce({ identities: [] });

    const report = await auditStudentLinks(db, users, {
      clearUnverified: true,
    });

    expect(report.cleared).toEqual(["u3"]);
    expect(db.updateRow).toHaveBeenCalledWith({
      data: {
        bi_campus_id: null,
        bi_employee_id: null,
        bi_linked_at: null,
        student_id: null,
      },
      databaseId: "app",
      rowId: "u3",
      tableId: "user",
    });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/shared && bunx vitest run utils/row-permission-lockdown.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `packages/shared/utils/row-permission-lockdown.ts`:

```ts
import { Query } from "@repo/api";
import { identityBacksStudentId, type LinkedIdentityLike } from "./bi-student";

/**
 * One-off maintenance for the lockdown of expense and profile rows.
 *
 * New rows are created read-only to their owner (`buildExpenseRowPermissions`,
 * `buildProfileRowPermissions`), but rows written earlier still carry per-user
 * write grants, and profile rows written earlier may carry `student_id` values
 * nothing verifies. The CLIs in `packages/shared/scripts` run these, dry-run by
 * default. They must only run after the apps/api and apps/web builds that
 * write these rows through the admin client are live.
 */

const DATABASE_ID = "app";
const PAGE_SIZE = 100;
const OWNER_WRITE_GRANT_RE = /^(update|delete|write)\("user:[^"]+"\)$/;

export interface LockdownRow {
  $id: string;
  $permissions: string[];
  [column: string]: unknown;
}

export interface LockdownDb {
  listRows(params: {
    databaseId: string;
    queries?: string[];
    tableId: string;
  }): Promise<{ rows: LockdownRow[]; total: number }>;
  updateRow(params: {
    data?: Record<string, unknown>;
    databaseId: string;
    permissions?: string[];
    rowId: string;
    tableId: string;
  }): Promise<unknown>;
}

export interface IdentityLister {
  listIdentities(params: {
    queries?: string[];
  }): Promise<{ identities: LinkedIdentityLike[] }>;
}

export interface OwnerWriteRevocationReport {
  changed: Array<{ removed: string[]; rowId: string }>;
  errors: Array<{ message: string; rowId: string }>;
  scanned: number;
}

export interface StudentLinkReport {
  cleared: string[];
  duplicates: Array<{ rowIds: string[]; studentId: string }>;
  errors: Array<{ message: string; rowId: string }>;
  unverified: Array<{ rowId: string; studentId: string }>;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** Every row of a table, read fully before anything is written. */
async function readAllRows(
  db: LockdownDb,
  tableId: string,
  filters: string[] = []
): Promise<LockdownRow[]> {
  const rows: LockdownRow[] = [];
  let cursor: string | null = null;
  for (;;) {
    const queries = [
      ...filters,
      Query.limit(PAGE_SIZE),
      ...(cursor ? [Query.cursorAfter(cursor)] : []),
    ];
    const page = await db.listRows({ databaseId: DATABASE_ID, queries, tableId });
    rows.push(...page.rows);
    if (page.rows.length < PAGE_SIZE) {
      return rows;
    }
    cursor = page.rows.at(-1)?.$id ?? null;
  }
}

/** A row's permissions without any per-user write grant. */
export function withoutOwnerWriteGrants(
  permissions: readonly string[]
): string[] {
  return permissions.filter(
    (permission) => !OWNER_WRITE_GRANT_RE.test(permission)
  );
}

export async function revokeOwnerWriteGrants(
  db: LockdownDb,
  tableId: "expense" | "user",
  options: { apply: boolean }
): Promise<OwnerWriteRevocationReport> {
  const report: OwnerWriteRevocationReport = {
    changed: [],
    errors: [],
    scanned: 0,
  };

  for (const row of await readAllRows(db, tableId)) {
    report.scanned += 1;
    const kept = withoutOwnerWriteGrants(row.$permissions);
    if (kept.length === row.$permissions.length) {
      continue;
    }
    report.changed.push({
      removed: row.$permissions.filter((permission) => !kept.includes(permission)),
      rowId: row.$id,
    });
    if (!options.apply) {
      continue;
    }
    try {
      await db.updateRow({
        databaseId: DATABASE_ID,
        permissions: kept,
        rowId: row.$id,
        tableId,
      });
    } catch (error) {
      report.errors.push({ message: messageOf(error), rowId: row.$id });
    }
  }

  return report;
}

export async function auditStudentLinks(
  db: LockdownDb,
  users: IdentityLister,
  options: { clearUnverified: boolean }
): Promise<StudentLinkReport> {
  const report: StudentLinkReport = {
    cleared: [],
    duplicates: [],
    errors: [],
    unverified: [],
  };
  const verifiedHolders = new Map<string, string[]>();

  for (const row of await readAllRows(db, "user", [
    Query.isNotNull("student_id"),
  ])) {
    const studentId =
      typeof row.student_id === "string"
        ? row.student_id.trim().toLowerCase()
        : "";
    if (!studentId) {
      continue;
    }

    let verified: boolean;
    try {
      const { identities } = await users.listIdentities({
        queries: [Query.equal("userId", row.$id), Query.limit(25)],
      });
      verified = identityBacksStudentId(identities, studentId);
    } catch (error) {
      report.errors.push({ message: messageOf(error), rowId: row.$id });
      continue;
    }

    if (verified) {
      verifiedHolders.set(studentId, [
        ...(verifiedHolders.get(studentId) ?? []),
        row.$id,
      ]);
      continue;
    }

    report.unverified.push({ rowId: row.$id, studentId });
    if (!options.clearUnverified) {
      continue;
    }
    try {
      await db.updateRow({
        data: {
          bi_campus_id: null,
          bi_employee_id: null,
          bi_linked_at: null,
          student_id: null,
        },
        databaseId: DATABASE_ID,
        rowId: row.$id,
        tableId: "user",
      });
      report.cleared.push(row.$id);
    } catch (error) {
      report.errors.push({ message: messageOf(error), rowId: row.$id });
    }
  }

  for (const [studentId, rowIds] of verifiedHolders) {
    if (rowIds.length > 1) {
      report.duplicates.push({ rowIds, studentId });
    }
  }

  return report;
}
```

Create `packages/shared/scripts/revoke-expense-owner-writes.ts`:

```ts
/**
 * Removes per-user write grants from every expense row, so a submitter can read
 * their expense and only apps/api (admin key, after ownership checks) can
 * change it. Dry-run by default; pass --apply to write.
 *
 * DO NOT apply before the apps/api build that edits drafts through the admin
 * client is live.
 *
 * Usage (from packages/shared):
 *   bun run lockdown:expense-rows
 *   bun run lockdown:expense-rows -- --apply
 */
import { Client, TablesDB } from "node-appwrite";
import {
  type LockdownDb,
  revokeOwnerWriteGrants,
} from "../utils/row-permission-lockdown";

const endpoint =
  process.env.NEXT_PUBLIC_APPWRITE_ENDPOINT ?? process.env.APPWRITE_ENDPOINT;
const project =
  process.env.NEXT_PUBLIC_APPWRITE_PROJECT ?? process.env.APPWRITE_PROJECT_ID;
const apiKey = process.env.APPWRITE_API_KEY;

if (!(endpoint && project && apiKey)) {
  console.error(
    "Missing Appwrite configuration: need NEXT_PUBLIC_APPWRITE_ENDPOINT, NEXT_PUBLIC_APPWRITE_PROJECT, and APPWRITE_API_KEY."
  );
  process.exit(2);
}

const apply = process.argv.includes("--apply");
const client = new Client()
  .setEndpoint(endpoint)
  .setProject(project)
  .setKey(apiKey);
const db = new TablesDB(client) as unknown as LockdownDb;

const report = await revokeOwnerWriteGrants(db, "expense", { apply });

console.log(`Mode: ${apply ? "APPLY" : "dry-run"}`);
console.log(`Expense rows scanned: ${report.scanned}`);
console.log(
  `${apply ? "Removed" : "Would remove"} write grants on ${report.changed.length} rows`
);
for (const entry of report.changed) {
  console.log(`  ${entry.rowId}: ${entry.removed.join(", ")}`);
}
if (report.errors.length > 0) {
  console.error(`ERRORS: ${report.errors.length}`);
  for (const entry of report.errors) {
    console.error(`  ${entry.rowId}: ${entry.message}`);
  }
  process.exit(1);
}
```

Create `packages/shared/scripts/lock-profile-rows.ts`:

```ts
/**
 * Locks profile rows and cleans up student links, in this order:
 *   1. removes per-user write grants from every `user` row;
 *   2. reports `student_id` values no BI (OIDC) identity verifies, and clears
 *      them when run with --apply --clear-unverified-links;
 *   3. reports any student id still held by more than one row.
 * Step 1 runs first so a cleared claim cannot be written back.
 *
 * Dry-run by default. DO NOT apply before the apps/web and apps/api builds that
 * write profiles through the admin client are live, and the app build that
 * saves profiles through PUT /api/profile has shipped.
 *
 * Usage (from packages/shared):
 *   bun run lockdown:profile-rows
 *   bun run lockdown:profile-rows -- --apply --clear-unverified-links
 */
import { Client, TablesDB, Users } from "node-appwrite";
import {
  auditStudentLinks,
  type IdentityLister,
  type LockdownDb,
  revokeOwnerWriteGrants,
} from "../utils/row-permission-lockdown";

const endpoint =
  process.env.NEXT_PUBLIC_APPWRITE_ENDPOINT ?? process.env.APPWRITE_ENDPOINT;
const project =
  process.env.NEXT_PUBLIC_APPWRITE_PROJECT ?? process.env.APPWRITE_PROJECT_ID;
const apiKey = process.env.APPWRITE_API_KEY;

if (!(endpoint && project && apiKey)) {
  console.error(
    "Missing Appwrite configuration: need NEXT_PUBLIC_APPWRITE_ENDPOINT, NEXT_PUBLIC_APPWRITE_PROJECT, and APPWRITE_API_KEY."
  );
  process.exit(2);
}

const apply = process.argv.includes("--apply");
const clearUnverified =
  apply && process.argv.includes("--clear-unverified-links");
const client = new Client()
  .setEndpoint(endpoint)
  .setProject(project)
  .setKey(apiKey);
const db = new TablesDB(client) as unknown as LockdownDb;
const users = new Users(client) as unknown as IdentityLister;

const grants = await revokeOwnerWriteGrants(db, "user", { apply });
console.log(`Mode: ${apply ? "APPLY" : "dry-run"}`);
console.log(`Profile rows scanned: ${grants.scanned}`);
console.log(
  `${apply ? "Removed" : "Would remove"} write grants on ${grants.changed.length} rows`
);

const links = await auditStudentLinks(db, users, { clearUnverified });
console.log(`Unverified student links: ${links.unverified.length}`);
for (const entry of links.unverified) {
  console.log(`  ${entry.rowId}: ${entry.studentId}`);
}
console.log(
  clearUnverified
    ? `Cleared: ${links.cleared.length}`
    : "Not cleared (pass --apply --clear-unverified-links to clear)."
);
console.log(`Student ids held by more than one verified row: ${links.duplicates.length}`);
for (const entry of links.duplicates) {
  console.log(`  ${entry.studentId}: ${entry.rowIds.join(", ")}`);
}

const errors = [...grants.errors, ...links.errors];
if (errors.length > 0) {
  console.error(`ERRORS: ${errors.length}`);
  for (const entry of errors) {
    console.error(`  ${entry.rowId}: ${entry.message}`);
  }
  process.exit(1);
}
```

In `packages/shared/package.json`, add to `"scripts"`:

```json
    "lockdown:expense-rows": "bun --env-file=../../apps/admin/.env.local scripts/revoke-expense-owner-writes.ts",
    "lockdown:profile-rows": "bun --env-file=../../apps/admin/.env.local scripts/lock-profile-rows.ts",
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shared && bunx vitest run utils/row-permission-lockdown.test.ts && bun run check-types`
Expected: PASS. If `check-types` rejects top-level `await` in `scripts/*.ts`, compare with `packages/api/tsconfig.json` (which type-checks `packages/api/scripts` the same way) and apply the same `compilerOptions`; do not exclude the scripts from type checking.

Do NOT run either script against Appwrite.

- [ ] **Step 5: Commit**

```bash
git add packages/shared/utils/row-permission-lockdown.ts packages/shared/utils/row-permission-lockdown.test.ts packages/shared/scripts packages/shared/package.json
git commit -m "Add owner scripts that lock old expense and profile rows

Rows written before the lockdown still carry per-user write grants, and
profile rows may hold student ids nothing verifies. The scripts remove the
grants, report and optionally clear unverified links, and list any student id
still on more than one account. Both are dry runs unless told to apply.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 11: Share the membership gate and catalog

**Files:**
- Move: `apps/web/src/lib/membership-gate.ts` → `packages/shared/utils/membership-gate.ts`
- Move: `apps/web/src/lib/membership-gate.test.ts` → `packages/shared/utils/membership-gate.test.ts`
- Move: `apps/web/src/lib/membership-catalog.ts` → `packages/shared/utils/membership-catalog.ts`
- Modify: `apps/web/src/app/(public)/membership/join/page.tsx`, `apps/web/src/app/actions/membership.ts`, `apps/web/src/app/actions/membership-purchase.ts`, `apps/web/src/app/actions/membership-purchase.test.ts` (imports only)

**Interfaces:**
- Produces: `resolveMembershipGate(input: MembershipGateInput): MembershipGate` and `type MembershipGateState` from `@repo/shared/utils/membership-gate`; `getPurchasableMembershipPlans(): Promise<MembershipPlan[]>` and `getMembershipPlanById(planId: string)` from `@repo/shared/utils/membership-catalog`. Behaviour unchanged.

- [ ] **Step 1: Move the test first and watch it fail**

```bash
git mv apps/web/src/lib/membership-gate.test.ts packages/shared/utils/membership-gate.test.ts
cd packages/shared && bunx vitest run utils/membership-gate.test.ts
```

Expected: FAIL — `./membership-gate` does not exist in `packages/shared/utils`.

- [ ] **Step 2: Move the modules**

```bash
git mv apps/web/src/lib/membership-gate.ts packages/shared/utils/membership-gate.ts
git mv apps/web/src/lib/membership-catalog.ts packages/shared/utils/membership-catalog.ts
```

In both moved modules, change `from "@repo/shared/utils/membership-plans"` to `from "./membership-plans"` (packages/shared imports its own utils relatively). In `packages/shared/utils/membership-gate.test.ts`, make the same change if it imports `@repo/shared/utils/membership-plans`.

- [ ] **Step 3: Update the web imports**

- `apps/web/src/app/(public)/membership/join/page.tsx`: `@/lib/membership-catalog` → `@repo/shared/utils/membership-catalog`; `@/lib/membership-gate` → `@repo/shared/utils/membership-gate`.
- `apps/web/src/app/actions/membership.ts` and `apps/web/src/app/actions/membership-purchase.ts`: `@/lib/membership-catalog` → `@repo/shared/utils/membership-catalog`.
- `apps/web/src/app/actions/membership-purchase.test.ts`: `vi.mock("@/lib/membership-catalog", …)` → `vi.mock("@repo/shared/utils/membership-catalog", …)`.

Then `rg -n "lib/membership-(gate|catalog)" apps packages` must print nothing.

- [ ] **Step 4: Run the tests**

Run: `cd packages/shared && bunx vitest run utils/membership-gate.test.ts && bun run check-types`
Run: `cd apps/web && bunx vitest run && bun run check-types`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A packages/shared/utils apps/web/src
git commit -m "Share the membership gate and catalog between web and API

The app's membership overview must apply exactly the rules the join page
applies, so both move to packages/shared unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Membership overview for the app

**Files:**
- Create: `apps/api/src/lib/membership-status-cache.ts`
- Create: `apps/api/src/lib/membership-status-cache.test.ts`
- Create: `apps/api/src/app/api/membership/route.ts`
- Create: `apps/api/src/app/api/membership/route.test.ts`

**Interfaces:**
- Consumes: `computeMembershipStatus` / `emptyMembershipStatus` / `MembershipComputationError` / `membershipCacheTag` (Task 7), `resolveMembershipGate`, `getPurchasableMembershipPlans` (Task 11).
- Produces: `getMembershipStatusForStudent(studentNumber: number, options?: { refresh?: boolean }): Promise<MembershipStatus>` and `MEMBERSHIP_REFRESH_FLOOR_MS = 60_000` in `@/lib/membership-status-cache` (Task 14 uses it).
- Produces: `GET /api/membership[?refresh=1]` with a bearer JWT → `200` body:

```json
{
  "state": "needs_bi_link | needs_directory_record | membership_check_unavailable | already_member | no_plans_available | eligible",
  "studentId": "s1715738",
  "isMember": true,
  "memberships": [{ "id": "…", "name": "…", "category": "113178", "startDate": "…", "expiryDate": "2027-06-30" }],
  "expiredMemberships": [],
  "currentExpiry": "2027-06-30",
  "reason": null,
  "checkedAt": "2026-09-15T08:00:00.000Z",
  "offeredPlans": [{ "id": "71", "name": "…", "price": 550, "duration": "year", "accrualMonths": 12, "startDate": "2026-08-01", "expiryDate": "2027-06-30" }],
  "defaultCampusId": "1",
  "campuses": [{ "id": "1", "name": "Oslo" }, { "id": "2", "name": "Bergen" }, { "id": "3", "name": "Trondheim" }, { "id": "4", "name": "Stavanger" }]
}
```

or `401 { message: "Authentication required" }`. The Flutter `MembershipOverview.fromJson` parses exactly these keys.

- [ ] **Step 1: Write the failing tests**

Create `apps/api/src/lib/membership-status-cache.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const computeMembershipStatus = vi.hoisted(() => vi.fn());
const revalidateTag = vi.hoisted(() => vi.fn());
const MembershipComputationError = vi.hoisted(
  () =>
    class MembershipComputationError extends Error {
      readonly reason: string;
      constructor(reason: string) {
        super(reason);
        this.reason = reason;
      }
    }
);

vi.mock("next/cache", () => ({
  revalidateTag,
  unstable_cache: (work: () => Promise<unknown>) => work,
}));
vi.mock("@repo/shared/utils/membership-status", () => ({
  computeMembershipStatus,
  emptyMembershipStatus: (reason: string) => ({
    checkedAt: Date.now(),
    expiredMemberships: [],
    finagoCategoryIds: [],
    isMember: false,
    memberships: [],
    reason,
  }),
  MembershipComputationError,
  membershipCacheTag: (studentNumber: number) => `membership:${studentNumber}`,
}));

import { getMembershipStatusForStudent } from "./membership-status-cache";

function statusCheckedAgo(ms: number, isMember = true) {
  return {
    checkedAt: Date.now() - ms,
    finagoCategoryIds: [113_178],
    isMember,
    memberships: [],
  };
}

describe("getMembershipStatusForStudent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(console, "error").mockImplementation(() => undefined);
  });

  it("serves the cached status without forcing a recompute", async () => {
    computeMembershipStatus.mockResolvedValue(statusCheckedAgo(5 * 60_000));

    await getMembershipStatusForStudent(1_715_738);

    expect(computeMembershipStatus).toHaveBeenCalledTimes(1);
    expect(revalidateTag).not.toHaveBeenCalled();
  });

  it("recomputes on refresh when the cached status is more than a minute old", async () => {
    const fresh = statusCheckedAgo(0, false);
    computeMembershipStatus
      .mockResolvedValueOnce(statusCheckedAgo(5 * 60_000))
      .mockResolvedValueOnce(fresh);

    const status = await getMembershipStatusForStudent(1_715_738, {
      refresh: true,
    });

    expect(revalidateTag).toHaveBeenCalledWith("membership:1715738", {
      expire: 0,
    });
    expect(computeMembershipStatus).toHaveBeenCalledTimes(2);
    expect(status).toBe(fresh);
  });

  it("serves a status less than a minute old even when asked to refresh", async () => {
    computeMembershipStatus.mockResolvedValue(statusCheckedAgo(10_000));

    await getMembershipStatusForStudent(1_715_738, { refresh: true });

    expect(revalidateTag).not.toHaveBeenCalled();
    expect(computeMembershipStatus).toHaveBeenCalledTimes(1);
  });

  it("turns a transient 24SevenOffice failure into an unavailable status", async () => {
    computeMembershipStatus.mockRejectedValue(
      new MembershipComputationError("finago_error")
    );

    const status = await getMembershipStatusForStudent(1_715_738, {
      refresh: true,
    });

    expect(status).toMatchObject({ isMember: false, reason: "finago_error" });
    expect(revalidateTag).not.toHaveBeenCalled();
  });
});
```

Create `apps/api/src/app/api/membership/route.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const account = vi.hoisted(() => ({ get: vi.fn() }));
const getRow = vi.hoisted(() => vi.fn());
const getMembershipStatusForStudent = vi.hoisted(() => vi.fn());
const getPurchasableMembershipPlans = vi.hoisted(() => vi.fn());

vi.mock("server-only", () => ({}));
vi.mock("@repo/connectors/24sevenoffice", () => ({
  getCustomerCategories: vi.fn(),
}));
vi.mock("@/lib/auth", () => ({
  createAuthenticatedClient: vi.fn(async () => ({ account })),
}));
vi.mock("@repo/api/server", () => ({
  createAdminClient: vi.fn(async () => ({ db: { getRow } })),
}));
vi.mock("@/lib/membership-status-cache", () => ({
  getMembershipStatusForStudent,
}));
vi.mock("@repo/shared/utils/membership-catalog", () => ({
  getPurchasableMembershipPlans,
}));

import { GET } from "./route";

const PLAN = {
  accrualMonths: 12,
  categoryId: 113_178,
  duration: "year",
  expiryDate: "2027-06-30",
  id: "71",
  name: "BISO Membership fall 2026 and spring 2027",
  price: 550,
  productId: 71,
  startDate: "2026-08-01",
};

const LINKED_PROFILE = {
  $id: "user-1",
  bi_campus_id: "2",
  bi_employee_id: "1015882",
  student_id: "s1715738",
};

function status(overrides: Record<string, unknown> = {}) {
  return {
    checkedAt: Date.parse("2026-09-15T08:00:00.000Z"),
    expiredMemberships: [],
    finagoCategoryIds: [],
    isMember: false,
    memberships: [],
    reason: "no_categories",
    ...overrides,
  };
}

function overviewRequest(query = "", authorization = "Bearer jwt") {
  const headers = new Headers();
  if (authorization) {
    headers.set("authorization", authorization);
  }
  return new Request(`https://api.biso.no/api/membership${query}`, {
    headers,
  }) as never;
}

describe("GET /api/membership", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    account.get.mockResolvedValue({ $id: "user-1" });
    getRow.mockResolvedValue(LINKED_PROFILE);
    getMembershipStatusForStudent.mockResolvedValue(status());
    getPurchasableMembershipPlans.mockResolvedValue([PLAN]);
  });

  it("requires a bearer token", async () => {
    const response = await GET(overviewRequest("", ""));

    expect(response.status).toBe(401);
    expect(getRow).not.toHaveBeenCalled();
  });

  it("asks an unlinked student to link, without touching 24SevenOffice", async () => {
    getRow.mockResolvedValue({ $id: "user-1", student_id: null });

    const body = await (await GET(overviewRequest())).json();

    expect(body).toMatchObject({
      isMember: false,
      offeredPlans: [],
      state: "needs_bi_link",
      studentId: null,
    });
    expect(body.campuses.map((c: { id: string }) => c.id)).toEqual([
      "1",
      "2",
      "3",
      "4",
    ]);
    expect(getMembershipStatusForStudent).not.toHaveBeenCalled();
  });

  it("offers plans to a linked non-member", async () => {
    const response = await GET(overviewRequest());
    const body = await response.json();

    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(getMembershipStatusForStudent).toHaveBeenCalledWith(1_715_738, {
      refresh: false,
    });
    expect(body).toMatchObject({
      checkedAt: "2026-09-15T08:00:00.000Z",
      currentExpiry: null,
      defaultCampusId: "2",
      isMember: false,
      reason: "no_categories",
      state: "eligible",
      studentId: "s1715738",
    });
    expect(body.offeredPlans).toEqual([
      {
        accrualMonths: 12,
        duration: "year",
        expiryDate: "2027-06-30",
        id: "71",
        name: "BISO Membership fall 2026 and spring 2027",
        price: 550,
        startDate: "2026-08-01",
      },
    ]);
  });

  it("tells a member whose cover already reaches the plan's end that they are covered", async () => {
    const membership = {
      category: "113178",
      expiryDate: "2027-06-30",
      id: "71",
      name: "BISO Membership fall 2026 and spring 2027",
      startDate: "2026-08-01",
    };
    getMembershipStatusForStudent.mockResolvedValue(
      status({ isMember: true, memberships: [membership], reason: undefined })
    );

    const body = await (await GET(overviewRequest())).json();

    expect(body).toMatchObject({
      currentExpiry: "2027-06-30",
      isMember: true,
      memberships: [membership],
      offeredPlans: [],
      reason: null,
      state: "already_member",
    });
  });

  it("forces a refresh when asked", async () => {
    await GET(overviewRequest("?refresh=1"));

    expect(getMembershipStatusForStudent).toHaveBeenCalledWith(1_715_738, {
      refresh: true,
    });
  });

  it("reports an unavailable check instead of 'not a member' when 24SevenOffice fails", async () => {
    getMembershipStatusForStudent.mockResolvedValue(
      status({ reason: "finago_error" })
    );

    const body = await (await GET(overviewRequest())).json();

    expect(body).toMatchObject({
      offeredPlans: [],
      reason: "finago_error",
      state: "membership_check_unavailable",
    });
  });

  it("reports an unavailable check when the profile cannot be read", async () => {
    getRow.mockRejectedValue(Object.assign(new Error("timeout"), { code: 500 }));

    const body = await (await GET(overviewRequest())).json();

    expect(body).toMatchObject({
      reason: "profile_unavailable",
      state: "membership_check_unavailable",
    });
    expect(getMembershipStatusForStudent).not.toHaveBeenCalled();
  });

  it("reports an unavailable check when the catalog cannot be read", async () => {
    getPurchasableMembershipPlans.mockRejectedValue(new Error("appwrite down"));

    const body = await (await GET(overviewRequest())).json();

    expect(body).toMatchObject({
      reason: "catalog_unavailable",
      state: "membership_check_unavailable",
    });
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/membership-status-cache.test.ts src/app/api/membership`
Expected: FAIL — modules not found.

- [ ] **Step 3: Implement**

Create `apps/api/src/lib/membership-status-cache.ts`:

```ts
import {
  computeMembershipStatus,
  emptyMembershipStatus,
  MembershipComputationError,
  type MembershipStatus,
  membershipCacheTag,
} from "@repo/shared/utils/membership-status";
import { revalidateTag, unstable_cache } from "next/cache";

const MEMBERSHIP_CACHE_TTL_SECONDS = 10 * 60;

/** A forced refresh within this long of the last computation is served from cache. */
export const MEMBERSHIP_REFRESH_FLOOR_MS = 60 * 1000;

function cachedStatus(studentNumber: number): Promise<MembershipStatus> {
  const tag = membershipCacheTag(studentNumber);
  return unstable_cache(
    () => computeMembershipStatus(studentNumber),
    ["api-membership", tag],
    { revalidate: MEMBERSHIP_CACHE_TTL_SECONDS, tags: [tag] }
  )();
}

async function readStatus(studentNumber: number): Promise<MembershipStatus> {
  try {
    return await cachedStatus(studentNumber);
  } catch (error) {
    // `unstable_cache` does not cache a thrown error, so a transient failure
    // is retried on the next read rather than remembered for ten minutes.
    if (error instanceof MembershipComputationError) {
      return emptyMembershipStatus(error.reason);
    }
    console.error("[membership] Unexpected status failure:", error);
    return emptyMembershipStatus("unexpected_error");
  }
}

/**
 * Live 24SevenOffice membership status for one student, cached for ten
 * minutes like the website's.
 *
 * `refresh` recomputes — after a purchase, or when a student pulls to
 * refresh — but no more than once a minute per student, so a client cannot
 * turn this endpoint into a 24SevenOffice load generator.
 */
export async function getMembershipStatusForStudent(
  studentNumber: number,
  { refresh = false }: { refresh?: boolean } = {}
): Promise<MembershipStatus> {
  const status = await readStatus(studentNumber);
  if (!refresh) {
    return status;
  }
  // An uncached failure is always stamped "now", so it never passes this
  // check: recomputing it straight away would only repeat the failing call.
  if (Date.now() - status.checkedAt < MEMBERSHIP_REFRESH_FLOOR_MS) {
    return status;
  }
  revalidateTag(membershipCacheTag(studentNumber), { expire: 0 });
  return readStatus(studentNumber);
}
```

Create `apps/api/src/app/api/membership/route.ts`:

```ts
import { createAdminClient } from "@repo/api/server";
import type { Users } from "@repo/api/types/appwrite";
import { sanitizeStudentNumber } from "@repo/shared/utils/bi-student";
import { CAMPUS_INVOICE_NAMES } from "@repo/shared/utils/finago-membership-invoice";
import { getPurchasableMembershipPlans } from "@repo/shared/utils/membership-catalog";
import { resolveMembershipGate } from "@repo/shared/utils/membership-gate";
import type { MembershipPlan } from "@repo/shared/utils/membership-plans";
import {
  emptyMembershipStatus,
  type MembershipStatus,
} from "@repo/shared/utils/membership-status";
import { type NextRequest, NextResponse } from "next/server";
import { createAuthenticatedClient } from "@/lib/auth";
import { applyCorsHeaders, corsPreflightResponse } from "@/lib/cors";
import { getMembershipStatusForStudent } from "@/lib/membership-status-cache";

export const dynamic = "force-dynamic";

/** An invoicing department, not a campus a student joins; the web wizard hides it too. */
const NATIONAL_CAMPUS_ID = "5";

// The bi_* columns are pending an `appwrite push tables`; extend locally
// until packages/api/types/appwrite.ts is regenerated.
type BiUser = Users & {
  bi_campus_id?: string | null;
  bi_employee_id?: string | null;
};

const NO_GATE = { currentExpiry: null, offeredPlans: [] as MembershipPlan[] };

function isRowNotFound(error: unknown): boolean {
  return (error as { code?: number } | null)?.code === 404;
}

function purchasableCampuses() {
  return Object.entries(CAMPUS_INVOICE_NAMES)
    .filter(([id]) => id !== NATIONAL_CAMPUS_ID)
    .map(([id, name]) => ({ id, name }));
}

function overviewBody(
  state: string,
  status: MembershipStatus,
  gate: { currentExpiry: string | null; offeredPlans: MembershipPlan[] },
  studentId: string | null,
  defaultCampusId: string | null
) {
  return {
    campuses: purchasableCampuses(),
    checkedAt: new Date(status.checkedAt).toISOString(),
    currentExpiry: gate.currentExpiry,
    defaultCampusId,
    expiredMemberships: status.expiredMemberships ?? [],
    isMember: status.isMember,
    memberships: status.memberships,
    offeredPlans: gate.offeredPlans.map((plan) => ({
      accrualMonths: plan.accrualMonths,
      duration: plan.duration,
      expiryDate: plan.expiryDate,
      id: plan.id,
      name: plan.name,
      price: plan.price,
      startDate: plan.startDate,
    })),
    reason: status.reason ?? null,
    state,
    studentId,
  };
}

/**
 * The student app's view of the caller's membership: the live 24SevenOffice
 * status (expired memberships excluded), the same purchase gate the website's
 * join page applies, and the plans on offer. Every failure to read reports
 * `membership_check_unavailable`, never "not a member".
 */
export async function GET(req: NextRequest) {
  const origin = req.headers.get("origin");
  const json = (data: unknown, status = 200) => {
    const response = NextResponse.json(data, { status });
    response.headers.set("Cache-Control", "private, no-store");
    return applyCorsHeaders(response, origin);
  };

  if (!req.headers.get("authorization")?.startsWith("Bearer ")) {
    return json({ message: "Authentication required" }, 401);
  }

  let userId: string;
  try {
    const { account } = await createAuthenticatedClient(req);
    userId = (await account.get()).$id;
  } catch {
    return json({ message: "Authentication required" }, 401);
  }

  let profile: BiUser | null;
  try {
    const { db } = await createAdminClient();
    profile = await db
      .getRow<BiUser>("app", "user", userId)
      .catch((error: unknown) => {
        if (isRowNotFound(error)) {
          return null;
        }
        throw error;
      });
  } catch (error) {
    console.error("[membership] Profile read failed:", error);
    return json(
      overviewBody(
        "membership_check_unavailable",
        emptyMembershipStatus("profile_unavailable"),
        NO_GATE,
        null,
        null
      )
    );
  }

  const studentId = profile?.student_id ?? null;
  const defaultCampusId = profile?.bi_campus_id ?? null;
  const studentNumber = sanitizeStudentNumber(studentId);
  if (studentNumber === null) {
    return json(
      overviewBody(
        "needs_bi_link",
        emptyMembershipStatus(studentId ? "invalid_student_id" : "no_student_id"),
        NO_GATE,
        studentId,
        defaultCampusId
      )
    );
  }

  const refresh = new URL(req.url).searchParams.get("refresh") === "1";
  const [status, plans] = await Promise.all([
    getMembershipStatusForStudent(studentNumber, { refresh }),
    getPurchasableMembershipPlans().catch((error: unknown) => {
      console.error("[membership] Catalog read failed:", error);
      return null;
    }),
  ]);

  if (plans === null) {
    return json(
      overviewBody(
        "membership_check_unavailable",
        { ...status, reason: "catalog_unavailable" },
        NO_GATE,
        studentId,
        defaultCampusId
      )
    );
  }

  const gate = resolveMembershipGate({
    employeeId: profile?.bi_employee_id,
    isAuthenticated: true,
    plans,
    status,
    studentId,
  });

  return json(overviewBody(gate.state, status, gate, studentId, defaultCampusId));
}

export function OPTIONS(req: NextRequest) {
  return corsPreflightResponse(req.headers.get("origin"));
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/api && NODE_ENV=test bunx vitest run src/lib/membership-status-cache.test.ts src/app/api/membership && bun run check-types`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/membership-status-cache.ts apps/api/src/lib/membership-status-cache.test.ts apps/api/src/app/api/membership
git commit -m "Give the app a membership overview backed by 24SevenOffice

GET /api/membership returns the live status with expired memberships
excluded, the join page's purchase gate and the plans on offer. Reads are
cached for ten minutes per student and a forced refresh runs at most once a
minute.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 13: Web page the app opens for BI linking

**Files:**
- Create: `apps/web/src/lib/membership-link-state.ts`
- Create: `apps/web/src/lib/membership-link-state.test.ts`
- Create: `apps/web/src/app/(public)/membership/link/page.tsx`
- Create: `apps/web/src/app/(public)/membership/link/linked-state.tsx`
- Modify: `apps/web/src/app/(public)/membership/join/gate-states.tsx`
- Modify: `packages/i18n/messages/en/membership.json`, `packages/i18n/messages/no/membership.json`

**Interfaces:**
- Consumes: `NeedsBiLinkState` with the session bootstrap, and `/membership/link` in the bi-link allow-list (Task 9).
- Produces: `https://biso.no/membership/link` (the Flutter app opens this URL); its linked state links to `biso://membership?linked=1` (the Flutter deep link handler routes this). `resolveMembershipLinkState(input): "signed_out" | "needs_bi_link" | "needs_directory_record" | "linked"`.

The page is deliberately not under `/app/*`: the Android app claims `https://biso.no/app/*` as verified App Links, so the app could not open such a URL in the browser.

- [ ] **Step 1: Write the failing test**

Create `apps/web/src/lib/membership-link-state.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { resolveMembershipLinkState } from "./membership-link-state";

describe("resolveMembershipLinkState", () => {
  it("walks sign-in, link, directory record, then linked", () => {
    expect(
      resolveMembershipLinkState({
        employeeId: null,
        isAuthenticated: false,
        studentId: null,
      })
    ).toBe("signed_out");
    expect(
      resolveMembershipLinkState({
        employeeId: null,
        isAuthenticated: true,
        studentId: null,
      })
    ).toBe("needs_bi_link");
    expect(
      resolveMembershipLinkState({
        employeeId: null,
        isAuthenticated: true,
        studentId: "s1715738",
      })
    ).toBe("needs_directory_record");
    expect(
      resolveMembershipLinkState({
        employeeId: "1015882",
        isAuthenticated: true,
        studentId: "s1715738",
      })
    ).toBe("linked");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/web && bunx vitest run src/lib/membership-link-state.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `apps/web/src/lib/membership-link-state.ts`:

```ts
export type MembershipLinkState =
  | "signed_out"
  | "needs_bi_link"
  | "needs_directory_record"
  | "linked";

/**
 * Which step of BI linking `/membership/link` shows. The app sends students
 * here because BI's tenant is reachable only through Appwrite's OIDC
 * provider, which only a browser holding the student's own session can use.
 */
export function resolveMembershipLinkState(input: {
  employeeId: string | null | undefined;
  isAuthenticated: boolean;
  studentId: string | null | undefined;
}): MembershipLinkState {
  if (!input.isAuthenticated) {
    return "signed_out";
  }
  if (!input.studentId) {
    return "needs_bi_link";
  }
  if (!input.employeeId) {
    return "needs_directory_record";
  }
  return "linked";
}
```

In `apps/web/src/app/(public)/membership/join/gate-states.tsx`:
1. Change `function StateCard(` to `export function StateCard(`.
2. Replace `SignedOutState` with:

```tsx
export function SignedOutState({
  redirectTo = "/membership/join",
}: {
  redirectTo?: string;
}) {
  const t = useTranslations("membership.join.signedOut");
  return (
    <StateCard body={t("body")} icon={LogIn} title={t("title")}>
      <Button asChild>
        <Link href={`/auth/login?redirectTo=${redirectTo}`}>{t("cta")}</Link>
      </Button>
    </StateCard>
  );
}
```

3. In `NeedsBiLinkState` (as rewritten in Task 9), add a `returnTo` prop defaulting to `"/membership/join"`:

```tsx
export function NeedsBiLinkState({
  linkFailed = false,
  returnTo = "/membership/join",
}: {
  linkFailed?: boolean;
  returnTo?: string;
}) {
```

and use it in the two URLs:

```tsx
        await clientAccount.createOAuth2Session(
          OAuthProvider.Oidc,
          `${base}/api/auth/bi-link?returnTo=${returnTo}`,
          `${base}${returnTo}?oidc_failed=1`,
          ["openid", "email", "profile"]
        );
```

Create `apps/web/src/app/(public)/membership/link/linked-state.tsx`:

```tsx
"use client";

import { Button } from "@repo/ui/components/ui/button";
import { CheckCircle2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { StateCard } from "../join/gate-states";

/** The app's membership screen listens for this link and re-verifies on it. */
const APP_MEMBERSHIP_LINKED_URL = "biso://membership?linked=1";

export function LinkedState({ email }: { email: string }) {
  const t = useTranslations("membership.link.linked");
  return (
    <StateCard
      body={t("body", { email })}
      icon={CheckCircle2}
      title={t("title")}
    >
      <Button asChild>
        <a href={APP_MEMBERSHIP_LINKED_URL}>{t("cta")}</a>
      </Button>
    </StateCard>
  );
}
```

Create `apps/web/src/app/(public)/membership/link/page.tsx`:

```tsx
import type { Users } from "@repo/api/types/appwrite";
import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { ShopHeroShell } from "@/components/shop/shop-hero-shell";
import { getLoggedInUser } from "@/lib/actions/user";
import { resolveMembershipLinkState } from "@/lib/membership-link-state";
import { NeedsBiLinkState, SignedOutState } from "../join/gate-states";
import { RetryDirectoryState } from "../join/retry-directory-state";
import { LinkedState } from "./linked-state";

export const metadata: Metadata = {
  description:
    "Link your BI student account so the BISO app can verify your membership.",
  title: "Link your BI student account | BISO",
};

// The bi_* columns are pending an `appwrite push tables`; extend locally
// until packages/api/types/appwrite.ts is regenerated.
type BiUser = Users & { bi_employee_id?: string | null };

interface MembershipLinkPageProps {
  searchParams: Promise<{ oidc_failed?: string }>;
}

/**
 * Where the app sends a student to link their BI account. BI's tenant is
 * reachable only through Appwrite's OIDC provider, and only a browser holding
 * the student's own BISO session can link through it, so this page reuses the
 * join page's link flow and hands the student back to the app when done.
 * A refused link (`?link_error=already_linked`) is announced by
 * `AccountLinkSessionCleanup` in the root layout.
 */
export default async function MembershipLinkPage({
  searchParams,
}: MembershipLinkPageProps) {
  const params = await searchParams;
  const [userData, t] = await Promise.all([
    getLoggedInUser(),
    getTranslations("membership.link"),
  ]);
  const profile = userData?.profile as BiUser | null | undefined;

  const state = resolveMembershipLinkState({
    employeeId: profile?.bi_employee_id,
    isAuthenticated: Boolean(userData?.user),
    studentId: profile?.student_id,
  });

  let body: React.ReactNode;
  if (state === "signed_out") {
    body = <SignedOutState redirectTo="/membership/link" />;
  } else if (state === "needs_bi_link") {
    body = (
      <NeedsBiLinkState
        linkFailed={params.oidc_failed === "1"}
        returnTo="/membership/link"
      />
    );
  } else if (state === "needs_directory_record") {
    body = <RetryDirectoryState />;
  } else {
    body = <LinkedState email={userData?.user.email ?? ""} />;
  }

  return (
    <div className="min-h-screen bg-linear-to-b from-section to-background">
      <ShopHeroShell
        heightClass="h-[32vh] min-h-[240px]"
        subtitle={t("subtitle")}
        title={t("title")}
      />
      <div className="mx-auto max-w-3xl px-4 py-12 sm:px-6">{body}</div>
    </div>
  );
}
```

In `packages/i18n/messages/en/membership.json`, add a top-level `"link"` object next to `"join"`:

```json
  "link": {
    "title": "Link your BI student account",
    "subtitle": "Link it once here, then go back to the BISO app to see your membership.",
    "linked": {
      "title": "Your BI student account is linked",
      "body": "Signed in as {email}. Go back to the BISO app to see your membership.",
      "cta": "Return to the BISO app"
    }
  },
```

In `packages/i18n/messages/no/membership.json`, same place:

```json
  "link": {
    "title": "Koble til BI-studentkontoen din",
    "subtitle": "Koble den til én gang her, og gå så tilbake til BISO-appen for å se medlemskapet ditt.",
    "linked": {
      "title": "BI-studentkontoen din er koblet til",
      "body": "Logget inn som {email}. Gå tilbake til BISO-appen for å se medlemskapet ditt.",
      "cta": "Tilbake til BISO-appen"
    }
  },
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/web && bunx vitest run && bun run check-types`
Expected: PASS. Also run the i18n key check if the package has one: `cd packages/i18n && cat package.json` and run any `check`/`test` script listed; it must pass.

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/lib/membership-link-state.ts apps/web/src/lib/membership-link-state.test.ts "apps/web/src/app/(public)/membership/link" "apps/web/src/app/(public)/membership/join/gate-states.tsx" packages/i18n/messages/en/membership.json packages/i18n/messages/no/membership.json
git commit -m "Add the page the app opens to link a BI student account

BI's tenant is reachable only through Appwrite's OIDC provider in a browser
holding the student's own session, so the app hands linking to this page.
It reuses the join page's link and retry states and sends the student back
to the app once linked.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14: Membership checkout from the app

**Files:**
- Modify: `packages/shared/utils/checkout-return.ts`
- Modify: `packages/shared/utils/checkout-return.test.ts`
- Modify: `apps/api/src/app/api/payment/[provider]/membership-checkout/route.ts`
- Modify: `apps/api/src/app/api/payment/[provider]/membership-checkout/route.test.ts`
- Modify: `apps/api/src/app/api/payment/return/route.ts`
- Modify: `apps/api/src/app/api/payment/return/route.test.ts`

**Interfaces:**
- Consumes: `getMembershipStatusForStudent` (Task 12), `resolveMembershipGate` (Task 11).
- Produces: `POST /api/payment/{vipps|stripe}/membership-checkout` accepts body `{ planId: string, campusId: string, client?: "web" | "app" }`; new errors `409 { message: "Your membership already covers this period." }` and `503 { message: "We couldn't verify your membership right now. Try again shortly." }`.
- Produces: `appMembershipDeepLink(orderId: string, outcome?: { cancelled?: boolean; status?: string | null }): string` → `biso://membership?orderId=…&status=…` or `biso://membership?orderId=…&cancelled=1`. The return route sends app membership buyers there; the Flutter app handles `biso://membership`.

- [ ] **Step 1: Write the failing tests**

Append to `packages/shared/utils/checkout-return.test.ts` (extend the import with `appMembershipDeepLink`):

```ts
describe("appMembershipDeepLink", () => {
  it("reopens the app's membership screen with the order and its status", () => {
    expect(appMembershipDeepLink("order-1", { status: "paid" })).toBe(
      "biso://membership?orderId=order-1&status=paid"
    );
  });

  it("marks an abandoned payment as cancelled rather than reporting a status", () => {
    expect(
      appMembershipDeepLink("order-1", { cancelled: true, status: "pending" })
    ).toBe("biso://membership?orderId=order-1&cancelled=1");
  });

  it("produces a parseable absolute URL", () => {
    expect(new URL(appMembershipDeepLink("a b&c")).protocol).toBe("biso:");
  });
});
```

In `apps/api/src/app/api/payment/[provider]/membership-checkout/route.test.ts`:
- add `getMembershipStatusForStudent: vi.fn(),` to the hoisted `mocks`;
- add `vi.mock("@/lib/membership-status-cache", () => ({ getMembershipStatusForStudent: mocks.getMembershipStatusForStudent }));`;
- in `beforeEach`, add:

```ts
    mocks.getMembershipStatusForStudent.mockResolvedValue({
      checkedAt: Date.now(),
      finagoCategoryIds: [],
      isMember: false,
      memberships: [],
      reason: "no_categories",
    });
```

- give `membershipCheckoutRequest` a `client?: string` option and send it: `body: JSON.stringify({ campusId, planId, ...(client ? { client } : {}) }),`;
- append these tests inside the `describe`:

```ts
  it("sends an app buyer back through the return route marked for the app", async () => {
    const response = await postVipps(
      membershipCheckoutRequest({ authorization: "Bearer valid", client: "app" })
    );

    expect(response.status).toBe(200);
    expect(mockedCreateVippsPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      {
        returnUrl:
          "https://api.biso.no/api/payment/return?orderId=order-1&client=app",
      }
    );
  });

  it("gives an app buyer's Stripe cancel URL the cancelled marker instead of the website", async () => {
    const response = await postStripe(
      membershipCheckoutRequest({ authorization: "Bearer valid", client: "app" })
    );

    expect(response.status).toBe(200);
    expect(mockedCreateStripeCheckoutSession).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      {
        cancelUrl:
          "https://api.biso.no/api/payment/return?orderId=order-1&client=app&cancelled=1",
        successUrl:
          "https://api.biso.no/api/payment/return?orderId=order-1&client=app",
      }
    );
  });

  it("refuses a plan that would not extend the buyer's current cover", async () => {
    mocks.getMembershipStatusForStudent.mockResolvedValue({
      checkedAt: Date.now(),
      finagoCategoryIds: [113_178],
      isMember: true,
      memberships: [
        {
          category: "113178",
          expiryDate: "2027-06-30",
          id: "71",
          name: "BISO Membership fall 2026 and spring 2027",
          startDate: "2026-08-01",
        },
      ],
    });

    const response = await postVipps(
      membershipCheckoutRequest({ authorization: "Bearer valid" })
    );

    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({
      message: "Your membership already covers this period.",
    });
    expect(mockedCreateOrder).not.toHaveBeenCalled();
  });

  it("sells a plan that extends a member's cover", async () => {
    mocks.getMembershipStatusForStudent.mockResolvedValue({
      checkedAt: Date.now(),
      finagoCategoryIds: [113_176],
      isMember: true,
      memberships: [
        {
          category: "113176",
          expiryDate: "2026-12-31",
          id: "54",
          name: "BISO Membership fall 2026",
          startDate: "2026-08-01",
        },
      ],
    });

    const response = await postVipps(
      membershipCheckoutRequest({ authorization: "Bearer valid" })
    );

    expect(response.status).toBe(200);
    expect(mockedCreateOrder).toHaveBeenCalled();
  });

  it("takes no payment while membership cannot be verified", async () => {
    mocks.getMembershipStatusForStudent.mockResolvedValue({
      checkedAt: Date.now(),
      finagoCategoryIds: [],
      isMember: false,
      memberships: [],
      reason: "finago_error",
    });

    const response = await postVipps(
      membershipCheckoutRequest({ authorization: "Bearer valid" })
    );

    expect(response.status).toBe(503);
    expect(mockedCreateOrder).not.toHaveBeenCalled();
  });
```

Append to `apps/api/src/app/api/payment/return/route.test.ts` inside `describe("payment return", …)`:

```ts
  it("deep-links an app membership buyer to the app's membership screen", async () => {
    mocks.isMembershipOrder.mockReturnValue(true);

    const response = await GET(returnRequest("orderId=order-1&client=app"));

    expect(response.headers.get("location")).toBe(
      "biso://membership?orderId=order-1&status=paid"
    );
  });

  it("sends a cancelled app membership checkout to the membership screen, not the cart", async () => {
    mocks.isMembershipOrder.mockReturnValue(true);
    db.getRow.mockResolvedValue(order({ status: "pending" }));

    const response = await GET(
      returnRequest("orderId=order-1&client=app&cancelled=1")
    );

    expect(response.headers.get("location")).toBe(
      "biso://membership?orderId=order-1&cancelled=1"
    );
  });

  it("reports a failed app membership payment to the membership screen", async () => {
    mocks.isMembershipOrder.mockReturnValue(true);
    db.getRow.mockResolvedValue(order({ status: "failed" }));

    const response = await GET(returnRequest("orderId=order-1&client=app"));

    expect(response.headers.get("location")).toBe(
      "biso://membership?orderId=order-1&status=failed"
    );
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shared && bunx vitest run utils/checkout-return.test.ts`
Run: `cd apps/api && NODE_ENV=test bunx vitest run "src/app/api/payment/[provider]/membership-checkout" src/app/api/payment/return`
Expected: FAIL — no `appMembershipDeepLink`, no `client` support, no gate, and app membership returns go to the shop.

- [ ] **Step 3: Implement**

Append to `packages/shared/utils/checkout-return.ts`:

```ts
/**
 * The deep link that reopens the app on its membership screen after a
 * membership payment, which is where a student sees whether their membership
 * is now active. It carries the order and its outcome; the app still verifies
 * the order itself, since a browser may drop a custom-scheme redirect.
 */
export function appMembershipDeepLink(
  orderId: string,
  outcome: { cancelled?: boolean; status?: string | null } = {}
): string {
  const params = new URLSearchParams({ orderId });
  if (outcome.cancelled) {
    params.set(CHECKOUT_CANCELLED_PARAM, "1");
  } else if (outcome.status) {
    params.set("status", outcome.status);
  }
  return `${APP_SCHEME}://membership?${params.toString()}`;
}
```

In `apps/api/src/app/api/payment/[provider]/membership-checkout/route.ts`:

1. Change the `checkout-return` import to `import { type CheckoutClient, checkoutReturnUrl, isCheckoutClient } from "@repo/shared/utils/checkout-return";` and add:

```ts
import { resolveMembershipGate } from "@repo/shared/utils/membership-gate";
import { getMembershipStatusForStudent } from "@/lib/membership-status-cache";
```

2. Add `client?: string;` to `MembershipCheckoutBody`.

3. Replace `IdentityOutcome` and the success return in `resolveMembershipPurchase`:

```ts
type IdentityOutcome =
  | {
      employeeId: string;
      ok: true;
      plan: MembershipPlan;
      studentId: string;
      studentNumber: number;
    }
  | { ok: false; message: string; status: number };
```

and at the end of `resolveMembershipPurchase`:

```ts
  return {
    employeeId: profile.bi_employee_id,
    ok: true,
    plan,
    studentId: profile.student_id ?? "",
    studentNumber,
  };
```

4. Give both start functions a trailing `client: CheckoutClient` parameter. In `startVippsMembershipCheckout`: `const returnUrl = checkoutReturnUrl(urls.apiBase, orderId, client);`. In `startStripeMembershipCheckout`:

```ts
  const successUrl = checkoutReturnUrl(urls.apiBase, orderId, client);
  // Stripe only accepts http(s) cancel URLs, so an app buyer comes back
  // through the return route with the cancelled marker, as in the shop route.
  const cancelUrl =
    client === "app"
      ? checkoutReturnUrl(urls.apiBase, orderId, client, { cancelled: true })
      : `${urls.webBase}/membership/join?cancelled=true`;
```

5. In `POST`, replace `const { plan } = identity;` with:

```ts
    const { plan } = identity;
    const client = isCheckoutClient(body.client) ? body.client : "web";

    // The join page already refuses these, but this endpoint is reachable
    // directly with any valid JWT — the app calls it — so it applies the same
    // gate: no charge while 24SevenOffice cannot be read (an existing member
    // could pay for cover they already have), and none that would not extend
    // the buyer's cover.
    const status = await getMembershipStatusForStudent(identity.studentNumber);
    const gate = resolveMembershipGate({
      employeeId: identity.employeeId,
      isAuthenticated: true,
      plans: [plan],
      status,
      studentId: identity.studentId,
    });
    if (gate.state === "membership_check_unavailable") {
      return json(
        {
          message:
            "We couldn't verify your membership right now. Try again shortly.",
        },
        503
      );
    }
    if (gate.state !== "eligible") {
      return json(
        { message: "Your membership already covers this period." },
        409
      );
    }
```

and pass `client` to the start calls: `startVippsMembershipCheckout(params, db, urls, client)` / `startStripeMembershipCheckout(params, db, urls, client)`.

In `apps/api/src/app/api/payment/return/route.ts`:
1. Extend the `checkout-return` import with `appMembershipDeepLink`.
2. Replace `redirectToApp` with:

```ts
function redirectToApp(
  status: string | null | undefined,
  orderId: string,
  cancelled: boolean,
  isMembership: boolean
): NextResponse {
  const settled = status === "paid" || status === "authorized";
  // A cancelled Stripe session reconciles to `pending`, so the marker on the
  // cancel URL is honoured only while the order has not actually settled. A
  // Vipps payment the buyer abandons reconciles to `cancelled` outright.
  const abandoned = (cancelled && !settled) || status === "cancelled";

  // A membership buyer never touched the cart: they go back to the membership
  // screen, which re-verifies and shows whether the membership is active.
  if (isMembership) {
    return NextResponse.redirect(
      appMembershipDeepLink(orderId, abandoned ? { cancelled: true } : { status })
    );
  }
  if (abandoned) {
    return NextResponse.redirect(appCartDeepLink(true));
  }
  return NextResponse.redirect(appOrderDeepLink(orderId, status));
}
```

3. In `GET`, compute `const isMembership = isMembershipOrder(current);` after `current` and use it in both branches:

```ts
    const isMembership = isMembershipOrder(current);
    return isAppCheckout
      ? redirectToApp(current.status, orderId, isCancelled, isMembership)
      : redirectForStatus(current.status, orderId, isMembership);
```

(`settleOrderIfPaid` still runs before this, unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shared && bunx vitest run utils/checkout-return.test.ts && bun run check-types`
Run: `cd apps/api && bun run test && bun run check-types`
Expected: PASS — including every pre-existing membership checkout and return test.

- [ ] **Step 5: Commit**

```bash
git add packages/shared/utils/checkout-return.ts packages/shared/utils/checkout-return.test.ts "apps/api/src/app/api/payment/[provider]/membership-checkout" apps/api/src/app/api/payment/return
git commit -m "Let the app buy memberships and come back to its membership screen

Membership checkout accepts client app, so Vipps and Stripe return the
buyer through the return route to biso://membership. The route now also
refuses a purchase that would not extend the buyer's cover, or one it cannot
verify, instead of relying on the website's join page for that.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 15: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run every affected suite**

```bash
cd apps/api && bun run test && bun run check-types
cd ../web && bun run test && bun run check-types
cd ../../packages/shared && bun run test && bun run check-types
cd ../connectors && bun run test && bun run check-types
cd ../api && bun run test
cd ../.. && bunx biome lint apps/api/src apps/web/src packages/shared packages/connectors/src packages/api
```

Expected: every command exits 0. Record the test counts (the baseline before this plan was `apps/api` 23 files / 167 tests).

- [ ] **Step 2: Confirm nothing the plan forbids happened**

Run: `git log --oneline main..HEAD` — one commit per task above, nothing else.
Run: `git diff main --stat -- packages/api/appwrite.config.json` — only the two-line removal of `create("users")`.
Confirm no script was run with `--apply` and nothing was pushed to Appwrite.

- [ ] **Step 3: Hand over the owner steps**

Report the rollout steps from the spec's "Rollout (ordered)" section verbatim to the owner, including: deploy `apps/api` and `apps/web`; run `bun run lockdown:expense-rows` (dry-run, then `-- --apply`); when the app build ships, remove `create("users")` from the `user` table in the console, `appwrite pull tables`, run `bun run lockdown:profile-rows` (dry-run, review, then `-- --apply --clear-unverified-links`), and add the unique index on `user.student_id` once the duplicate report is empty; review 24SevenOffice for customers created under the old id scheme; delete the legacy `vipps_checkout` and `verify_biso_membership` Functions if they exist.
