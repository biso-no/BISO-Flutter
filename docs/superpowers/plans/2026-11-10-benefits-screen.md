# Member Benefits Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A benefits screen and a full deal page in the BISO Flutter app,
reachable from Home, Explore, Profile, the member pass and the membership
page, for members, non-members and signed-out visitors.

**Architecture:** Pure logic first: discount text, the "Utvalgt" picker and
the showcase grouping are plain Dart, unit-tested. A single membership
"standing" provider wraps the existing `memberPassProvider` and
`membershipOverviewProvider`. The screens are built from small widgets in
`lib/presentation/widgets/benefits/`. The reveal/copy logic moves out of the
old bottom sheet into a panel on the new deal page, and the sheet is deleted.

**Tech Stack:** Flutter, Riverpod 2 (`flutter_riverpod`), go_router,
`cached_network_image`, `flutter gen-l10n` (ARB files in
`lib/generated/l10n/`, generated Dart committed).

**Spec:** `docs/superpowers/specs/2026-11-09-benefits-screen-design.md`.
Read it before starting any task. Where the mockups and the spec differ, the
spec wins.

All paths are relative to the worktree
`/Users/markus/Documents/dev/BISO-Flutter/.claude/worktrees/benefits-screen`
(branch `feat/benefits-screen`), except Task 14, which is in BISO-Sites.

## Global Constraints

- Never push, open a PR, deploy or write to production. Commit locally on `feat/benefits-screen` only.
- No changes to `apps/api`, the admin, the website or the Appwrite schema. Only Task 14 touches BISO-Sites (docs).
- Codes and links: only fetched by `BenefitsApi.reveal` after a member taps. Never cache, log or put them in a provider, and drop them when the page closes.
- Never say or imply "not a member" when the standing is `checking` or `unavailable`.
- Design rules (`test/presentation/design_rules_test.dart`): Cupertino icons only (Material only with `// biso:allow <reason>` where none exists), colours via `BisoPalette`, no `isDark ?` branches, no `BisoNavigationInset.`, Museo (display*/headlineLarge/headlineMedium) only at weight 300. Add every new `lib/` file to `migratedFiles`.
- Brand colours: navy `#001731`, sky `#3DA9E0` **only on navy**, BISO blue = `palette.link`, sun `#FECD45` **fill only, never text**, gold `BisoAccent.gold` for the entry-point tiles.
- No blur inside cards or grid cells. Network images use `CachedNetworkImage` with a bounded `memCacheWidth`.
- Numbers are written Norwegian style with a no-break space: `25 %`, `150 kr`. A badge's minus is U+2212: `−25 %`.
- Copy: Norwegian first, plain, no superlatives, no idioms translated word for word. All strings come from the ARB files (Task 4).
- Run `dart format` on touched files before each commit. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Large text and long titles**: at text scale 2.0 with a 70-character title, the grid cards, Spotlight cards, top card and deal page grow or truncate and never overflow. Tests in Tasks 8, 9 and 10.
2. **Standing changes while the screen is open**: going from `checking` to `member` never shows "Bli medlem" or the sticky bar in between. Test in Task 10.
3. **A deal opened with no loaded list** (deep link, restored app, or a deal that has since ended): the page loads it by id, or shows "Denne fordelen er ikke lenger tilgjengelig." Test in Task 7.
4. **A student with no profile campus** opening from the member pass or Profile: the screen lists all-of-BISO benefits and labels the campus "Hele BISO". Tests in Tasks 10 and 12.
5. **An old API without `/api/benefits`** (`notDeployed`): the screen shows an empty state, and the Home section, Explore row, Profile row, member pass "Vis alle" and membership link are all hidden. Tests in Tasks 10, 11 and 12.

---

### Task 1: `createdAt` on the model, and the discount text

**Files:**
- Modify: `lib/data/models/campus_benefit.dart`
- Create: `lib/core/utils/benefit_highlight.dart`
- Test: `test/data/models/campus_benefit_test.dart`, `test/core/utils/benefit_highlight_test.dart`

