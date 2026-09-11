# Glass header and full-app redesign

Date: 2026-09-11. Status: approved in conversation, awaiting written-spec review.

Builds on `docs/superpowers/plans/2026-09-11-biso-design-refresh.md`, which
delivered the floating native-glass tab bar, bottom clearance
(`BisoNavigationInset`), expanding header search (`BisoSearchAppBar`), Museo
Sans, and redesigns of Home, Explore, Events and Profile.

## Goal

Every reachable screen shares one visual system that feels native on iOS 26
and distinctly BISO: content scrolls under a translucent header the way it
already scrolls under the tab bar, lists are grouped and scannable, and
nothing looks like a generic template. Performance comes before glass
everywhere.

References: GitHub iOS (home at rest and scrolled, search) and App Store
screenshots supplied by the user on 2026-09-11.

## Decisions

| Topic | Decision |
|---|---|
| Type | Museo Sans 300 for large titles, hero text and big numbers only. System font (SF Pro) for everything else. No synthesized bold. |
| Icon tiles | Five brand-tuned accents, each with one meaning. |
| Header | Blurred scroll edge plus native-glass button capsules. No full-width native glass. |
| Dark mode | Navy-based, not true black. |
| Unreachable screens | Not redesigned. Unused widget files are deleted. |
| Settings | Five tabs become an iOS-Settings list with one page per former tab. |
| Campus detail | Blue parallax header replaced by a photo cover like Home. |

## 1. Foundation

### 1.1 Color tokens

A single source, `BisoColors` (`lib/core/theme/biso_colors.dart`), exposed
through `ThemeData.colorScheme` plus a `ThemeExtension<BisoPalette>` for tokens
Material has no slot for. Screens read tokens, never `AppColors.*` hues, and
never branch on `isDark` for color.

| Token | Light | Dark |
|---|---|---|
| paper (page) | `#F4F7FA` | `#071B2E` |
| surface (groups, cards) | `#FFFFFF` | `#102C46` |
| surfaceRaised (tile wells, fields) | `#EAF0F5` | `#183750` |
| ink | `#001731` | `#F1F6FA` |
| muted | `#526579` (5.6:1 on paper) | `#ABC0D0` (9.3:1) |
| hairline | `#DCE5EC` | `#294158` |
| primary (buttons) | `#001731` | `#3DA9E0` |
| link / selected | `#1570A6` (5.0:1 on paper) | `#3DA9E0` (6.6:1) |
| success | `#177A4E` (5.0:1) | `#4CC38A` (7.9:1) |
| warning | `#935700` (5.4:1) | `#F2B42C` (9.4:1) |
| error | `#D12F3A` (4.7:1) | `#FF6B6B` (6.3:1) |

Accents for icon tiles and category marks. The glyph color is chosen per accent
for at least 3:1 graphic contrast.

| Accent | Meaning | Fill | Glyph | Glyph contrast |
|---|---|---|---|---|
| blue | Events, departures, calendar | `#3DA9E0` | navy | 6.8:1 |
| gold | Shop, orders, membership | `#F2B42C` | navy | 9.7:1 |
| teal | Units, clubs, people, chat | `#12877F` | white | 4.4:1 |
| coral | Money: expenses, payment, reimbursements | `#E0573F` | white | 3.8:1 |
| violet | Help, AI assistant, info | `#7663E8` | white | 4.5:1 |

A neutral tile (surfaceRaised fill, muted glyph) covers rows with no category
(e.g. "Website", "Privacy"). Status colors are used only for status (order
state, verification, errors), never as decoration.

`AppColors` keeps its brand constants (`biNavy`, `biLightBlue`) and loses the
orange/green/purple/pink ramps once no screen references them.

### 1.2 Typography

`PremiumTheme` builds the text theme per platform:

| Style | Family | Weight | Size |
|---|---|---|---|
| displayLarge/Medium/Small | MuseoSans | 300 | 57 / 45 / 36 |
| headlineLarge (large page title) | MuseoSans | 300 | 34 |
| headlineMedium (hero numbers, section heroes) | MuseoSans | 300 | 28 |
| headlineSmall (section title) | system display | 700 | 22 |
| titleLarge | system display | 600 | 20 |
| titleMedium (row title) | system text | 400 | 17 |
| titleSmall | system text | 600 | 15 |
| bodyLarge / Medium / Small | system text | 400 | 17 / 15 / 13 |
| labelLarge (buttons) | system text | 600 | 17 |
| labelMedium / Small | system text | 500 | 13 / 11 |

The system families are `CupertinoSystemDisplay` (20 pt and up) and
`CupertinoSystemText` (below 20 pt) on iOS, and `null` (Roboto) on Android.
Museo styles must not be given a weight other than 300 anywhere; a test asserts
the theme, and a review step greps screens for `fontWeight` applied to headline
or display styles.

### 1.3 Page and header (`BisoPage`)

`lib/core/theme/biso_page.dart`. One scaffold for every screen.

```
BisoPage(
  title: 'Shop',                // large title + compact title
  largeTitle: true,             // false for detail pages: compact title only
  leading: BisoBackButton(),    // default when the route can pop
  actions: [BisoHeaderAction(...), ...],  // grouped into one glass capsule
  search: BisoHeaderSearch(...),// optional expanding search (reuses BisoSearchAppBar logic)
  overImage: false,             // true when content starts with a full-bleed photo
  onRefresh: ...,               // optional pull-to-refresh, offset below header
  slivers: [...],               // or `body:` for non-sliver content
  bottomBar: ...,               // optional pinned bar placed above the tab bar
)
```

Behavior:

- **Layout.** The body fills the whole screen. The header is an overlay.
  `BisoPageInset.top(context)` (status bar + 52 pt) is applied as leading
  scroll padding, mirroring `BisoNavigationInset` at the bottom.
- **At rest.** No bar background. A large Museo title sits at the start of the
  content, actions float top-right in one `BisoChrome` capsule (48 pt tall, 48 pt
  per button, 22 pt icons), and back is a 48 pt glass circle.
- **Scrolled.** The first 12 pt of scroll fade in the band: a
  `BackdropFilter.grouped` blur (sigma 20) tinted with paper at 78% (light) or
  72% (dark), plus a hairline. While the band's opacity is 0 the filter is not
  in the tree.
- **Compact title.** It fades in (system text, 17 pt, 600) once the large title
  has scrolled under the header. Detail pages (`largeTitle: false`) show it
  from the start and fade only the band.
- **Over image.** Before the band appears the header's icons are white on
  chrome, and the status bar is light. After it appears, normal colors return.
- **Scroll detection.** It listens to depth-0 vertical `ScrollNotification`s,
  the same approach as `BisoNavigationScaffold`, so screens need no controllers.
- **Accessibility.** With reduced motion there is no fade: the band shows as
  soon as offset > 0. With high contrast (iOS Increase Contrast,
  `MediaQuery.highContrastOf`) the band is opaque paper plus a hairline and the
  capsules fall back to solid; `BisoChrome` already handles high contrast.
  Flutter does not expose iOS Reduce Transparency. The native capsules and tab
  bar honor it on their own, but the Flutter band cannot, so it stays
  translucent under that setting.
- **Native views.** At most three per screen: header capsule, back circle and
  tab bar. Search reuses the capsule slot.

### 1.4 Building blocks

`lib/presentation/widgets/biso/`:

- `BisoSection(title, action)`: 22 pt section title with an optional "See all"
  text button or `…` menu.
- `BisoListGroup(children)`: surface, 20 pt radius, 16 pt side margins.
  Dividers are inset to start after the icon tile.
- `BisoListRow(leading, title, subtitle, value, trailing, onTap)`: 56 pt minimum
  height, row highlight on press. Trailing is one of chevron, value text,
  `Switch.adaptive`, badge or none.
- `BisoIconTile(icon, accent)`: 32 pt rounded square (8 pt radius), glyph
  20 pt.
