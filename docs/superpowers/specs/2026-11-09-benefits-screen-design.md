# Member benefits screen in the app

Date: 2026-11-09. Status: design agreed in conversation with mockups, and the
builder check is answered. Waiting for the owner to approve this document.

Where the mockups and this document differ, **this document wins**. The
Spotlight number is white with a sun bar, not yellow. Non-members see "Bare
for medlemmer" on grid cards. "Se priser" is dropped.

Mockups the owner approved (open them with the brainstorm server, or read the
HTML):
`/Users/markus/Documents/dev/BISO-Flutter/.superpowers/brainstorm/40176-1794227156/content/`

| File | What it shows |
|---|---|
| `overview-v2.html` | The benefits screen: member and non-member side by side. **Use the "1 · Spotlight" style.** |
| `detail-page.html` | The deal page in three states |
| `entry-points.html` | The four in-app entry points (all chosen) |
| `overview-layout.html` | Earlier round, kept for reference only: layout A won, B's top card was moved into A |

## Why

Today a student can see benefits in only two places in the app: a plain
"Dine fordeler" list on the member pass, and short benefit sections on a
campus page. Neither shows what membership actually gets you. The website
has a full benefits page, the app does not.

The screen has two jobs at once:

- **Members** come to find a deal they can use today, and use it.
- **Students who haven't joined** see what they would get and can sign up
  from the same screen.

The owner wants it to look great and to follow the app's design and BISO's
brand colours.

## Goals

1. A new benefits screen built from "layout A" with "layout B"'s top card:
   a large title, a navy top card, an "Utvalgt" row in Spotlight style, a
   grid of every deal with category filters, the non-discount perks as
   checklists, and a "Bli medlem" bar for non-members.
2. A full deal page that replaces today's benefit sheet everywhere.
3. Five ways in: Home, Explore, Profile, the member pass, and the "Bli
   medlem" page.
4. Works the same for members, non-members and signed-out visitors, and
   never tells someone they aren't a member when the app simply couldn't
   check.

## Non-goals

- No changes to the website, the admin or `apps/api`. The public
  `GET /api/benefits` list and the existing reveal call already return
  everything this needs.
- No Appwrite schema change, no data migration.
- No search, saved/favourite deals, sharing, maps or opening hours.
- No push notifications about new deals.
- No usage tracking (`benefit_interactions`). Worth doing later, not now.
- The campus page's benefit sections stay as they are.

## Anti-goals (would make this a failure even if it works)

- **A code leaks.** Codes and links are still only fetched by the existing
  reveal call when a member taps. They are never cached, logged, put in a
  provider or kept after the page closes. Same rules as
  `benefit_detail_sheet.dart` today.