**Interfaces:**
- Produces: `CampusBenefit.createdAt` (`DateTime?`, parsed from the API's `createdAt`, null when missing or unparseable, included in `props`).
- Produces:
  ```dart
  enum BenefitHighlightKind { percent, free, price }
  class BenefitHighlight extends Equatable {
    const BenefitHighlight.percent(int amount);
    const BenefitHighlight.price(int amount);
    const BenefitHighlight.free();
    final BenefitHighlightKind kind;
    final int? amount;
  }
  BenefitHighlight? benefitHighlightOf(CampusBenefit benefit, String languageCode);
  ```

- [ ] **Step 1: Write the failing tests**

In `campus_benefit_test.dart`, add: `createdAt parses an ISO string` (`'2026-11-09T10:00:00.000+00:00'` → `DateTime.utc(2026, 11, 9, 10)`), and `createdAt is null when missing or garbage`.

`benefit_highlight_test.dart`: build benefits with a helper `b({String title = 'X', String? description})` and assert:

```dart
expect(benefitHighlightOf(b(title: 'GRAFFI GRILL', description: '25% rabatt på hele menyen for biso-medlemmer'), 'nb'), const BenefitHighlight.percent(25));
expect(benefitHighlightOf(b(title: '20% Rabatt på Los Tacos'), 'nb'), const BenefitHighlight.percent(20));
expect(benefitHighlightOf(b(title: 'Club Tempo', description: 'Gratis inngang for alle BISO-medlemmer'), 'nb'), const BenefitHighlight.free());
expect(benefitHighlightOf(b(title: 'Free entry'), 'en'), const BenefitHighlight.free());
expect(benefitHighlightOf(b(title: 'RUSH', description: '150kr for 2 timer hopping'), 'nb'), const BenefitHighlight.price(150));
expect(benefitHighlightOf(b(title: 'BABA', description: '149 kr for sandwich, 119kr for acai'), 'nb'), const BenefitHighlight.price(149));
expect(benefitHighlightOf(b(title: 'Kino', description: 'Billett 75,-'), 'nb'), const BenefitHighlight.price(75));
// title wins over description
expect(benefitHighlightOf(b(title: '10 % hos Peppes', description: 'Gratis brus'), 'nb'), const BenefitHighlight.percent(10));
// markup is read as plain text
expect(benefitHighlightOf(b(title: 'X', description: '<p>25<strong>%</strong> rabatt</p>'), 'nb'), const BenefitHighlight.percent(25));
// nothing to claim, or numbers we must not over-read
expect(benefitHighlightOf(b(title: 'Medlemspriser på arrangementer'), 'nb'), isNull);
expect(benefitHighlightOf(b(title: '100% fornøyd'), 'nb'), isNull);
expect(benefitHighlightOf(b(title: 'Gratisparkering'), 'nb'), isNull);
expect(benefitHighlightOf(b(title: 'Siden 2026'), 'nb'), isNull);
```

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/data/models/campus_benefit_test.dart test/core/utils/benefit_highlight_test.dart`
Expected: FAIL (`createdAt` and `benefitHighlightOf` are undefined).

- [ ] **Step 3: Implement**

Add `createdAt` to `CampusBenefit` (constructor, `tryParse`, `props`). Then write `benefitHighlightOf`:
- Read the title with `benefit.title.resolve(languageCode)`, then the description with `richContentToPlainText(benefit.description.resolve(languageCode) ?? '')` (`lib/core/utils/rich_content.dart`).
- For each text in that order, try the three rules in order. The first match wins.
  - Percent: `RegExp(r'(?<!\d)(\d{1,2})\s?%')`
  - Free: `RegExp(r'\b(gratis|free)\b', caseSensitive: false)`
  - Price: `RegExp(r'(?<!\d)(\d{2,4})\s?(?:kr\b|,-)', caseSensitive: false)`

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): read createdAt and find a deal's discount text"`

---

### Task 2: Showcase grouping and the "Utvalgt" picker

**Files:**
- Create: `lib/providers/benefits/benefit_showcase.dart`
- Modify: `lib/providers/benefits/benefits_providers.dart`
- Test: `test/providers/benefits/benefit_showcase_test.dart`

**Interfaces:**
- Consumes: `CampusBenefit` (with `createdAt`) from Task 1.
- Produces:
  ```dart
  enum FeaturedReason { pickedByBiso, endingSoon, isNew }
  class FeaturedBenefit extends Equatable { const FeaturedBenefit(this.benefit, this.reason); final CampusBenefit benefit; final FeaturedReason? reason; }
  /// Catalogue order, as on the website.
  const benefitCategoryKeys = ['food_drink','health_fitness','nightlife','shopping','travel','software','events','other'];
  String benefitCategoryKeyOf(CampusBenefit b); // unknown or null -> 'other'
  class BenefitShowcase {
    factory BenefitShowcase.from(List<CampusBenefit> all, {required DateTime now});
    final List<CampusBenefit> deals;                           // section member, API order
    final List<FeaturedBenefit> featured;                      // at most 5, each with a reason
    final Map<BenefitSection, List<CampusBenefit>> perks;      // keys career, social, safety in that order; empty lists left out
    final List<String> categories;                             // keys present in deals, catalogue order
    final List<String> imageUrls;                              // distinct partner.logoUrl ?? imageUrl, deals order, nulls skipped
    int get count;                                             // deals.length + every perk
    bool get isEmpty;                                          // no deals and no perks
    List<FeaturedBenefit> get homeItems;                       // featured, else first 5 deals with reason null
  }
  ```
- Produces, in `benefits_providers.dart`:
  ```dart
  final benefitClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
  final benefitShowcaseProvider = Provider.autoDispose.family<AsyncValue<BenefitShowcase>, String?>(...); // maps campusBenefitsProvider(campusId)
  ```

- [ ] **Step 1: Write the failing tests**

Use `now = DateTime.utc(2026, 11, 10, 12)`. Each test builds a list and calls `BenefitShowcase.from(list, now: now)`:
- `deals keep API order and only the member section`
- `business never shows`: a `business` item appears nowhere and isn't counted.
- `perks group career, social, safety in that order and skip empty ones`
- `count is deals plus perks`
- `featured order: picked by BISO, then ending soon, then new`. Input order: new, ending, picked. Expect reasons `[pickedByBiso, endingSoon, isNew]`.
- `featured caps at 5 and lists a deal once`. One deal is featured, ends in 3 days and is new: one entry, with `pickedByBiso`.
- `ending soon edge`: `publishEnd = now + 30 days` is in, `+ 30 days + 1 minute` is out, and a `publishEnd` in the past is out.
- `new edge`: `createdAt = now − 14 days` is in, `− 14 days − 1 minute` is out, and null `createdAt` is out.
- `featured only takes member deals`: a featured `career` item is left out.
- `categories in catalogue order, unknown counted as other`
- `imageUrls prefer the partner logo, are distinct and skip nulls`
- `homeItems falls back to the first 5 deals without a reason`, and is empty when there are no deals.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/providers/benefits/benefit_showcase_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement `BenefitShowcase.from` and the two providers**

Edges are instant differences: `!end.isAfter(now.add(Duration(days: 30)))` and `end.isAfter(now)`; `!created.isBefore(now.subtract(Duration(days: 14)))`. `benefitShowcaseProvider` returns `ref.watch(campusBenefitsProvider(campusId)).whenData((list) => BenefitShowcase.from(list, now: ref.watch(benefitClockProvider)()))`.

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): group the showcase and pick Utvalgt deals with a reason"`

---

### Task 3: Membership standing, and a shared "Logg inn med BI" action

**Files:**
- Create: `lib/providers/benefits/benefit_standing.dart`
- Create: `lib/presentation/screens/auth/continue_with_bi_action.dart`
- Modify: `lib/presentation/screens/profile/member_pass_screen.dart` (use the shared action)
- Test: `test/providers/benefits/benefit_standing_test.dart`, existing `test/presentation/screens/profile/member_pass_screen_test.dart` must stay green

**Interfaces:**
- Produces:
  ```dart
  enum BenefitStanding { member, upcoming, needsBi, notMember, signedOut, checking, unavailable }
  class BenefitStandingInfo extends Equatable {
    const BenefitStandingInfo(this.standing, {this.validUntil, this.upcomingStart});
    final BenefitStanding standing; final DateTime? validUntil; final DateTime? upcomingStart;
    bool get isNonMember; // notMember || signedOut
  }
  BenefitStandingInfo benefitStandingFrom(MemberPassView view, {DateTime? upcomingStart});
  final benefitStandingProvider = Provider.autoDispose<BenefitStandingInfo>(...);
  ```