- `BisoFormGroup` / `BisoFormField`: grouped inputs styled like iOS Settings
  (label above the field, error below).
- `BisoEmptyState`, `BisoErrorState(onRetry)`, `BisoSkeleton` (rows, cards and
  grid variants).
- Buttons come from the theme: primary is a pill filled with the primary token,
  secondary is a tinted pill (surfaceRaised), destructive is text in the error
  color. Glass buttons exist only in floating chrome.
- Icons: `CupertinoIcons` everywhere in `lib/presentation`. `Icons.*` is allowed
  only where no Cupertino equivalent exists, with a comment.

### 1.5 Tab bar

`BisoNavigationBar` changes only in the active tab: a neutral pill (ink at 8%
light, white at 12% dark), with the icon and label in the link token. Inactive
tabs use ink. The collapse and expand behavior and clearance are unchanged.

### 1.6 Performance rules

- Blur exists only while content is under the header. There is never blur or
  glass inside list items, cards or grids.
- Network images keep `CachedNetworkImage` with bounded `memCacheWidth`.
- Lists stay lazy: slivers and builders, no `shrinkWrap` lists inside scroll
  views.
- Header and tab bar rebuilds are scoped: scroll listening updates only the
  header's own state.

### 1.7 Cleanup

Delete these files, which nothing imports (verified with `rg` on 2026-09-11):
- `screens/home/home_screen.dart`
- `widgets/ai_chat/ai_assistant_fab.dart`
- `widgets/ai_chat/future_tool_preview.dart`
- `widgets/ai_chat/sharepoint_search_widget.dart`
- `widgets/ai_chat/tool_output_widget.dart`
- `widgets/membership_status_widget.dart`
- `widgets/premium/large_event_hero.dart`
- `widgets/premium/premium_navigation.dart`
- `widgets/premium/wonderous_bottom_nav.dart`
- `widgets/premium/wonderous_story_card.dart`
- `core/theme/app_theme.dart`

Also remove the unused classes in `premium_components.dart` and
`premium_layouts.dart` (`PremiumCard`, `PremiumTextField`, `PremiumChip`,
`PremiumSwitch`, `PremiumAppBar`, `PremiumIconButton`, `PremiumList`,
`PremiumHero`), and `BisoGlassScope` and `BisoGlassBottomNavigation`.

The following are **kept and not redesigned** because nothing reaches them:
`student_id_screen.dart` and both membership modals, `chat_list_screen.dart`
(it still defines `chatServiceProvider` and `userChatsProvider`),
`new_chat_screen.dart` and `message_search_screen.dart`. The broken deep link
to `/chat/conversation/:id` (`deep_link_service.dart:349`) is out of scope and
noted for later.

## 2. Screens

Every screen moves onto `BisoPage` and the tokens. Group 0 comes first; groups
A–G touch separate files and may run in parallel. Shared l10n additions are
collected in one step at the end of each group to avoid ARB conflicts.

**0. Foundation and alignment.** Sections 1.1–1.7. Then migrate Home
(`overImage` over the campus cover), Explore (directory rows use accent tiles
instead of the rainbow cards), Events and Profile (grouped rows, Cupertino
icons, the gold completion card becomes a neutral group with a primary button).

**A. Explore directories.**
- Units overview: large title, image cards.
- Unit detail: detail page with a logo header group.
- Volunteer: large title, grouped job rows; the detail sheet is restyled.
- Departures: large title, rows with line badges.
- Notifications: large title, grouped rows, unread dot in the link color.
- Announcement: detail page with a category chip row and HTML body.
- Pull-to-refresh sits below the header.

**B. Shop.**
- Marketplace: mode chips and categories move into the scrolling content, and
  the grid becomes a `SliverGrid` passing under the header. Search stays
  expanding.
- Product detail and webshop product detail: `overImage` full-bleed gallery;
  back, favorite and cart are glass; the purchase bar is a `bottomBar` above
  the tab bar.
- Cart, checkout, orders and order: grouped lists with totals in Museo; the
  order status uses status tokens.
- Sell product: grouped form.
- Checkout, payment and cart logic are not touched.

