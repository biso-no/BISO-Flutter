# Appwrite Content Migration — Design

**Date:** 2026-09-07
**Status:** Approved for planning
**Scope:** Move events, jobs and webshop products off `api.biso.no` onto direct Appwrite reads; support product variations and custom fields; audit consuming screens.

## Goal

The app currently fetches events, jobs and webshop products over HTTP from `api.biso.no`
(plus a legacy WordPress path for events). That API returns HTTP 500 for these endpoints,
and the models are shaped for WordPress/WooCommerce payloads that no longer reflect the
Appwrite schema.

Fetch this content directly from Appwrite using the `appwrite` Dart SDK, reshape the models
to the real schema, and make product variations and custom fields work.

**Expenses stay on `api.biso.no`.** They are explicitly out of scope and must not be touched.

## Verified ground truth

All of the following was verified against **live** Appwrite (`https://appwrite.biso.no/v1`,
project `biso`, database `app`) on 2026-09-07, not inferred from the schema export.

| Table | Published rows | Localized content via | Notes |
|---|---|---|---|
| `events` | 3 | `translation_refs` | `image` is a full URL |
| `jobs` | 260 | `translations` | rich fields only inside `metadata` JSON |
| `webshop_products` | 57 | `translation_refs` | has `variations` + `custom_fields` |

Additional verified facts:

1. **Public read works.** Published rows carry `read("any")`; no session is required.
   Draft rows return `$permissions: []` and are genuinely unreadable publicly, so filtering
   on `status == 'published'` is both correct and necessary.

2. **No title/description columns exist** on `events`, `jobs` or `webshop_products`. All
   localized text lives in `content_translations`, reachable either through the relationship
   or through the generic `content_id` + `content_type` pair.

3. **Nested relationships require explicit selection.** They are absent from the default
   response and appear only with e.g. `Query.select(['*', 'translation_refs.*'])`.

4. **Relationship-attribute queries work, and filter parent rows.**
   `Query.equal('translation_refs.title', 'Karrieredagene')` returned exactly 1 row, and a
   bogus value returned 0 — so the filter is genuinely applied, not silently ignored.
   Critically, it does **not** prune the nested child array: filtering on
   `translation_refs.locale` still returns every locale nested.

5. **`contains` works on relationship attributes; `search` does not.**
   `contains('translation_refs.title', 'dagene')` returned 1 row.
   `search(...)` fails with `requires a fulltext index`.

6. **Image columns are inconsistent in live data.** The same `images` column holds bare file
   IDs (`"6a99004100362c968d1e"`) and full URLs
   (`"https://appwrite.biso.no/v1/storage/buckets/media/files/.../view?project=biso"`).

7. **`webshop_products.custom_fields` exists** as a parent-side relationship to
   `product_custom_fields` (verified by probing; sibling names like `customFields` error with
   `Attribute not found in schema`). The local `appwrite.config.json` export predates this
   column and is stale.

8. **`product_custom_fields` has 0 rows.** The read path can be built and unit-tested against
   synthetic data, but cannot be validated against real content until the backend populates it.

9. **`jobs.metadata`** is a JSON string containing only
   `{auto_screen, auto_translate, company, employment_type, location, tags}`.
   `content_translations.additional_fields` is null in sampled rows.

## Design

### 1. Shared content layer

Built first, because all three services need it. Three small, independently testable units.

**`ContentTranslation` model** — parses one `content_translations` row: `locale`, `title`,
`description` (HTML), `short_description`, `additional_fields`, `content_type`, `content_id`.

**Locale resolver** — given a list of translations and a target locale, returns the best match.

Fallback chain: `requested locale → 'no' → 'en' → first available → empty strings`.

It never throws and never yields a blank title when *any* translation exists. Locale selection
is deliberately client-side: filtering by `translation_refs.locale` server-side would silently
drop rows that lack that locale (see finding 4), which would hide English-only content from
Norwegian users.

**Appwrite image normalizer** — accepts a bare file ID or a full URL and returns a usable URL
against the `media` bucket. Required by finding 6. Pure function, trivially testable.

### 2. Query shape

Every list read converges on one shape:

```dart
db.listRows(
  databaseId: AppConstants.databaseId,
  tableId: 'events',
  queries: [
    Query.equal('status', 'published'),
    Query.equal('campus_id', campusId),
    Query.select(['*', 'translation_refs.*']),
    Query.orderAsc('start_date'),
    Query.limit(limit),
    Query.offset(offset),
  ],
);
```

One round trip, translations nested. Jobs use `translations.*`; webshop uses
`translation_refs.*`, `variations.*`, `custom_fields.*`.

**Search moves server-side** using `contains` on the translated title, replacing today's
client-side filtering.

### 3. Deletions

Per decision, the old paths are removed rather than kept as fallback:

- `EventService.getWordPressEvents`, `EventService.getFunctionEvents`, and the WordPress
  constants they rely on.
- The HTTP branches in `JobService` and `WebshopService`.

Appwrite becomes the single source for this content. Rationale: two live data paths double
the maintenance surface and make failures ambiguous, and the HTTP path is currently failing
anyway.

### 4. Model reshaping

`EventModel`, `JobModel` and `WebshopProduct` carry many fields with **no corresponding
column** in Appwrite. `JobModel` alone declares `requirements`, `responsibilities`, `skills`,
`salary`, `benefits`, `maxApplicants` and `currentApplicants`; the real `metadata` holds only
six keys (finding 9).

Each model shrinks to what the schema actually provides. Fields that could only ever be empty
are removed rather than retained as permanently-null decoration.

`WebshopProduct` is a full rewrite: it is currently WooCommerce-shaped (`int id`, prices as
`String`, `meta_data`, `permalink`) and shares nothing with the Appwrite row beyond intent.
It becomes: `String` id, `double` `regularPrice`/`memberPrice`, `memberOnly`, normalized
images, `variations`, `customFields`.

These are breaking changes. The three existing model tests
(`test/data/models/{event,job,webshop_product}_model_test.dart`) are WordPress/Woo-shaped and
are rewritten against captured real Appwrite payloads.

### 5. Variations and custom fields

**`ProductVariation`** — `name`, `regularPrice`, `memberPrice`, `stock`, `sku`, `sortOrder`,
`enabled`. Filtered to enabled, ordered by `sortOrder`. A product with variations prices from
the selected variation rather than the product.

**`ProductCustomField`** — `fieldKey`, `label`, `type` (`text` / `textarea` / `number` /
`select` / `email`), `isRequired`, `placeholder`, `helpText`, `options`. Renders a typed form
honouring `isRequired`, serializing to the shape `order_items.custom_fields_json` expects.

### 6. Member pricing

Show `memberPrice` when the user has an active membership (via the existing
`membership_service`), otherwise `regularPrice`. Badge `member_only` items. Where a variation
is selected, its prices win over the product's.

### 7. Screen audit

Last, once the data layer is trustworthy: walk home, events, marketplace, webshop, jobs and
the detail screens on the simulator, and fix real consumption bugs found there.

## Sequencing

Each step lands and is verified before the next begins.

1. Shared content layer (translations, locale resolver, image normalization)
2. Events migration
3. Jobs migration
4. Webshop products migration, including variations and custom fields
5. Screen audit

## Testing

- Unit tests for the locale resolver's full fallback chain, including the empty case.
- Unit tests for image normalization covering both bare-ID and full-URL inputs.
- Model parsing tests built from **real captured Appwrite payloads**, replacing the existing
  WordPress/Woo-shaped tests.
- Custom fields tested against synthetic data, with the gap in finding 8 recorded.
- Simulator verification per step; the app must build and run between steps.

## Risks and open items

| Item | Impact | Handling |
|---|---|---|
| `product_custom_fields` is empty | Cannot validate against real data | Build to schema, unit-test synthetically, flag for backend follow-up |
| `appwrite.config.json` is stale | Schema drift vs. reality | Treat live Appwrite as source of truth; re-pull the export |
| Only 3 published events | Thin verification surface for events | Also exercise jobs (260) and webshop (57) |
| No fulltext index on translated titles | `search` unavailable | Use `contains`; add index later if ranked search is wanted |
| Model shrinkage is breaking | Consuming screens may reference removed fields | Compiler surfaces every site; step 5 audit covers behaviour |

## Out of scope

- Expenses — remain on `api.biso.no`.
- Orders, payments and checkout flow.
- The marketplace `products` table, which is self-contained and already reads from Appwrite.