- Produces: `Future<void> runContinueWithBi(BuildContext context, WidgetRef ref)`. This is the body of `_MemberPassScreenState._continueWithBi` without the busy flag: `continueWithBi(ref)`, then `memberPassProvider.notifier.retry()`, `goToOnboardingAfterBi`, and the snackbar from `biContinueMessage`. Callers keep their own busy state.

- [ ] **Step 1: Write the failing tests**

A table test over `benefitStandingFrom`:

| view | upcomingStart | expected |
|---|---|---|
| `activeView()` (from `test/helpers/fake_member_pass_api.dart`) | – | `member`, `validUntil == view.pass!.holder.expiryDate` |
| `status: signedOut` | – | `signedOut` |
| `status: loading` | – | `checking` |
| `status: reconnect` | – | `unavailable` |
| `noPass / noBiIdentity` | – | `needsBi` |
| `noPass / notMember` | null | `notMember` |
| `noPass / expired` | null | `notMember` |
| `noPass / notMember` | `DateTime.utc(2027,1,1)` | `upcoming`, `upcomingStart` set |
| `noPass / unavailable` and `noPass / null` | – | `unavailable` |

Also `isNonMember is true only for notMember and signedOut`.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/providers/benefits/benefit_standing_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the mapping and the provider**

`benefitStandingProvider` watches `membershipOverviewProvider`'s `valueOrNull?.upcomingMembership?.startDate`, then `ref.watch(memberPassProvider.select((v) => benefitStandingFrom(v, upcomingStart: start)))`. The select stops the pass's one-second ticker from rebuilding watchers. Then move `_continueWithBi`'s body into `runContinueWithBi` and call it from the member pass screen.

- [ ] **Step 4: Run the tests and see them pass**

Run: `flutter test test/providers/benefits/benefit_standing_test.dart test/presentation/screens/profile/member_pass_screen_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): one membership standing for the benefits feature"`

---

### Task 4: Strings

**Files:**
- Modify: `lib/generated/l10n/app_en.arb` (template), `lib/generated/l10n/app_no.arb`, and the regenerated `app_localizations*.dart`
- Test: `test/l10n/benefits_strings_test.dart`

**Interfaces:**
- Produces these `AppLocalizations` members, for every later task. nb / en:

| Key | nb | en |
|---|---|---|
| `benefitsScreenTitle` | Fordeler | Benefits |
| `benefitsCampusLine(campus)` | For BISO-medlemmer i {campus} | For BISO members in {campus} |
| `benefitsAllOfBiso` | Hele BISO | All of BISO |
| `benefitsTopNonMember(count, campus)` | plural: fordel venter / fordeler venter på deg som BISO-medlem i {campus} | benefit is / benefits are waiting for you as a BISO member in {campus} |
| `benefitsTopMember(count, campus)` | plural: fordel er din / fordeler er dine i {campus} | benefit is / benefits are yours in {campus} |
| `benefitsTopNeutral(count, campus)` | plural: fordel / fordeler for BISO-medlemmer i {campus} | benefit / benefits for BISO members in {campus} |
| `benefitsMoreLogos(count)` | + {count} til | + {count} more |
| `benefitsYouAreMember` | Du er medlem | You're a member |
| `benefitsMemberValidUntil(date)` | Gyldig til {date} | Valid until {date} |
| `benefitsShowCardShort` | Vis kort | Show card |
| `benefitsSignInAction` | Logg inn | Sign in |
| `benefitsFeatured` | Utvalgt | Featured |
| `benefitsReasonPicked` | Valgt av BISO | Picked by BISO |
| `benefitsReasonEnds(date)` | Slutter {date} | Ends {date} |
| `benefitsReasonNew` | Nytt | New |
| `benefitsAllDeals` | Alle tilbud | All deals |
| `benefitsCategoryAll` | Alle | All |
| `benefitsCategoryFoodDrink` … `benefitsCategoryOther` | Mat og drikke, Trening og helse, Uteliv, Shopping, Reise, Programvare, Arrangementer, Annet | Food & drink, Health & fitness, Nightlife, Shopping, Travel, Software, Events, Other |
| `benefitsClaimCard` / `benefitsClaimCode` / `benefitsClaimLink` | Vis kortet i kassen / Rabattkode / Lenke | Show your card / Discount code / Link |
| `benefitsMembersOnlyShort` | Bare for medlemmer | Members only |
| `benefitsMoreThanDiscounts` | Mer enn rabatter | More than discounts |
| `benefitsSectionCareer` / `Social` / `Safety` | Karrierefordeler / Sosialt nettverk / Trygghet og støtte | Career advantages / Social network / Safety & support |
| `benefitsStickyTitle` | Alt dette får du som medlem | All this comes with membership |
| `benefitsCountInCampus(count, campus)` | plural: {count} fordel / fordeler i {campus} | {count} benefit / benefits in {campus} |
| `benefitsLockedTitle` | Bare for BISO-medlemmer | BISO members only |
| `benefitsLockedBody(count, campus)` | plural: Bli medlem for å bruke dette tilbudet og {count} annen fordel / andre fordeler i {campus}. | Join to use this deal and {count} other benefit(s) in {campus}. |
| `benefitsLockedSignedOutBody` | Logg inn og bli medlem for å bruke dette tilbudet. | Sign in and join to use this deal. |
| `benefitsUseAtTillTitle` | Vis medlemskortet i kassen | Show your membership card at the till |
| `benefitsUseAtTillBody` | Vis kortet før du betaler, så får du rabatten. | Show the card before you pay to get the discount. |
| `benefitsShowMemberCard` | Vis medlemskortet | Show membership card |
| `benefitsRevealCode` / `benefitsOpenDeal` | Vis rabattkode / Åpne tilbudet | Show discount code / Open the deal |
| `benefitsYourCode` | Din rabattkode | Your discount code |
| `benefitsCodeNote` | Koden gjelder bare for BISO-medlemmer. | The code is for BISO members only. |
| `benefitsToShop` | Til butikken | Go to shop |
| `benefitsMemberHasIt` | Du har denne fordelen som medlem. | You have this benefit as a member. |
| `benefitsUpcomingPanel(date)` | Medlemskapet ditt starter {date}. Da kan du bruke tilbudet. | Your membership starts {date}. You can use the deal from then. |
| `benefitsDiscountForMembers` | rabatt for medlemmer | member discount |
| `benefitsFree` | Gratis | Free |
| `benefitsAboutDeal` | Om tilbudet | About the deal |
| `benefitsValid` / `benefitsUntilDate(date)` / `benefitsUntilFurther` | Gyldig / Til {date} / Til videre | Valid / Until {date} / Until further notice |
| `benefitsWebsite` | Nettside | Website |
| `benefitsMoreInCategory(category)` | Mer innen {category} | More in {category} |
| `benefitsForYou` | Fordeler for deg | Benefits for you |
| `benefitsMemberBenefits` / `benefitsMemberBenefitsSubtitle` | Medlemsfordeler / Rabatter og tilbud for medlemmer | Member benefits / Discounts and deals for members |
| `benefitsSeeWhatYouGet` | Se hva du får | See what you get |

