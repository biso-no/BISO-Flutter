# Expense Feature Map

This maps the web expense/reimbursement system so the same behavior can be rebuilt in a native app.

## Active User-Facing Routes

- `/fs` lists the signed-in user's reimbursements.
  - File: `apps/web/src/app/(protected)/fs/page.tsx`
  - Requires authentication through the protected layout.
  - Shows a hero, empty state, and reimbursement cards.
  - Loads data with `getExpenses()`.
- `/fs/new` creates a reimbursement with the v3 split-view flow.
  - File: `apps/web/src/app/(protected)/fs/new/page.tsx`
  - Requires authentication.
  - Fetches current user/profile and campus/department data before mounting the client flow.
  - Uses `ExpenseSplitView` from `components/expense-v3`.
- `/fs/[id]` shows reimbursement details.
  - File: `apps/web/src/app/(protected)/fs/[id]/page.tsx`
  - Loads one expense by ID with attachments and checks ownership.
  - Shows status, total, allocation, bank account, optional event/prepayment/invoice, and receipt links.
- `/profile` includes the account/profile form used by expense submission.
  - File: `apps/web/src/app/(protected)/profile/page.tsx`
  - Reuses `apps/web/src/app/expenses/profile/profile-form.tsx`.

## Current Creation Flow

The active creation experience is `ExpenseSplitView`, not the older `components/expense` wizard.

1. Assignment gate
   - User must select campus and department before upload.
   - Campus list includes national campus and departments.
   - Department list filters out inactive departments.
   - Purpose: assignment context improves AI-generated accounting summary.

2. Receipt wallet
   - Left pane on desktop, tab on mobile.
   - Accepts image and PDF files.
   - Supports multi-file upload and drag/drop.
   - Shows thumbnails for images and file icon for PDFs.
   - Shows upload/processing progress and allows removal.
   - Bank statements can appear as child items linked under a receipt.

3. Upload and OCR
   - File is uploaded to Appwrite storage bucket `expenses` using `uploadExpenseAttachment`.
   - Then the same file is sent to API OCR endpoint `/api/expenses/ocr`.
   - The OCR step has a 30 second timeout in the web client.
   - Client states: `uploading`, `processing`, `analyzing`, `ready`, `error`, `editing`.
   - After OCR, the UI adds a short artificial analyzing delay for a generative feel.

4. Receipt editing
   - User can open a receipt detail preview.
   - Editable fields: vendor, date, amount, original foreign amount, description.
   - Image receipts render as previews; PDFs show "No preview available" in the detail pane.
   - OCR-derived values can be manually corrected before submission.

5. Foreign currency handling
   - OCR detects non-NOK currency.
   - API converts to NOK using historical exchange rates.
   - UI shows an amber warning that the NOK amount is estimated.
   - User can upload a bank statement for exact NOK verification.
   - Bank statement OCR can update the NOK amount.
   - Multi-file upload attempts to auto-link bank statements to receipts by vendor overlap.

6. Report summary
   - Right pane shows a paper-like expense report.
   - Includes user identity, bank account, selected cost allocation, description, receipt rows, total, and submit button.
   - When all receipts are ready and assignment is selected, the app calls `/api/expenses/summary`.
   - The returned summary populates the editable description field.

7. Profile completion
   - Submission requires profile fields: name, email, phone, bank account, address, zip, city.
   - Missing profile data shows an amber banner inside the report.
   - The banner opens a modal that updates only the missing fields.
   - The submit readiness check currently requires `profile.bank_account`; the API also checks name, phone, email, and bank account before generating the PDF.

8. Submit
   - Submit posts to `/api/expenses/submit`.
   - Payload includes campus ID, department ID, bank account, description, total, prepayment amount, event name, and attachment rows.
   - If the local draft was already saved, the submit payload includes `expenseId` and promotes the existing draft row instead of creating a duplicate.
   - On success, the app routes to `/fs/[expenseId]`.

9. Save draft
   - Save draft posts to `/api/expenses/draft`.
   - The row is saved with `status: draft`.
   - Saving a draft does not generate a PDF, send emails, or notify finance.
   - The web client stores the returned draft ID so later draft saves update the same row.

## API Surface For Native App

The API app supports JWT authentication through `Authorization: Bearer <jwt>`.