**C. Money and forms.**
- Expenses: the title-swapping search field becomes the standard expanding
  search; the summary and filters scroll with the list; the detail sheet is
  restyled; the "New expense" FAB is removed, and a `+` action is added to the
  header capsule next to search, as in GitHub.
- New expense: grouped form sections and restyled receipt tiles. The screen
  has no step model, so no step indicator is added.
- Payment information, edit profile: grouped forms.
- Validation and upload logic are not touched.

**D. Settings.**
- `SettingsScreen` becomes a grouped list. Rows for General, Notifications,
  Privacy, Chat and Language each push their own page, which reuses the body of
  the former tab.
- `SettingsScreen(initialTab:)` callers push the matching page directly.
- Campus-colored tab styling is removed.

**E. Conversations.**
- Chat conversation: detail header with avatar and name as the compact title;
  messages pass under it; the composer is a glass capsule above keyboard and tab
  bar; the other person's bubbles are surface with ink text, and your own are
  primary with on-primary text.
- Chat info, user picker: grouped rows.
- AI assistant: same chat treatment with a violet accent, no gradients; the
  double top inset from `SafeArea` is removed.

**F. Campus and large events.**
- Campus detail: the parallax blue `SliverAppBar` is replaced by an `overImage`
  photo cover like Home; the scroll-to-top FAB is removed; the leadership
  section uses grouped rows.
- Large event: `overImage` full-bleed hero.

**G. Outside the tab shell.**
- Login, verification code, magic link: scrollable and keyboard-safe (no
  `Spacer` overflow), Museo hero title, primary pill buttons.
- Onboarding: step progress in the header, the fixed-height `PageView` inside a
  scroll view is replaced by per-step scrollable pages.
- Ticket scanner: always dark, camera full-bleed, glass header and result
  sheet over it.

## 3. Out of scope

- Data, providers, services and business logic.
- Routes, except that settings sub-pages are pushed the same way settings is
  today.
- Unreachable screens listed in 1.7.
- Real Museo Sans weights beyond 300.
- Android-specific visual tuning beyond the existing solid fallback.
- Performance profiling on a physical device. It remains a pre-release step and
  no frame-rate claim is made without it.

## 4. Testing and verification

- **Foundation, test-first.** Theme test (Museo styles weight 300 only; system
  families on iOS). `BisoPage` tests: no band and no `BackdropFilter` at offset
  0; band present after scrolling; first content row starts below the header
  but can scroll under it; compact title appears after the large title passes;
  reduced motion; high contrast gives an opaque band. `BisoListRow` and
  `BisoIconTile` contrast and semantics tests. Tab bar active-pill test.
- **Per group.** Update the existing tests that pin layout
  (`navigation_content_clearance_test.dart`,
  `webshop_product_detail_screen_test.dart`). Add a smoke test per screen that
  it builds under `BisoPage` in light and dark at text scale 1.0 and 1.6
  without overflow. Settings test that each former tab is reachable from its
  row.
- **Every group ends with** `flutter analyze` (no new issues), the full
  `flutter test` suite passing, and a `rg` check of the group's files for
  `Icons\.`, `AppColors\.(orange|green|purple|pink)` and `isDark \?`.
- **Visual.** Simulator screenshots of every screen in light and dark at rest
  and scrolled, inspected against the references. Signed-in screens require the
  user to sign in on the simulator once.

## 5. Risks

- **Flutter blur beneath native glass views.** The capsules are `UiKitView`s
  over a Flutter `BackdropFilter`. Group 0 verifies in the simulator, before any
  screen migration, that the band and capsules composite correctly while
  scrolling. If they do not, the capsules sit on an opaque chip while the band
  is visible.
- **Screens with bespoke scroll physics** (marketplace, expenses, chat) must
  become sliver-based for content to pass under the header. That is the
  largest behavioral change in the redesign and is covered by their smoke and
  clearance tests.
- **Settings restructure** changes navigation depth. Deep entry points
  (`initialTab`) are updated in the same change.