Plurals use ICU (`{count, plural, =1{…} other{…}}`). `count` is `int`, `date`/`campus`/`category` are `String`.

- [ ] **Step 1: Write the failing test**

`benefits_strings_test.dart` loads `AppLocalizations` for `nb` and `en` (follow `test/l10n/member_pass_strings_test.dart`) and asserts:
- `benefitsCountInCampus(1, 'Oslo') == '1 fordel i Oslo'` and `(27, 'Oslo') == '27 fordeler i Oslo'`
- the same for en: `'1 benefit in Oslo'`, `'27 benefits in Oslo'`
- `benefitsLockedBody(26, 'Trondheim') == 'Bli medlem for å bruke dette tilbudet og 26 andre fordeler i Trondheim.'`
- `benefitsReasonEnds('30. nov.') == 'Slutter 30. nov.'`

- [ ] **Step 2: Run it and see it fail**

Run: `flutter test test/l10n/benefits_strings_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Add the keys to both ARB files and regenerate**

Run: `flutter gen-l10n`. Expected: `app_localizations*.dart` updated, no warnings about missing translations.

- [ ] **Step 4: Run the test and see it pass**

Run: the same command. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): strings for the benefits screen and deal page"`

---

### Task 5: Brand tokens and shared benefit visuals

**Files:**
- Modify: `lib/core/theme/biso_colors.dart`
- Create: `lib/presentation/widgets/benefits/benefit_visuals.dart`
- Modify: `test/presentation/design_rules_test.dart` (add the new file)
- Test: `test/core/theme/biso_palette_brand_test.dart`, `test/presentation/widgets/benefits/benefit_visuals_test.dart`

**Interfaces:**
- Produces new `BisoPalette` fields, the **same value in light and dark**, included in `copyWith` and `lerp`: `deep #001731`, `deepRaised #0B2747`, `deepEdge #12314F`, `deepMuted #93A7BB`, `sky #3DA9E0`, `marker #FECD45`.
- Produces, in `benefit_visuals.dart`:
  ```dart
  IconData benefitCategoryIcon(String key);   // food_drink: Icons.restaurant (// biso:allow no Cupertino food icon), health_fitness: sportscourt, nightlife: moon_stars, shopping: bag, travel: airplane, software: device_laptop, events: calendar, other: sparkles
  String benefitCategoryLabel(String key, AppLocalizations l10n);
  String benefitHighlightBadge(BenefitHighlight h, AppLocalizations l10n);  // '−25 %', l10n.benefitsFree, '150 kr'
  String benefitHighlightValue(BenefitHighlight h, AppLocalizations l10n);  // '25 %', l10n.benefitsFree, '150 kr'
  String benefitReasonLabel(FeaturedReason r, CampusBenefit b, AppLocalizations l10n); // endingSoon uses DateFormat('d. MMM', locale) on the Oslo day
  IconData benefitReasonIcon(FeaturedReason r); // star_fill, clock, sparkles
  class BenefitImage extends StatelessWidget { const BenefitImage({required CampusBenefit benefit, required int memCacheWidth, double fallbackNumberSize = 44}); }
  class BenefitBadge extends StatelessWidget { const BenefitBadge(String label); }      // marker fill, deep text, 13pt 700
  class BenefitReasonChip extends StatelessWidget { const BenefitReasonChip({required FeaturedReason reason, required CampusBenefit benefit, bool onImage = true}); }
  ```
  `BenefitImage` fills its parent. With an image, it uses `CachedNetworkImage(fit: BoxFit.cover, memCacheWidth: …)` with `errorWidget` drawing the fallback. Without one, or on error, the fallback is a `deep`→`deepRaised` gradient with the highlight value in Museo (`headlineMedium` sized by `fallbackNumberSize`, colour `sky`). With no highlight it shows the category icon in `sky`. The image is wrapped in `ExcludeSemantics`.

- [ ] **Step 1: Write the failing tests**

- Palette: `marker`, `deep` and `sky` equal `Color(0xFFFECD45)`, `Color(0xFF001731)` and `Color(0xFF3DA9E0)` in both `BisoPalette.light` and `.dark`, and `lerp(light, dark, .5).marker == marker`.
- Visuals: `benefitHighlightBadge(percent(25)) == '−25 %'`, `benefitHighlightValue(price(150)) == '150 kr'`, and the nb label for `food_drink` is `'Mat og drikke'`.
- `BenefitImage` with no `imageUrl` and description `'25% rabatt'` shows text `'25 %'`. With neither image nor highlight, it shows `Icon(CupertinoIcons.sparkles)` for category `other`.
- `BenefitReasonChip` for `endingSoon` with `publishEnd 2026-11-30T22:59:59Z` shows `'Slutter 30. nov.'` in nb. (Oslo day 30 Nov. Accept whatever `DateFormat('d. MMM','nb')` renders, asserted via the same call.)

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/core/theme/biso_palette_brand_test.dart test/presentation/widgets/benefits/benefit_visuals_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the tokens and `benefit_visuals.dart`**

- [ ] **Step 4: Run the tests, plus the design rules**

Run: `flutter test test/core/theme test/presentation/widgets/benefits/benefit_visuals_test.dart test/presentation/design_rules_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): brand tokens and shared benefit visuals"`

---

### Task 6: The deal page's action panel (logic moved from the sheet)

**Files:**
- Create: `lib/presentation/widgets/benefits/benefit_action_panel.dart`
- Modify: `lib/providers/benefits/benefits_providers.dart` (move `benefitLinkOpenerProvider` here from the sheet)
- Modify: `test/presentation/design_rules_test.dart`
- Test: `test/presentation/widgets/benefits/benefit_action_panel_test.dart`