- `POST /api/expenses/ocr`
  - Body: `multipart/form-data` with `file`.
  - Optional query: `purpose=receipt`, `purpose=bank-statement`, or omitted for auto classification.
  - Auth: Appwrite JWT or session cookie.
  - Accepted file types: `image/jpeg`, `image/png`, `image/webp`, `application/pdf`.
  - Max file size: 10 MB.
  - Response:
    - `success: true`
    - `data.address`
    - `data.category`: `meal`, `travel`, `accommodation`, `supplies`, `event-materials`, `fee`, `other`
    - `data.city`
    - `data.country`
    - `data.documentType`: `receipt` or `bank-statement`
    - `data.description`
    - `data.amount`
    - `data.currency`
    - `data.date`
    - `data.purchaseContext`
    - `data.vendor`
    - `data.amountInNok`
    - `data.exchangeRate`
    - `method`: `vision` or `pdf`

- `POST /api/expenses/summary`
  - Body:
    ```json
    {
      "assignment": {
        "campusId": "string",
        "campusName": "string",
        "departmentId": "string",
        "departmentName": "string"
      },
      "receipts": [
        {
          "amount": 123,
          "category": "meal",
          "city": "Oslo",
          "country": "Norway",
          "currency": "NOK",
          "date": "2026-04-28",
          "description": "Lunch receipt",
          "documentType": "receipt",
          "purchaseContext": "Lunch receipt, Oslo",
          "vendor": "Vendor"
        }
      ]
    }
    ```
  - Legacy body `{ "descriptions": ["..."] }` is still accepted.
  - Response: `{ "success": true, "summary": "..." }`.

- `POST /api/expenses/submit`
  - Body:
    ```json
    {
      "campus": "campusId",
      "department": "departmentId",
      "bank_account": "1234 56 78901",
      "description": "Accounting summary",
      "total": 1234.5,
      "prepayment_amount": 0,
      "eventName": "",
      "expenseAttachments": [
        {
          "date": "2026-04-28",
          "url": "appwriteFileId",
          "amount": 1234.5,
          "description": "Receipt description",
          "type": "image/jpeg"
        }
      ]
    }
    ```
  - Creates an expense as `draft`.
  - Fetches the expanded expense.
  - Generates a five-digit reimbursement number from the Appwrite row sequence.
  - Generates a PDF cover sheet named `refusjon-{number}.pdf`.
  - Uploads the PDF to the `expenses` storage bucket.
  - Emails the user and `invoice` recipient with the PDF and uploaded receipt attachments.
  - Updates status to `pending`.
  - Response includes `success`, `fetchedExpense`, and `reimbursementNumber`.

- `POST /api/expenses/draft`
  - Body uses the same base payload as submit.
  - Optional `expenseId` updates an existing draft owned by the current user.
  - Creates or updates an Appwrite `expense` row with `status: draft`.
  - Does not generate reimbursement PDF.
  - Does not send emails.
  - Does not move the expense to `pending`.
  - Response: `{ "success": true, "draft": { "$id": "..." } }`.

## Storage And Database

Storage bucket:

- `expenses`
  - Stores receipt uploads, bank statements, and generated reimbursement PDFs.
  - Public/view URL format used by web:
    `APPWRITE_ENDPOINT/storage/buckets/expenses/files/{fileId}/view?project={projectId}`

Appwrite table `expense`:

- Permissions include create for users, read for admin and finance teams.
- Row security is enabled.
- Important columns:
  - `user`: relationship to `user`
  - `campus`: campus ID string
  - `department`: department ID string
  - `bank_account`: required string
  - `description`: optional string
  - `expenseAttachments`: one-to-many relationship to `expense_attachments`
  - `total`: required number
  - `prepayment_amount`: optional number
  - `status`: `draft`, `pending`, `success`, `submitted`, `rejected`
  - `invoice_id`: optional number
  - `userId`: required string
  - `eventName`: optional string
  - `departmentRel`: relationship to departments
  - `campusRel`: relationship to campus
- Indexes:
  - `status`
  - full-text `description`
  - `userId`

Appwrite table `expense_attachments`:

- Permissions include create for users.
- Row security is enabled.
- Columns:
  - `date`: optional datetime
  - `url`: optional string; stores the Appwrite file ID
  - `amount`: optional number
  - `description`: optional string
  - `type`: required string; stores MIME type

## Status Mapping

Web labels and colors:

- `draft`: Draft, muted gray, clock icon
- `pending`: Pending, yellow, clock icon
- `success`: Approved, green, check icon
- `submitted`: Submitted, blue, check icon
- `rejected`: Rejected, red, x icon

Admin translation files mention `approved` and `paid`, but the shared generated enum does not include those values. Native should use the generated enum above unless the backend schema is changed.

## Design And Interaction Patterns

General brand:

- BISO blue: `#3DA9E0`, represented as `--brand`.
- BISO dark navy: `#001731`, represented as `--brand-dark`.
- BISO yellow accent: `#F7D64A`, represented as `--brand-accent`.
- Hero overlays use dark navy plus blue gradients.
- Main font setup uses local Museo Sans and Inter.
- Icons are from Lucide in the web app.