- **Telling a member they aren't one.** A failed or pending membership check
  must never show "Bli medlem" or "Bare for medlemmer" as if it were a fact
  (same rule as the current sheet's `_Standing.outage` / `checking`).
- **A non-member thinks they can use a deal.** On the benefits screen and
  the deal page, every member deal is clearly marked "for members only" to
  someone who hasn't joined or is signed out (see the grid's claim line and
  the deal page's panel). Home's "Fordeler for deg" cards carry no marker.
  They open the deal page, which says it.
- **Off-brand.** Orange-gold everywhere, sky blue as text on white, or yellow
  used as text. See "Colour" below.
- **Copy that reads as translated English or self-praise** (see the brand
  copy rules: no "ledende", no idioms translated word for word).

## What exists today (build on it)

- `lib/data/models/campus_benefit.dart`: `CampusBenefit`, `BenefitText`,
  `BenefitPartner`, sections and redemption types.
- `lib/data/services/benefits_api_client.dart`: `fetchBenefits({campusId})`
  (public, no token) and `reveal(benefitId)`.
- `lib/providers/benefits/benefits_providers.dart`: `campusBenefitsProvider`
  (auto-disposed, so every visit refetches).
- `lib/presentation/widgets/benefits/benefit_detail_sheet.dart`: the sheet,
  including the standing/reveal state machine, copy-to-clipboard, link
  opening and "Vis medlemskortet" via `showPassPresentation`. **This logic
  moves into the new deal page.** The sheet itself goes away.
- `lib/presentation/widgets/benefits/benefit_list_section.dart`: "Dine
  fordeler" on the member pass.
- `filterCampusProvider` and the campus switcher modal on Home
  (`_CampusSwitcherModal` in `premium_home_screen.dart`).
- Design system: `BisoPage` (header, scroll edge, over-image mode),
  `BisoSection`, `BisoListGroup`, `BisoListRow`, `BisoIconTile`,
  `BisoEmptyState`, `BisoErrorState`, `BisoSkeleton`, `BisoPalette`,
  `BisoAccent`, `BisoTypography`. `test/presentation/design_rules_test.dart`
  enforces the rules, so new files go into its `migratedFiles` list.

The API already returns, per benefit: `id`, `campusId` (`"5"` = all of BISO),
`section`, `category`, `title`, `description`, `terms`, `imageUrl`,
`isFeatured`, `partner {id, name, logoUrl, websiteUrl}`, `publishEnd`,
`redemptionType`, `sortOrder` and `createdAt`. The app model doesn't read
`createdAt` yet and needs to, for "Nytt". The list comes back in board order:
the campus's own benefits first, then all-of-BISO ones.

## What the real data looks like (design for this)

Checked against the live API on 2026-11-09:

- Trondheim and Bergen have deals with images. Oslo and Stavanger have mostly
  text-only deals.
- Many "images" are partner **logos** (square or wide, sometimes on white),
  not photos. Partner records with a logo are rare.
- Descriptions are often one short line, and some are empty.
- Titles are inconsistent. Some are the partner name ("GRAFFI GRILL"), some
  the deal ("20% Rabatt på Los Tacos").
- Nothing is marked featured (`isFeatured`, "Vis først" in the admin) yet.
- No live deal uses a code. Every deal is "show your card" (`onsite`) or has
  nothing to claim (`none`).
- The `career`, `social` and `safety` sections are almost all title-only one-liners.
- The `business` section is for companies, not students.

So outside Trondheim, the grid will mostly show the navy no-image tiles until
editors add pictures and categories. The design has to look deliberate in
that state, not broken. Adding images and categories is content work for the
Branding Committee, not part of this build. Mention it in the handover.

## Membership standing (one mapping for the whole feature)

The screen, the deal page and the sticky bar all use one standing, derived
from `memberPassProvider` (as the sheet does today) plus
`membershipOverviewProvider` for an upcoming start date (as the member pass
screen does). It mirrors how `member_pass_screen.dart` already treats each
case:

| Standing | When | Treated as |
|---|---|---|
| Member | pass `active` | Member |
| Upcoming | `notMember`/`expired` **and** an upcoming membership exists | Paid, not started. Never shown "Bli medlem". |
| Needs BI | `noBiIdentity` | Can't be checked until they sign in with BI. Never shown "Bli medlem". |
| Not a member | `notMember` / `expired`, no upcoming membership | Non-member |
| Signed out | `signedOut` | Signed out |
| Checking | `loading` | Neutral: nothing that implies either answer |
| Check failed | `reconnect` / `unavailable` | Neutral, with retry where there's an action |

What each one shows:

- **Upcoming:** the top card shows the member text ("fordeler er dine i
  {campus}") and a member row with the seal, "Medlemskapet ditt starter
  {date}" (the existing `membershipStartsOn`) and no "Vis kort" button. No
  sticky bar. On the deal page, the panel says "Medlemskapet ditt starter
  {date}. Da kan du bruke tilbudet." with no button.
- **Needs BI:** the top card shows the neutral text (no pill), plus a row
  "Logg inn med BI-studentkontoen din" with the existing "Logg inn med BI"
  action (the same flow as the member pass's `_continueWithBi`). No sticky
  bar. On the deal page, the panel uses the existing
  `membershipNeedsBiLinkTitle`/`Body`/`Cta`.

## Which campus

The screen keeps **its own campus**. It does not write to
`filterCampusProvider`:

- Opened from the **member pass** or **Profile**, it starts on the
  student's profile campus (`authState.user.campusId`, or all of BISO only
  when that's unset). That's the same list "Dine fordeler" and the Profile
  row count.
- Opened from **Home**, **Explore** or the **"Bli medlem" page**, it starts
  on `filterCampusProvider`.
- The campus link on the screen switches only this screen's campus. Home is
  left alone.
- The deal page gets the campus the list was loaded for, and uses it for the
  "{N} andre fordeler i {campus}" text.
- `campusBenefitsProvider(campusId)` is still one fetch per campus per
  visit, shared by whichever entry point uses the same campus.

## The benefits screen

Route: `/explore/benefits` (inside the Explore branch, so the tab bar shows
Utforsk), taking an optional starting campus. A `BisoPage` with a large
title.

From top to bottom:

### 1. Title and campus

- Large Museo title **"Fordeler"** / "Benefits".
- Under it, in muted text: "For BISO-medlemmer i **{campus}** ⌄" ("For BISO
  members in {campus}"). The campus name is a link (BISO blue) that opens the
  app's existing campus switcher (lift `_CampusSwitcherModal` out of
  `premium_home_screen.dart` so both screens can use it). Switching changes
  only this screen (see "Which campus").
- Benefits shown = that campus's benefits plus all-of-BISO ones, as the API
  returns them for `?campus={id}`.

### 2. The top card (from layout B)

A navy card, 24 pt radius, a faint sky-blue ring in the top-right corner and
one small sun-yellow dot:

- A large Museo number in sky blue: how many benefits are on this screen
  (every deal in the grid plus every perk in "Mer enn rabatter").
- Under it, white text. A non-member sees "fordeler venter på deg som
  BISO-medlem i {campus}". A member sees "fordeler er dine i {campus}".
- A row of up to five round partner images (the partner logo if there is one,
  else the deal image), overlapping, with "+ N til" after them. If there are
  no images, the row is left out.
- **Non-member:** a sky-blue pill "Bli medlem" with navy text. It opens
  `/profile/membership`.
- **Member:** a raised navy row with a sun-yellow seal tile, "Du er medlem",
  "Gyldig til {date}" and a white "Vis kort" pill that opens
  `showPassPresentation`.
- **Signed out:** as a non-member, but the pill says "Logg inn" and goes to
  login.
- **Upcoming / Needs BI:** see "Membership standing" above.
- **Checking or the check failed:** the number and a neutral line ("fordeler
  for BISO-medlemmer i {campus}"). No pill, no member row, and nothing that
  says or implies "not a member".

### 3. "Utvalgt" (Spotlight)

The section title is "Utvalgt" ("Featured"). Below it is a horizontal,
snapping carousel of large cards, one at a time, with page dots under it.

Each card is 236 pt tall with a 22 pt radius. The deal image fills it, with
a navy gradient from the bottom. On the card:

- Top-left, a dark chip giving the **reason** the deal is there (below).
- Bottom-left, the title (20 pt, 600, white) and the first line or two of
  the description.
- Bottom-right, the discount in large Museo **white** ("15 %") with a short
  sun-yellow bar under it (the same marker as on the deal page), if one is
  found (see "Discount text"). The owner chose this over the mockup's yellow
  number, because yellow must not be used as text.

**Which deals, and why they're there.** Only `member`-section deals. Take, in
this order, and stop at 5:

1. `isFeatured` (the admin's "Vis først"): reason **"Valgt av BISO"** (star icon).
2. `publishEnd` within the next 30 days: reason **"Slutter {d. MMM}"** (clock icon).
3. `createdAt` within the last 14 days: reason **"Nytt"** (sparkle icon).

A deal that matches more than one rule gets the first reason and appears
once. Within each rule, keep the API order. If nothing matches, the whole
section is hidden and the page goes from the top card straight to "Alle
tilbud".

Logos under text: because many images are logos, use a gradient strong
enough that white text stays readable on a light logo (aim for at least
4.5:1 behind the text area). A deal with no image gets the navy fallback
(below) instead of a photo.

No auto-advance. The student swipes.

### 4. "Alle tilbud"

- Section title "Alle tilbud" with the count after it in muted text.
- A horizontal row of filter chips: "Alle" first, then one chip per category
  that actually has deals on this screen, with the category's icon. Labels
  come from the shared catalogue (`packages/shared/utils/benefit-catalog.ts`
  in BISO-Sites): Mat og drikke, Trening og helse, Uteliv, Shopping, Reise,
  Programvare, Arrangementer, Annet. The selected chip is navy with white
  text, the rest are white with a hairline. If fewer than two categories have
  deals (true for Oslo, Bergen and Stavanger today, where nearly everything is
  "Annet"), leave the chip row out.
- A two-column grid (`SliverGrid`, lazy) of every `member`-section deal, in
  API order:
  - The image on top at 4:3, cover crop.
  - A sun-yellow badge top-left with the discount text if one is found
    ("−25 %", "Gratis", "150 kr").
  - Title (15 pt, 600), then the description, two lines at most, muted.
  - A small muted line at the bottom saying how you claim it. For `onsite`:
    "Vis kortet i kassen" with a card icon. For `code`: "Rabattkode". For
    `link`: "Lenke". For `none`: no line.
  - **Not a member or signed out:** that line is replaced on every card by a
    lock icon and "Bare for medlemmer", so nobody reads "Vis kortet i
    kassen" as something they can do now. Upcoming, Needs BI, checking and
    check-failed keep the normal claim line, which says nothing about the
    viewer.
  - Tapping opens the deal page.
- **No image:** a navy tile (navy gradient) with the discount number in large
  Museo sky blue, or the category's icon in sky blue if there is no number.

### 5. "Mer enn rabatter"

Section title "Mer enn rabatter" ("More than discounts"). Then, for each of
`career`, `social` and `safety` that has items, in that order:

- A small subheading with a navy tile (sky glyph) and the section's catalogue
  name: "Karrierefordeler", "Sosialt nettverk", "Trygghet og støtte".
- A `BisoListGroup` of rows. Each row has a sky-blue round tick (navy check)
  and the title. If there is a description, it shows under the title, muted,
  two lines at most. The rows can't be tapped.

The `business` section never shows in the app.

### 6. Sticky "Bli medlem" bar (non-members only)

A glass bar floating above the tab bar: "Alt dette får du som medlem" and
under it "{N} fordeler i {campus}", plus a navy "Bli medlem" pill. It slides
in only once the top card has scrolled out of view, so two sign-up buttons
are never on screen together. Not shown to members, or while checking or
after a failed check. Signed out: the pill says "Logg inn".

### States

- **Loading:** the title and campus line, then skeletons (one card-sized
  block, then grid cards).
- **Error:** `BisoErrorState` with retry.
- **Old API without the route** (`notDeployed`): the screen shows an empty
  state, and the entry points (below) are hidden.
- **No benefits for this campus at all:** `BisoEmptyState` (gift icon) with
  the existing "Ingen fordeler her ennå." and the campus link so the student
  can switch.
- **No member deals but some perks:** the top card and "Mer enn rabatter"
  only.

## The deal page

Route: `/explore/benefits/:benefitId`. `BisoPage` with `overImage: true` and
`largeTitle: false`: the compact title (the deal title) fades in once the
picture has scrolled away. Pass the `CampusBenefit` in as `extra` when it is
already loaded. If it isn't (a deep link, or the app was restored), look it up
by id from the campus's list, and show "Denne fordelen er ikke lenger
tilgjengelig." if it's gone.

From top to bottom:

1. **Picture**, full width, about 300 pt tall, cover crop. If there's no
   image, a navy block with the discount number or category icon in sky
   blue, same as the grid fallback.
2. **Chips:** the category (icon and name, neutral), plus the Utvalgt reason
   if it has one (BISO-blue tint).
3. **Title** (26 pt, 700).
4. **Where:** the partner's logo and name if there is a partner, else the
   campus name with a pin icon (or "Hele BISO" for all-of-BISO benefits).
5. **The deal in large type:** if a discount was found, a large Museo navy
   number ("25 %") with a short sun-yellow bar under it, and "rabatt for
   medlemmer" beside it. For "Gratis" and "150 kr", show that value with no
   "rabatt". If nothing was found, leave this row out.
6. **The action**, which depends on who is looking and how the deal is
   claimed (below).
7. **"Om tilbudet"**: the description in full, rendered the same way the
   sheet renders it today (HTML / Plate / plain text). Leave the heading out
   if there's no description.
8. **Info group** (`BisoListGroup`, neutral icon tiles):
   - "Gyldig": "Til {date}" if `publishEnd`, else "Til videre".
   - "Nettside": the partner's website, opens externally. Only if there is one.
   - "Vilkår": expands to show the terms. Only if there are terms.
9. **"Mer innen {kategori}"**: a horizontal row of up to 8 other deals from
   the same category (square image, badge, title, one line). Left out if
   there are none.

### The action panel

The standing/reveal logic from `benefit_detail_sheet.dart` carries over
unchanged. Only the look changes.

| Who | `onsite` | `code` / `link` | `none` |
|---|---|---|---|
| Member | White card: a navy tile with a card icon, "Vis medlemskortet i kassen", "Vis kortet før du betaler, så får du rabatten." and a full-width navy pill "Vis medlemskortet" (opens `showPassPresentation`). | A navy pill "Vis rabattkode" / "Åpne tilbudet". After the reveal, a navy card: "Din rabattkode", the code large in monospace on raised navy, a sky "Kopier" pill and a translucent "Til butikken" pill (if the partner has a website), and "Koden gjelder bare for BISO-medlemmer." For links, the reveal opens the link, as today. | A quiet white card with the seal tile and "Du har denne fordelen som medlem." No button. |
| Upcoming | "Medlemskapet ditt starter {date}. Da kan du bruke tilbudet." No button. | Same | Same |
| Needs BI | The existing "Logg inn med BI" title, text and button. | Same | Same |
| Not a member | A navy panel: a lock tile, "Bare for BISO-medlemmer", "Bli medlem for å bruke dette tilbudet og {N} andre fordeler i {campus}." and a sky "Bli medlem" pill. | Same | Same |
| Signed out | The same panel, but the text says to sign in, and the pill is "Logg inn". | Same | Same |
| Checking | The card with the pill disabled and a spinner, as the sheet does today. | Same | Nothing |
| Check failed | "Vi får ikke sjekket medlemskapet ditt akkurat nå. Prøv igjen om litt." with "Prøv igjen". | Same | Nothing |

## Entry points

All five were chosen:

1. **Home:** a new section "Fordeler for deg" ("Benefits for you") after
   "Skjer i {campus}", with "Vis alle" opening `/explore/benefits`. Its
   content is the Utvalgt deals in a smaller Spotlight card (300 × 176). If
   Utvalgt is empty, show the first 5 member deals without a reason chip. If
   there are no member deals, leave the section out.
2. **Utforsk:** the first row in the category list: a gold `BisoIconTile`
   (gift icon), "Medlemsfordeler", "Rabatter og tilbud for medlemmer". It
   should be found by the Explore search too.
3. **Profil:** a "Medlemsfordeler" row right after Medlemskap and
   Medlemskort, with the same gold gift tile and the subtitle "{N} fordeler i
   {campus}" (or no subtitle while loading).
4. **Medlemskort:** "Dine fordeler" stays as it is, with a "Vis alle" action
   on its section title, and every row opens the new deal page instead of
   the sheet.
5. **"Bli medlem" page** (`/profile/membership`): a link row or small card
   "Se hva du får" ("See what you get") that opens the benefits screen. Show
   it to non-members only, above the plans.

## Discount text (badges and the large number)

A small pure function, unit-tested. Look in the title, then the description
as plain text (HTML stripped), and use the first match:

1. A percentage, `(\d{1,2})\s?%`: badge "−{n} %", large number "{n} %".
2. "gratis" / "free" (case-insensitive, whole word): "Gratis" / "Free".
3. A price, `(\d{2,4})\s?(kr|,-)`: "{n} kr".
4. Otherwise nothing: no badge and no large number.

Write numbers with a space before % and kr ("25 %", "150 kr"), as Norwegian
does. The same function feeds the grid badge, the Spotlight number, the deal
page and the no-image fallback.

## Colour (BISO brand, mapped onto the app's tokens)

The owner asked for this explicitly. The website's brand rules
(`packages/ui/styles/biso-surface.css` in BISO-Sites) are the source:

| Role | Colour | Where |
|---|---|---|
| Navy | `#001731` (the app's `primary`) | The top card, the deal page's action panels, fallback tiles, selected chips, primary pills on light |
| Sky | `#3DA9E0` (the app's dark `primary` / `BisoAccent.blue`) | **Only on navy:** the large count, the "Bli medlem" pill on navy, glyphs in navy tiles, ticks |
| BISO blue | `#1668AE` (≈ the app's `link`) | Links (the campus name), the selected tab, the Utvalgt reason chip on the deal page |
| Sun | `#FECD45` (new token, the brand marker) | **Fill only, never text:** discount badges, the bar under the Spotlight number and under the deal page's large number, the member seal, the small dot on the top card |
| Gold | `#F2B42C` (`BisoAccent.gold`) | Unchanged: the gold icon tiles at the entry points, because gold means "membership" in the app |

Add the sun colour as a palette token (for example `BisoPalette.marker`),
the same in light and dark. Don't use a hex literal in a widget. Navy text on
sun is 12:1.

Type follows `BisoTypography`: Museo 300 for the large title and the large
numbers only, the system font for everything else, and no Museo weight other
than 300.

**Dark mode:** everything reads tokens, so it follows the theme. The navy top
card and panels stay navy in dark mode, with a `#12314F` hairline so they
don't sink into the dark paper. Check contrast in dark mode before calling it
done.

## Copy

Norwegian is the main language. Add both to the ARB files. Change the drafts
below if the owner wants, but keep them plain.

| Key idea | nb | en |
|---|---|---|
| Screen title | Fordeler | Benefits |
| Campus line | For BISO-medlemmer i {campus} | For BISO members in {campus} |
| Top card, non-member | fordeler venter på deg som BISO-medlem i {campus} | benefits waiting for you as a BISO member in {campus} |
| Top card, member | fordeler er dine i {campus} | benefits are yours in {campus} |
| Logos | + {n} til | + {n} more |
| Featured | Utvalgt | Featured |
| Reasons | Valgt av BISO · Slutter {date} · Nytt | Picked by BISO · Ends {date} · New |
| All deals | Alle tilbud | All deals |
| Claim line | Vis kortet i kassen · Rabattkode · Lenke | Show your card · Discount code · Link |
| Perks | Mer enn rabatter | More than discounts |
| Sticky bar | Alt dette får du som medlem / {n} fordeler i {campus} | All this comes with membership / {n} benefits in {campus} |
| Member | Du er medlem / Gyldig til {date} / Vis kort | You're a member / Valid until {date} / Show card |
| Locked | Bare for BISO-medlemmer / Bli medlem for å bruke dette tilbudet og {n} andre fordeler i {campus}. | BISO members only / Join to use this deal and {n} other benefits in {campus}. |
| Use at till | Vis medlemskortet i kassen / Vis kortet før du betaler, så får du rabatten. | Show your membership card at the till / Show the card before you pay to get the discount. |
| Code | Vis rabattkode / Din rabattkode / Koden gjelder bare for BISO-medlemmer. / Til butikken | Show discount code / Your discount code / The code is for BISO members only. / Go to shop |
| Deal page | rabatt for medlemmer · Om tilbudet · Gyldig · Til videre · Nettside · Mer innen {kategori} | member discount · About the deal · Valid · Until further notice · Website · More in {category} |
| Home | Fordeler for deg | Benefits for you |
| Explore / Profile | Medlemsfordeler / Rabatter og tilbud for medlemmer | Member benefits / Discounts and deals for members |
| Membership page | Se hva du får | See what you get |

Reuse the existing `benefits*` strings where they fit (`benefitsCopy`,
`benefitsCopied`, `benefitsUnavailable`, `benefitsNotFound`, `benefitsEmpty`,
`benefitsTerms`, `benefitsLinkFailed`, `benefitsBecomeMember`). Remove the
ones only the sheet used.

## Constraints

- Follow the design system: `BisoPage`, Cupertino icons, `BisoPalette`
  tokens, no `isDark ?` colour branches, and no blur inside cards or grid
  cells. Add every new file to `design_rules_test.dart`'s `migratedFiles`.
- Images go through `CachedNetworkImage` with a bounded `memCacheWidth`. The
  grid is a lazy `SliverGrid`, with no shrink-wrapped lists in scroll views.
- Accessibility: every card has one semantic label (title, discount, reason).
  Decorative images are excluded. Respect the text scale (cards grow, text
  isn't clipped) and reduced motion (no slide-in animation for the sticky
  bar, just show and hide).
- One fetch per visit (`campusBenefitsProvider`). The screen, Home's section
  and the Profile row all read the same provider for the same campus.
- Membership standing comes from `memberPassProvider`, read the way the sheet
  reads it today. The "Gyldig til" date comes from the same data the member
  pass shows.

## Testing expectations

- Unit tests: discount text (every rule plus the no-match case), the Utvalgt
  picker (order, cap at 5, dedupe, the 30-day and 14-day edges in Oslo
  time), the count, and `createdAt` parsing.
- Widget tests for the benefits screen: member, non-member, signed out,
  checking, check failed, loading, error, empty campus, no Utvalgt, category
  filter, sticky bar only after the top card is gone.
- Widget tests for the deal page: every cell of the action table, a missing
  benefit, no image, no description, no terms, no partner.
- Entry points: each one shows and navigates. The member pass rows open the
  deal page, not a sheet.
- `flutter analyze` and the full test suite pass.

## Docs (BISO-Sites)

The staff guide page
`apps/docs/content/docs/guide/members-and-benefits/publish-a-benefit.mdx`
("What the student sees") describes the app. Update it in a small BISO-Sites
change:

- Where benefits show in the app: the new screen, the entry points, and the
  deal page.
- That **Vis først** puts a benefit in the app's "Utvalgt" row as "Valgt av
  BISO", and that new deals and deals ending soon show there on their own.
- The new non-member wording, replacing "Koden vises bare for medlemmer."

## Left to the builder

- Widget and file structure, and how the member pass, Home and the Profile row
  share the screen's providers.
- The exact skeleton shapes, spacing tweaks and animation curves, within the
  mockups' look.
- How the deal page finds a benefit that wasn't passed in.
- The Spotlight gradient's exact stops, as long as the contrast target holds.
- Whether the Explore search matches "fordeler", "rabatt" and "medlem".