**Interfaces:**
- Consumes: `BenefitStandingInfo`/`benefitStandingProvider` (Task 3), `runContinueWithBi` (Task 3), strings (Task 4), palette tokens (Task 5).
- Produces: `class BenefitActionPanel extends ConsumerStatefulWidget { const BenefitActionPanel({required CampusBenefit benefit, required int otherCount, required String campusName}); }`. It reads `benefitStandingProvider` itself.

Behaviour: the spec's action table, cell by cell. The reveal state machine, `_openLink` (https only), `_copy` with the `benefitsCopied` snackbar, and the outage retry are copied from `benefit_detail_sheet.dart` unchanged. "Bli medlem" pushes `/profile/membership`, and "Logg inn" goes to `/auth/login`. Code view: monospace on `deepRaised`, a sky "Kopier" pill, and "Til butikken" only when `benefit.partner?.websiteUrl` is set (opened through `benefitLinkOpenerProvider`).

- [ ] **Step 1: Write the failing tests**

Move every test from `benefit_list_section_test.dart` that opens the sheet and exercises reveal, copy, link, members-only, outage or not-found into this file. Pump `BenefitActionPanel` directly with the same fakes (`_FakeApi`, `_FakePass`). Then add one test per new table cell:
- member + onsite: `'Vis medlemskortet'`, and tapping calls `showPassPresentation` (follow the existing presentation test's fake)
- member + none: `'Du har denne fordelen som medlem.'` and no `FilledButton`
- notMember + onsite: `'Bare for BISO-medlemmer'` and `'Bli medlem for å bruke dette tilbudet og 26 andre fordeler i Trondheim.'` with `otherCount: 26, campusName: 'Trondheim'`
- signedOut: `'Logg inn'`, and no `'Bli medlem'`
- upcoming: `'Medlemskapet ditt starter 1. januar 2027. Da kan du bruke tilbudet.'`, with no button
- needsBi: the `membershipNeedsBiLinkCta` text
- checking: a disabled button with a progress indicator, and no `'Bli medlem'`
- code revealed: `'Din rabattkode'`, the code, `'Kopier'`, and `'Til butikken'` only when the partner has a website

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/widgets/benefits/benefit_action_panel_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the panel**

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command plus `test/presentation/design_rules_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): action panel for the deal page"`

---

### Task 7: The deal page and its route; the sheet goes away

**Files:**
- Create: `lib/presentation/screens/benefits/benefits_routes.dart`
- Create: `lib/presentation/screens/benefits/benefit_detail_screen.dart`
- Modify: `lib/main.dart` (route under `/explore`)
- Modify: `lib/presentation/widgets/benefits/benefit_list_section.dart` (a row tap pushes the deal page)
- Delete: `lib/presentation/widgets/benefits/benefit_detail_sheet.dart`. Remove it from `migratedFiles`, and remove ARB keys that nothing references any more (check each with `rg`), then run `flutter gen-l10n`.
- Modify: `test/presentation/widgets/benefits/benefit_list_section_test.dart`, `test/presentation/design_rules_test.dart`
- Test: `test/presentation/screens/benefits/benefit_detail_screen_test.dart`

**Interfaces:**
- Produces, in `benefits_routes.dart`:
  ```dart
  const benefitsPath = '/explore/benefits';
  const nationalCampusParam = 'national';
  String benefitsRoute({String? campusParam});                  // '/explore/benefits' or '?campus=<campusParam>'
  String benefitRoute(String benefitId, {required String? campusId}); // '/explore/benefits/<id>?campus=<campusId ?? national>'
  String? campusIdFromParam(String param);                       // 'national' -> null
  String pinnedCampusParam(String? campusId);                    // campusId ?? 'national'
  ```
- Produces: `class BenefitDetailScreen extends ConsumerWidget { const BenefitDetailScreen({required String benefitId, required String? campusId, CampusBenefit? initial}); }`
- Produces: `final benefitCampusNameProvider = Provider.autoDispose.family<String, String?>(...)` in `lib/providers/benefits/benefits_providers.dart`. A null id gives `''`, and widgets show `l10n.benefitsAllOfBiso`. Otherwise the name comes from `filterCampusProvider` when the ids match, else from `switcherCampusesProvider`'s value, else `'BISO'`.
- Route: `GoRoute(path: '/benefits/:benefitId')` nested under a `GoRoute(path: '/benefits')` under `/explore`. The list builder is a placeholder `SizedBox` until Task 10 replaces it. The detail builder passes `state.extra as CampusBenefit?` and `campusIdFromParam(state.uri.queryParameters['campus'] ?? nationalCampusParam)`.

Layout follows the spec's "deal page" section: `BisoPage(overImage: true, largeTitle: false, title: <title>)`. From top to bottom:
1. A 300pt `BenefitImage(memCacheWidth: 1080, fallbackNumberSize: 64)`.
2. Chips: category, plus the reason if `BenefitShowcase.featured` has this deal.
3. Title in `headlineSmall` (26pt / 700, via `copyWith(fontSize: 26)`).
4. The partner row (logo and name), else a pin icon with the campus name or `benefitsAllOfBiso`.
5. The large highlight row: Museo `displayMedium` w300 in `deep`, with a 6pt `marker` bar under it, and `benefitsDiscountForMembers` for percent only.
6. `BenefitActionPanel`, where `otherCount = showcase.count - 1`.
7. "Om tilbudet" with `description.toFullHtml(...)`, as the sheet did.
8. The info group: Gyldig, Nettside (through `benefitLinkOpenerProvider`), Vilkår (expandable).
9. "Mer innen {kategori}": up to 8 same-category deals, 140pt squares. In nb the category label is lowercased: "Mer innen mat og drikke".

- [ ] **Step 1: Write the failing tests**

- `shows a deal passed in without fetching`: the fake API's `campuses` stays empty.
- `loads a deal by id when nothing is passed in`: no `extra`, the fake API returns the deal, and its title shows.
- `a deal that is gone says so`: the fake API returns an empty list, and `'Denne fordelen er ikke lenger tilgjengelig.'` shows.
- `no image shows the fallback number`
- `no description: no "Om tilbudet"`, and `no terms: no "Vilkår"`
- `no partner shows the campus name`, and `an all-of-BISO deal shows "Hele BISO"`
- `"Mer innen" lists other deals of the category and leaves this one out`
- `text scale 2.0 with a 70-char title: no overflow` (`expect(tester.takeException(), isNull)`)
- In `benefit_list_section_test.dart`: `tapping a row opens the deal page` (routed harness with an `extraRoutes` entry for `/explore/benefits/:benefitId`). Remove the sheet tests that moved in Task 6.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/screens/benefits/benefit_detail_screen_test.dart test/presentation/widgets/benefits/benefit_list_section_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the routes, the screen, the list-row tap, and delete the sheet**

- [ ] **Step 4: Run the tests and analyze**

Run: `flutter test test/presentation test/providers/benefits && flutter analyze`. Expected: PASS, no new analyzer issues.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): a full deal page replaces the benefit sheet"`