Expense list/detail design:

- Marketing-like hero image with dark/blue brand overlay.
- White cards over `from-section to-background` page background.
- Cards use shadows, brand icon accents, and status badges.
- Empty state uses a large file icon, short helper copy, and primary action.

Expense creation design:

- Full-height operational tool rather than a landing page.
- Desktop layout:
  - Left receipt wallet pane, fixed width around 350-400 px.
  - Right report/receipt detail pane.
  - No public nav around the creation tool.
- Mobile layout:
  - Top segmented tab between `Receipts` and `Report`.
  - Selecting a receipt switches to report/detail view.
- Assignment gate:
  - Centered modal-like card on muted background.
  - Building icon, short explanation, campus select, department combobox, continue button.
- Receipt wallet:
  - Card-like receipt items with thumbnails.
  - Progress bar at bottom while upload/OCR is active.
  - Child receipt indentation for linked bank statements.
- Report:
  - Paper document visual with rounded corners and large shadow.
  - Header contains title, date, draft number.
  - User/bank info on the left, cost allocation on the right.
  - Receipt rows in a table.
  - Sticky table header.
  - Footer contains count, total, and submit button.
- Receipt detail:
  - Image preview in aspect 3:4 frame.
  - Animated scan line while OCR is processing.
  - "AI Extracted" or "Analyzing receipt..." pill.
  - Editable form fields with icons and skeleton loaders.
- Warnings:
  - Amber profile-completion banner.
  - Amber foreign-currency warning.
  - Green confirmation when a bank statement is attached.

## Older Or Unwired Expense Code

- `apps/web/src/components/expense` contains an older step wizard, card, skeleton, upload/profile/campus steps, and summary dialog.
- `apps/web/src/components/expense-v2` contains another experimental receipt canvas flow.
- The active `/fs/new` page imports `components/expense-v3/expense-split-view`.
- `apps/web/src/app/api/expense/generate-description/route.ts` is an older singular route that calls an Appwrite function. The active v3 flow uses `/api/expenses/summary` from the API app.
- `apps/admin` contains role access and i18n strings for expenses, but no implemented admin expense route was found in `apps/admin/src/app`.

## Native App Implementation Checklist

1. Authentication
   - Use Appwrite auth.
   - Generate or obtain an Appwrite JWT for API calls.
   - Send `Authorization: Bearer <jwt>` to API endpoints.

2. Data loading
   - Load current profile.
   - Load campuses with departments.
   - Load user's expenses by `userId`, ordered descending by created date.
   - Load one expense with attachment expansion for details.

3. New expense state
   - Mirror the v3 store shape: phase, receipts, selected receipt, assignment, profile, description, summary loading, submission error.
   - Treat receipt rows as local draft objects until submit.
   - Keep bank statements as linked child rows or as metadata on the parent receipt.

4. File pipeline
   - Pick or capture image/PDF.
   - Upload to Appwrite storage bucket `expenses`.
   - POST file to `/api/expenses/ocr`.
   - Convert OCR response into a local receipt row.
   - Allow manual edits.
   - For foreign currency, prompt for bank statement and rerun OCR with `purpose=bank-statement`.

5. Summary pipeline
   - When all receipts are ready and assignment is complete, call `/api/expenses/summary`.
   - Let user edit the generated description.
   - Avoid regenerating repeatedly for the same receipt/assignment snapshot.

6. Submission pipeline
   - Validate required profile fields.
   - Validate at least one ready receipt, assignment, bank account, and description.
   - POST the submit payload.
   - Include `expenseId` when submitting a previously saved draft.
   - Navigate to detail screen on success.

7. Draft pipeline
   - Allow saving once assignment and bank account are available.
   - Wait for active receipt upload/OCR work to finish before saving.
   - Store the returned draft ID locally.
   - Reuse the draft ID for subsequent draft saves and final submit.
   - Do not treat a draft save as a finance submission.

8. Native screens
   - Reimbursements list.
   - Reimbursement detail.
   - Assignment selection.
   - Receipt wallet/upload list.
   - Expense report review.
   - Receipt detail edit.
   - Profile completion modal/sheet.

9. Native-specific improvements worth considering
   - Add camera scan as a primary receipt input.
   - Persist draft receipts locally during upload/OCR.
   - Add retry per failed receipt.
   - Make PDF preview available if the native stack supports it.
   - Use a bottom sheet for receipt detail on phones.
   - Show upload/OCR progress as explicit per-file stages.