---

### Task 8: The top card and Spotlight

**Files:**
- Create: `lib/presentation/widgets/benefits/benefits_top_card.dart`
- Create: `lib/presentation/widgets/benefits/benefit_spotlight.dart`
- Modify: `test/presentation/design_rules_test.dart`
- Test: `test/presentation/widgets/benefits/benefits_top_card_test.dart`, `test/presentation/widgets/benefits/benefit_spotlight_test.dart`

**Interfaces:**
- Produces: `class BenefitsTopCard extends ConsumerWidget { const BenefitsTopCard({required BenefitShowcase showcase, required String campusName}); }`. It reads `benefitStandingProvider`.
- Produces: `enum BenefitSpotlightSize { large, compact }` and `class BenefitSpotlight extends StatelessWidget { const BenefitSpotlight({required List<FeaturedBenefit> items, required String? campusId, BenefitSpotlightSize size = BenefitSpotlightSize.large}); }`. Tapping a card pushes `benefitRoute(id, campusId: campusId)` with `extra: benefit`.

Top card, per the spec's "top card" section:
- `deep` fill, 24 radius, padding 22/20, and always a 1pt `deepEdge` border (it only shows on dark paper, so no theme branch is needed).
- `campusName` comes from `benefitCampusNameProvider`. When it's empty, show `l10n.benefitsAllOfBiso`.
- A decorative ring of `sky` at 16% alpha top-right, and an 8pt `marker` dot.
- The count in Museo `displayLarge` w300 in `sky`.
- The text from `benefitsTopNonMember`/`TopMember`/`TopNeutral(count, campus)`.
- Up to 5 40pt round images from `showcase.imageUrls`, overlapping by 10, then `benefitsMoreLogos(n)` when more than 5. Leave the row out when the list is empty.
- The action row by standing:
  - notMember: a `sky` pill "Bli medlem" → push `/profile/membership`
  - signedOut: a `sky` pill "Logg inn" → `/auth/login`
  - member: a `deepRaised` row with a `marker` seal tile, `benefitsYouAreMember`, `benefitsMemberValidUntil(formatOsloDate(validUntil))` and a white "Vis kort" pill → `showPassPresentation`
  - upcoming: the same row, with `membershipStartsOn` and no pill
  - needsBi: a row with `membershipNeedsBiLinkTitle` and a pill with `membershipNeedsBiLinkCta` → `runContinueWithBi`
  - checking/unavailable: nothing

Spotlight:
- **large:** a `PageView` with `viewportFraction ≈ 0.92`, 236pt tall, 22 radius, and page dots underneath.
- **compact:** a horizontal `ListView` of 300×176 cards with no dots.
- Each card: a `BenefitImage(memCacheWidth: 900)` under a gradient from transparent at 30% to `deep` at 94%, strong enough for 4.5:1 behind the text. Then a `BenefitReasonChip` top-left (when `reason != null`), the title and two lines of description bottom-left in white, and the highlight value bottom-right in Museo **white** with a 5pt `marker` bar under it. No auto-advance.
- Each card has one `Semantics(button: true)` label: reason, title and highlight value.

- [ ] **Step 1: Write the failing tests**

Top card:
- for each standing, the right texts and pills: notMember shows `'Bli medlem'`; signedOut shows `'Logg inn'` and no `'Bli medlem'`; member shows `'Du er medlem'`, `'Gyldig til …'` and `'Vis kort'`; upcoming shows `membershipStartsOn` and no `'Vis kort'` and no `'Bli medlem'`; needsBi shows the CTA and no `'Bli medlem'`; checking and unavailable show none of `'Bli medlem'`, `'Logg inn'` and `'Du er medlem'`
- `+ N til` appears only above 5 images
- dark mode pumps without exceptions
- text scale 2.0: no overflow

Spotlight:
- reason chips render the right labels
- the value text is white (find the `Text` with `'15 %'` and check its style colour is `Colors.white`)
- a tap pushes `/explore/benefits/<id>?campus=3`
- compact mode has no page dots
- text scale 2.0 with a 70-char title: no overflow

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/widgets/benefits/benefits_top_card_test.dart test/presentation/widgets/benefits/benefit_spotlight_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement both widgets**

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command plus `test/presentation/design_rules_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): top card and Spotlight"`

---

### Task 9: Grid cards, category chips and the perks section

**Files:**
- Create: `lib/presentation/widgets/benefits/benefit_grid.dart`
- Create: `lib/presentation/widgets/benefits/benefit_perks.dart`
- Modify: `test/presentation/design_rules_test.dart`
- Test: `test/presentation/widgets/benefits/benefit_grid_test.dart`, `test/presentation/widgets/benefits/benefit_perks_test.dart`

**Interfaces:**
- Produces: `class BenefitGridCard extends StatelessWidget { const BenefitGridCard({required CampusBenefit benefit, required BenefitStanding standing, required String? campusId}); }`
- Produces: `class BenefitCategoryChips extends StatelessWidget { const BenefitCategoryChips({required List<String> categories, required String? selected, required ValueChanged<String?> onSelected}); }`. `null` means "Alle". The widget renders nothing when `categories.length < 2`.
- Produces: `Widget benefitGridSliver({required List<CampusBenefit> deals, required BenefitStanding standing, required String? campusId})`. This is a lazy `SliverList.builder` of rows, each holding two cards in `IntrinsicHeight` + `Row` + `Expanded` so cards grow with text and match heights. (This replaces the spec's `SliverGrid`, which can't grow with the text scale.)
- Produces: `class BenefitPerksSection extends StatelessWidget { const BenefitPerksSection({required Map<BenefitSection, List<CampusBenefit>> perks}); }`

Grid card:
- `surface` fill, 18 radius.
- A 4:3 `BenefitImage(memCacheWidth: 600)` with a `BenefitBadge` top-left when there's a highlight.
- The title (15pt 600), then up to 2 lines of description (`richContentToPlainText`, muted).
- A claim line: card icon + `benefitsClaimCard` for onsite, `benefitsClaimCode`, `benefitsClaimLink`, or nothing for none. **When `standing` is `notMember` or `signedOut`**, a lock icon + `benefitsMembersOnlyShort` replaces it for every type.
- One `Semantics` label: title, highlight and claim line.
- Tapping pushes the deal page with `extra`.

Perks section:
- A subheading per section: a 24pt `deep` tile with a `sky` glyph (briefcase, person_2, shield) and the section label.
- A `BisoListGroup` of non-tappable rows: a 20pt `sky` circle with a `deep` checkmark, the title, and the description as a 2-line muted subtitle when there is one.

- [ ] **Step 1: Write the failing tests**

- `the claim line follows the redemption type for a member`
- `non-members and signed-out see "Bare for medlemmer" on every card`
- `checking keeps the normal claim line`
- `chips hide below two categories`
- `tapping a chip calls onSelected with its key, "Alle" with null`
- `perks show headings in order career, social, safety, with descriptions as subtitles`
- `text scale 2.0 with a 70-char title: grid rows grow, no overflow`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/widgets/benefits/benefit_grid_test.dart test/presentation/widgets/benefits/benefit_perks_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command plus the design rules test. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): deal grid, category chips and perks"`

---

### Task 10: The benefits screen

**Files:**
- Create: `lib/presentation/screens/benefits/benefits_screen.dart`
- Create: `lib/presentation/widgets/campus/campus_switcher_sheet.dart`. Move `_CampusSwitcherModal`/`_CampusModalCard` out of `premium_home_screen.dart` as they are.
- Modify: `lib/presentation/screens/home/premium_home_screen.dart` (use the moved sheet), `lib/main.dart` (the `/explore/benefits` builder), `test/presentation/design_rules_test.dart`
- Test: `test/presentation/screens/benefits/benefits_screen_test.dart`, existing `test/presentation/screens/home/home_design_test.dart` stays green

**Interfaces:**
- Consumes: everything from Tasks 2–9.
- Produces: `Future<void> showCampusSwitcher(BuildContext context, {required String? selectedCampusId, required ValueChanged<CampusModel> onSelected})`.
- Produces: `class BenefitsScreen extends ConsumerStatefulWidget { const BenefitsScreen({String? campusParam}); }`. A null `campusParam` starts on `filterCampusProvider.id`, `'national'` starts on null, and anything else is that id. The campus lives in this widget's state, and switching never touches `filterCampusProvider`.
- Route builder: `BenefitsScreen(campusParam: state.uri.queryParameters['campus'])`.

Layout (`BisoPage(title: benefitsScreenTitle, largeTitle: true)`, slivers):
1. The campus line: `benefitsCampusLine` with the campus name as a `palette.link` tappable span with a chevron, which opens `showCampusSwitcher`.
2. `BenefitsTopCard`.
3. "Utvalgt" + `BenefitSpotlight` when `featured` isn't empty.
4. "Alle tilbud" + the count, `BenefitCategoryChips` (local `selected` state), and `benefitGridSliver` over the filtered deals.
5. "Mer enn rabatter" + `BenefitPerksSection` when `perks` isn't empty.

The sticky bar is a glass `bottomBar`: `benefitsStickyTitle`, `benefitsCountInCampus`, and a `deep` pill ("Bli medlem", or "Logg inn" when signed out). It shows only for `notMember`/`signedOut`, and only once the top card's bottom edge has scrolled above the header. Track that with a `GlobalKey` on the card and a `ScrollNotification` listener. With reduced motion (`MediaQuery.disableAnimations`) it appears without a slide.

States:
- loading: title, campus line, `BisoSkeleton.card()`, `BisoSkeleton.grid(count: 4)`
- error: `BisoErrorState(onRetry: invalidate)`
- `notDeployed`, or `showcase.isEmpty`: `BisoEmptyState(icon: CupertinoIcons.gift, title: benefitsEmpty)`, with the campus line kept so the student can switch

- [ ] **Step 1: Write the failing tests**

Use `pumpBisoScreen(routed: true)` with fakes for `benefitsApiProvider`, `memberPassProvider`, `membershipOverviewProvider`, `authStateProvider`, `filterCampusStateProvider` and `benefitClockProvider`:
- `member sees the member row and no sticky bar after scrolling`
- `non-member: no sticky bar at the top, sticky bar after scrolling past the top card` (`tester.drag(find.byType(CustomScrollView), Offset(0, -900))`)
- `signed out: "Logg inn" in the card and the sticky bar`
- `checking then member never shows "Bli medlem"`: start `loading`, assert `find.text('Bli medlem')` finds nothing, switch the fake to `activeView()`, pump, and assert `'Du er medlem'`.
- `no Utvalgt: the section is gone`
- `chip filter narrows the grid`
- `campusParam "national" lists all-of-BISO benefits and labels "Hele BISO"`: the fake API records `campuses == [null]`.
- `switching campus refetches for the new campus and leaves filterCampusProvider alone`
- `loading, error and retry`, and `empty campus shows the empty state with the campus line`
- `notDeployed shows the empty state`
- `dark mode and text scale 2.0 pump without exceptions`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/screens/benefits/benefits_screen_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the switcher move, the screen and the route**

- [ ] **Step 4: Run the tests and see them pass**

Run: `flutter test test/presentation/screens/benefits test/presentation/screens/home test/presentation/design_rules_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): the benefits screen"`

---

### Task 11: Home: "Fordeler for deg"

**Files:**
- Create: `lib/presentation/widgets/home/home_benefits_section.dart`
- Modify: `lib/presentation/screens/home/premium_home_screen.dart` (insert after the "Skjer i {campus}" section), `test/presentation/design_rules_test.dart`
- Test: `test/presentation/widgets/home/home_benefits_section_test.dart`

**Interfaces:**
- Produces: `class HomeBenefitsSection extends ConsumerWidget { const HomeBenefitsSection({required String campusId}); }`. It returns a sliver.

Header: the same pattern as `_buildPremiumContentSection` (`headlineSmall` title `benefitsForYou`, and a "Vis alle" `TextButton` → `context.go(benefitsRoute())`). Body: `BenefitSpotlight(items: showcase.homeItems, campusId: campusId, size: compact)`. Loading shows `BisoSkeleton.card()`. The section returns `SliverToBoxAdapter(child: SizedBox.shrink())` on error, `notDeployed`, or empty `homeItems`.

- [ ] **Step 1: Write the failing tests**

- `shows Utvalgt items with reasons`
- `falls back to the first deals without reason chips`
- `hidden with no deals`, `hidden on error`, and `hidden on notDeployed`
- `"Vis alle" goes to /explore/benefits`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/widgets/home/home_benefits_section_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement it and insert it in Home**

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command plus `test/presentation/screens/home`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): Fordeler for deg on Home"`

---

### Task 12: Explore, Profile, member pass and membership page links

**Files:**
- Modify: `lib/presentation/screens/explore/explore_screen.dart`. Add the first `_CategoryData`: `CupertinoIcons.gift`, `BisoAccent.gold`, `benefitsMemberBenefits`, `benefitsMemberBenefitsSubtitle`, → `context.go(benefitsRoute())`. Search matches its title and subtitle like every other row.
- Create: `lib/presentation/widgets/benefits/benefits_profile_row.dart`. `BenefitsProfileRow`: a `BisoListRow` with a gold gift tile, `benefitsMemberBenefits`, and the subtitle `benefitsCountInCampus(count, campusName)` for the profile campus (`benefitShowcaseProvider(user?.campusId)` and `benefitCampusNameProvider(user?.campusId)`, with an empty name shown as `benefitsAllOfBiso`; no subtitle while loading) → `context.push(benefitsRoute(campusParam: pinnedCampusParam(user?.campusId)))`.
- Modify: `lib/presentation/screens/profile/profile_screen.dart`. Insert `const BenefitsProfileRow()` after `MemberPassRow()`.
- Modify: `lib/presentation/widgets/benefits/benefit_list_section.dart`. `BisoSection.action` gets a `TextButton(viewAllMessage)` → `context.push(benefitsRoute(campusParam: pinnedCampusParam(campusId)))`.
- Modify: `lib/presentation/screens/profile/membership_screen.dart`. When `!overview.isMember`, add a `BisoSection` with one `BisoListRow` (gold gift tile, `benefitsSeeWhatYouGet`) → `context.push(benefitsRoute())`, placed after the `_NotMemberCard` sliver and before the plans.
- Modify: `test/presentation/design_rules_test.dart`
- Test: `test/presentation/screens/explore/explore_benefits_row_test.dart`, `test/presentation/widgets/benefits/benefits_profile_row_test.dart`, additions to `benefit_list_section_test.dart` and `test/presentation/screens/profile/membership_screen_test.dart`

All four are hidden when `campusBenefitsProvider` fails with `notDeployed`. Explore can't know before fetching, so it watches `campusBenefitsProvider(filterCampus.id)` and hides the row only on a `notDeployed` error. The others watch the provider for their campus.

- [ ] **Step 1: Write the failing tests**

- `Explore lists "Medlemsfordeler" first and it opens /explore/benefits`, `Explore search "fordel" finds it`, and `hidden on notDeployed`
- `Profile row shows "27 fordeler i Trondheim" and pushes /explore/benefits?campus=3`, and `a user with no campus pushes ?campus=national and shows "Hele BISO"`, and `hidden on notDeployed`
- `member pass "Vis alle" pushes /explore/benefits?campus=<profile campus>`, and `hidden on notDeployed`
- `membership page shows "Se hva du får" to a non-member only`, and it pushes `/explore/benefits`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/presentation/screens/explore/explore_benefits_row_test.dart test/presentation/widgets/benefits test/presentation/screens/profile/membership_screen_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the four entry points**

- [ ] **Step 4: Run the tests and see them pass**

Run: the same command plus `test/presentation/screens/profile test/presentation/screens/explore test/presentation/design_rules_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat(benefits): Explore, Profile, member pass and membership links"`

---

### Task 13: Whole-branch verification

**Files:** none new, unless a fix is needed.

- [ ] **Step 1: Analyze**

Run: `flutter analyze`. Expected: `No issues found!`, or only issues that already exist on `main`. To tell them apart, run `flutter analyze` in the main checkout `/Users/markus/Documents/dev/BISO-Flutter`, read-only, without switching its branch.

- [ ] **Step 2: Full test suite**

Run: `flutter test`. Expected: every test passes.

- [ ] **Step 3: Leftovers**

Run: `rg -n "benefit_detail_sheet|showBenefitDetailSheet|benefitsShowCard\b|benefitsMembersOnly\b" lib test`. Expected: no matches. Run `rg -n "Color\(0x" lib/presentation/widgets/benefits lib/presentation/screens/benefits`. Expected: no matches.

- [ ] **Step 4: Commit any fixes**

`git commit -m "fix(benefits): <what>"` (skip if nothing changed).

---

### Task 14: Staff guide update (BISO-Sites)

**Files:**
- Worktree: from `/Users/markus/Documents/dev/BISO-Sites`, check `git branch --show-current` and `git status --short`, then `git worktree add .claude/worktrees/app-benefits-docs -b docs/app-benefits-screen main`. Work only there.
- Modify: `apps/docs/content/docs/guide/members-and-benefits/publish-a-benefit.mdx`, the "What the student sees" section

Replace the app bullet (the one starting "In the app, the button is …") with bullets that say, in the page's existing style (bold Norwegian UI text with an English gloss in brackets):
- The app has a **Fordeler** (Benefits) screen, opened from Home (**Fordeler for deg**), Explore and Profile (**Medlemsfordeler**), the member pass and the membership page. Tapping a benefit opens its own page.
- **Vis først** (Show first) puts a benefit at the top of the app's **Utvalgt** (Featured) row, marked **Valgt av BISO** (Picked by BISO). A benefit that ends within 30 days (**Slutter …**) and one added in the last 14 days (**Nytt**) show there on their own. There are at most five.
- On a benefit's page a member sees **Vis medlemskortet** (Show membership card), **Vis rabattkode** (Show discount code) or **Åpne tilbudet** (Open the deal). Someone who isn't a member sees **Bare for BISO-medlemmer** (BISO members only) and **Bli medlem** (Join). On the benefits list they see **Bare for medlemmer** (Members only) on every benefit.
- A benefit with a picture looks best. Without one, the app shows a navy tile with the discount from the text (for example "25 %").

- [ ] **Step 1: Edit the page**

- [ ] **Step 2: Check it**

Run: `bun run --filter=docs test && bun run --filter=docs check-types && bun run --filter=docs lint`. Expected: all pass.

- [ ] **Step 3: Commit in the BISO-Sites worktree**

`git commit -m "docs(benefits): what students see in the app's benefits screen"`
