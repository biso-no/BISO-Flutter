# Glass Header and Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every reachable BISO screen on one design system: tokens, SF Pro UI type with Museo Sans headlines, grouped lists, and a translucent header that content scrolls under.

**Architecture:**
- **Foundation (Tasks 1–10):**
  - `BisoPalette` / `BisoAccent` color tokens and `BisoTypography`, wired into `PremiumTheme.build`.
  - `BisoPageHeader`: blurred scroll-edge band plus native-glass capsules.
  - `BisoPage`: a full-screen scroll body with the header overlaid, mirroring how `BisoNavigationScaffold` overlays the tab bar.
  - Building blocks in `lib/presentation/widgets/biso/`.
- **Screens (Tasks 11–36):** migrated one or two per task with a shared recipe, guarded by a design-rules test.

**Tech Stack:** Flutter 3.47.2 (Dart 3), Riverpod 2, go_router, `native_liquid_glass_flutter` (via `BisoChrome`), flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-11-glass-header-and-screen-redesign-design.md`. Read it before starting any task.

## Global Constraints

**Scope**
- Do not change data models, services, providers, or business logic.
- Do not change GoRouter routes. The only navigation changes are:
  - Settings section pages, pushed with `MaterialPageRoute` as Settings is today.
  - The debug-only `biso://debug/open` deep link (Task 9).

**Tokens and type**
- Colors come from `BisoPalette.of(context)` or `BisoAccent`. Migrated files contain no `AppColors` orange/green/purple/pink/gold ramps and no `isDark ?` color branches.
- Museo Sans (`displayLarge/Medium/Small`, `headlineLarge`, `headlineMedium`) is only ever weight 300. Never apply `fontWeight` to those styles.
- Icons in migrated files are `CupertinoIcons`. A Material `Icons.*` use is allowed only with a trailing `// biso:allow` comment explaining why.

**Layout and performance**
- Blur and glass never appear inside list items, cards, or grids.
- Lists stay lazy: slivers and builders, no `shrinkWrap` inside scroll views.
- `BisoPage` owns top and bottom clearance. Migrated screens must not add `BisoNavigationInset.padding`, `SafeArea` top/bottom, or fixed bottom spacers (`SizedBox(height: 132)` and similar).

**Strings**
- New user-visible strings go into both `lib/generated/l10n/app_en.arb` and `lib/generated/l10n/app_no.arb`, followed by `flutter gen-l10n`.
- Existing hardcoded strings are left as they are.

**Verification**
- Every task ends with `flutter analyze` reporting no issues beyond the 12-info baseline (2026-09-11) and the full `flutter test` suite passing.

**Commits and execution**
- Commits happen only after the user has approved committing in Task 0. Commit messages follow the repo's style: sentence-case imperative, no `feat:` prefix. Wherever a commit step shows `"<attribution lines>"`, pass these two lines as the second `-m`, so each commit ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01EoNgHSZ11ZjboBSoGTu3wZ
  ```
- Execute tasks in order. Several tasks touch `test/presentation/design_rules_test.dart` and the ARB files, so running them in parallel conflicts.

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `lib/core/theme/biso_colors.dart` | `BisoPalette` theme extension (light/dark tokens), `BisoAccent` enum |
| `lib/core/theme/biso_typography.dart` | Per-platform `TextTheme` (Museo 300 headlines, system UI faces) |
| `lib/core/theme/biso_page_header.dart` | `BisoPageHeader`, `BisoHeaderAction`, `BisoHeaderSearch`, `BisoGlassCapsule`, `BisoCapsuleButton`, `BisoBackButton`, `kBisoHeaderHeight` |
| `lib/core/theme/biso_page.dart` | `BisoPage`, `BisoPageInsets`, `BisoLargeTitle`, `BisoPageDebug` |
| `lib/presentation/widgets/biso/biso_icon_tile.dart` | `BisoIconTile` |
| `lib/presentation/widgets/biso/biso_list.dart` | `BisoSection`, `BisoListGroup`, `SliverBisoListGroup`, `BisoListRow`, `BisoRowDivider` |
| `lib/presentation/widgets/biso/biso_states.dart` | `BisoEmptyState`, `BisoErrorState`, `BisoSkeleton` |
| `lib/presentation/widgets/biso/biso_form.dart` | `BisoFormGroup`, `BisoFormRow`, `bisoInputDecoration` |
| `lib/presentation/widgets/biso/biso_bottom_bar.dart` | `BisoBottomBar` |
| `lib/presentation/widgets/biso/biso.dart` | Barrel export for screens |
| `test/helpers/biso_screen_harness.dart` | `pumpBisoScreen`, `expectBuildsCleanly` |
| `test/presentation/design_rules_test.dart` | Per-file design rules for migrated files |

**Modified**
- `lib/core/theme/premium_theme.dart`: `build(brightness, platform)` from tokens.
- `lib/core/theme/biso_navigation.dart`: active tab pill.
- `lib/data/services/deep_link_service.dart`: debug deep link.
- Every reachable screen listed in the spec, plus its tests.

**Deleted:** the dead files in spec §1.7, `lib/core/theme/biso_search_app_bar.dart` and its test (Task 19), and any legacy helpers left unreferenced (Task 37).

---

## Task 0: Branch and baseline

The working tree holds Codex's uncommitted design refresh on `main`. This work builds on it.

- [ ] **Step 1: Ask the user** whether to create branch `feat/glass-redesign` and commit the current working tree as a baseline ("Add the BISO design refresh with glass navigation"). Do not run git write commands without an explicit yes.
- [ ] **Step 2: If approved:**

```bash
git switch -c feat/glass-redesign
git add -A
git commit -m "Add the BISO design refresh with glass navigation" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EoNgHSZ11ZjboBSoGTu3wZ"
```

- [ ] **Step 3: Record the baseline:** `flutter analyze` must report 12 issues, all `info`, and `flutter test` must pass all tests (419 on 2026-09-11).

---

## Task 1: Color tokens

**Files:**
- Create: `lib/core/theme/biso_colors.dart`
- Test: `test/core/theme/biso_colors_test.dart`

**Interfaces:**
- Produces:
  - `BisoPalette` (ThemeExtension) with fields `paper, surface, surfaceRaised, ink, muted, hairline, primary, onPrimary, link, success, warning, error` (all `Color`), plus `BisoPalette.light`, `BisoPalette.dark`, and `static BisoPalette of(BuildContext)`.
  - `enum BisoAccent { blue, gold, teal, coral, violet, neutral }` with `Color fill(BuildContext)`, `Color glyph(BuildContext)`, `Color? get fixedFill`, and `Color? get fixedGlyph`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/theme/biso_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, palette) in [
    ('light', BisoPalette.light),
    ('dark', BisoPalette.dark),
  ]) {
    test('$name text tokens reach 4.5:1 on paper and surface', () {
      final text = {
        'ink': palette.ink,
        'muted': palette.muted,
        'link': palette.link,
        'success': palette.success,
        'warning': palette.warning,
        'error': palette.error,
      };
      for (final entry in text.entries) {
        for (final ground in [palette.paper, palette.surface]) {
          expect(
            contrast(entry.value, ground),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on $ground',
          );
        }
      }
      expect(
        contrast(palette.onPrimary, palette.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('accent glyphs reach 3:1 on their fills', () {
    for (final accent in BisoAccent.values) {
      if (accent == BisoAccent.neutral) continue;
      expect(
        contrast(accent.fixedGlyph!, accent.fixedFill!),
        greaterThanOrEqualTo(3),
        reason: accent.name,
      );
    }
  });

  testWidgets('palette and neutral accent follow the theme extension', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [BisoPalette.dark],
        ),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(BisoPalette.of(captured), same(BisoPalette.dark));
    expect(BisoAccent.neutral.fill(captured), BisoPalette.dark.surfaceRaised);
    expect(BisoAccent.neutral.glyph(captured), BisoPalette.dark.muted);
    expect(BisoAccent.gold.fill(captured), const Color(0xFFF2B42C));
  });

  testWidgets('palette falls back to brightness without an extension', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(BisoPalette.of(captured), same(BisoPalette.dark));
  });

  test('lerp reaches each end', () {
    expect(
      BisoPalette.light.lerp(BisoPalette.dark, 0).paper,
      BisoPalette.light.paper,
    );
    expect(
      BisoPalette.light.lerp(BisoPalette.dark, 1).link,
      BisoPalette.dark.link,
    );
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/core/theme/biso_colors_test.dart`
Expected: FAIL at compile time: `Target of URI doesn't exist: 'package:biso/core/theme/biso_colors.dart'`.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';

/// BISO color tokens.
///
/// Screens read colors through [BisoPalette.of] and [BisoAccent]. They never
/// pick hues from the AppColors ramps or branch on brightness themselves.
@immutable
class BisoPalette extends ThemeExtension<BisoPalette> {
  const BisoPalette({
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.primary,
    required this.onPrimary,
    required this.link,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// Page background.
  final Color paper;

  /// Grouped lists and cards.
  final Color surface;

  /// Icon wells, input fields and secondary buttons.
  final Color surfaceRaised;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color primary;
  final Color onPrimary;

  /// Links and selected states.
  final Color link;
  final Color success;
  final Color warning;
  final Color error;

  static const light = BisoPalette(
    paper: Color(0xFFF4F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEAF0F5),
    ink: Color(0xFF001731),
    muted: Color(0xFF526579),
    hairline: Color(0xFFDCE5EC),
    primary: Color(0xFF001731),
    onPrimary: Color(0xFFFFFFFF),
    link: Color(0xFF1570A6),
    success: Color(0xFF177A4E),
    warning: Color(0xFF935700),
    error: Color(0xFFD12F3A),
  );

  static const dark = BisoPalette(
    paper: Color(0xFF071B2E),
    surface: Color(0xFF102C46),
    surfaceRaised: Color(0xFF183750),
    ink: Color(0xFFF1F6FA),
    muted: Color(0xFFABC0D0),
    hairline: Color(0xFF294158),
    primary: Color(0xFF3DA9E0),
    onPrimary: Color(0xFF001731),
    link: Color(0xFF3DA9E0),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFF2B42C),
    error: Color(0xFFFF6B6B),
  );

  static BisoPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BisoPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  BisoPalette copyWith({
    Color? paper,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? muted,
    Color? hairline,
    Color? primary,
    Color? onPrimary,
    Color? link,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return BisoPalette(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      hairline: hairline ?? this.hairline,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      link: link ?? this.link,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  BisoPalette lerp(covariant ThemeExtension<BisoPalette>? other, double t) {
    if (other is! BisoPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BisoPalette(
      paper: mix(paper, other.paper),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      hairline: mix(hairline, other.hairline),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      link: mix(link, other.link),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
    );
  }
}

/// Category accents for icon tiles. Each accent has one meaning, so a color
/// tells the reader what kind of row it is before they read it.
enum BisoAccent {
  /// Events, departures, calendar.
  blue(Color(0xFF3DA9E0), Color(0xFF001731)),

  /// Shop, orders, membership.
  gold(Color(0xFFF2B42C), Color(0xFF001731)),

  /// Units, clubs, people, volunteering, chat.
  teal(Color(0xFF12877F), Color(0xFFFFFFFF)),

  /// Money: expenses, payment, reimbursements.
  coral(Color(0xFFE0573F), Color(0xFFFFFFFF)),

  /// Help, AI assistant, information.
  violet(Color(0xFF7663E8), Color(0xFFFFFFFF)),

  /// Rows without a category.
  neutral(null, null);

  const BisoAccent(this.fixedFill, this.fixedGlyph);

  /// The accent's own fill, or null for [neutral], which follows the theme.
  final Color? fixedFill;

  /// The glyph color chosen for at least 3:1 contrast on [fixedFill].
  final Color? fixedGlyph;

  Color fill(BuildContext context) =>
      fixedFill ?? BisoPalette.of(context).surfaceRaised;

  Color glyph(BuildContext context) =>
      fixedGlyph ?? BisoPalette.of(context).muted;
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/core/theme/biso_colors_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit** (only if approved in Task 0)

```bash
git add lib/core/theme/biso_colors.dart test/core/theme/biso_colors_test.dart
git commit -m "Add BISO color tokens and category accents" -m "<attribution lines>"
```

---

## Task 2: Typography and theme from tokens

**Files:**
- Create: `lib/core/theme/biso_typography.dart`
- Modify: `lib/core/theme/premium_theme.dart`. Replace `lightTheme`, `darkTheme`, `_theme` and `_premiumTextTheme` (lines 7–262); keep the shadow, `glassContainer` and animation members below them unchanged.
- Test: `test/core/theme/premium_theme_test.dart`

**Interfaces:**
- Consumes: `BisoPalette` (Task 1).
- Produces:
  - `BisoTypography.museo` (`'MuseoSans'`) and `static TextTheme BisoTypography.textTheme(TargetPlatform platform)`.
  - `static ThemeData PremiumTheme.build(Brightness brightness, {TargetPlatform? platform})`. `PremiumTheme.lightTheme` and `PremiumTheme.darkTheme` stay as-is for existing callers.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_typography.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Museo Sans is used only at weight 300, only for large type', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final t = BisoTypography.textTheme(platform);
      for (final style in [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
      ]) {
        expect(style!.fontFamily, BisoTypography.museo);
        expect(style.fontWeight, FontWeight.w300);
      }
      for (final style in [
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(style!.fontFamily, isNot(BisoTypography.museo));
      }
    }
  });

  test('iOS uses the system display face from 20 pt and text face below', () {
    final t = BisoTypography.textTheme(TargetPlatform.iOS);
    expect(t.headlineSmall!.fontFamily, 'CupertinoSystemDisplay');
    expect(t.titleLarge!.fontFamily, 'CupertinoSystemDisplay');
    expect(t.titleMedium!.fontFamily, 'CupertinoSystemText');
    expect(t.labelSmall!.fontFamily, 'CupertinoSystemText');
  });

  test('theme keeps per-style families instead of one global font', () {
    final theme = PremiumTheme.build(
      Brightness.light,
      platform: TargetPlatform.iOS,
    );
    expect(theme.textTheme.headlineLarge!.fontFamily, 'MuseoSans');
    expect(theme.textTheme.bodyMedium!.fontFamily, 'CupertinoSystemText');
  });

  test('themes carry their palette and map it into the color scheme', () {
    for (final (brightness, palette) in [
      (Brightness.light, BisoPalette.light),
      (Brightness.dark, BisoPalette.dark),
    ]) {
      final theme = PremiumTheme.build(brightness);
      expect(theme.extension<BisoPalette>(), same(palette));
      expect(theme.scaffoldBackgroundColor, palette.paper);
      expect(theme.colorScheme.primary, palette.primary);
      expect(theme.colorScheme.surface, palette.surface);
      expect(theme.colorScheme.error, palette.error);
      expect(theme.textTheme.bodyMedium!.color, palette.ink);
      final filled = theme.filledButtonTheme.style!;
      expect(filled.backgroundColor!.resolve({}), palette.primary);
      expect(filled.shape!.resolve({}), isA<StadiumBorder>());
      expect(
        theme.textButtonTheme.style!.foregroundColor!.resolve({}),
        palette.link,
      );
    }
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/core/theme/premium_theme_test.dart`
Expected: FAIL at compile time: `biso_typography.dart` doesn't exist and `PremiumTheme.build` isn't defined.

- [ ] **Step 3: Implement `biso_typography.dart`**

```dart
import 'package:flutter/material.dart';

/// Museo Sans exists only as weight 300, so it is reserved for large type
/// where a light weight reads well. Everything else uses the platform's UI
/// face with real weights, which avoids synthesized bold.
class BisoTypography {
  BisoTypography._();

  static const museo = 'MuseoSans';

  static TextTheme textTheme(TargetPlatform platform) {
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final display = apple ? 'CupertinoSystemDisplay' : null;
    final text = apple ? 'CupertinoSystemText' : null;

    TextStyle museoStyle(double size, double height, double spacing) =>
        TextStyle(
          fontFamily: museo,
          fontSize: size,
          fontWeight: FontWeight.w300,
          height: height,
          letterSpacing: spacing,
        );

    TextStyle system(
      String? family,
      double size,
      FontWeight weight,
      double height, [
      double spacing = 0,
    ]) => TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );

    return TextTheme(
      displayLarge: museoStyle(57, 1.12, -1.0),
      displayMedium: museoStyle(45, 1.16, -0.8),
      displaySmall: museoStyle(36, 1.2, -0.6),
      headlineLarge: museoStyle(34, 1.18, -0.5),
      headlineMedium: museoStyle(28, 1.2, -0.3),
      headlineSmall: system(display, 22, FontWeight.w700, 1.25, -0.2),
      titleLarge: system(display, 20, FontWeight.w600, 1.25, -0.2),
      titleMedium: system(text, 17, FontWeight.w400, 1.3, -0.2),
      titleSmall: system(text, 15, FontWeight.w600, 1.33, -0.1),
      bodyLarge: system(text, 17, FontWeight.w400, 1.35, -0.2),
      bodyMedium: system(text, 15, FontWeight.w400, 1.35, -0.1),
      bodySmall: system(text, 13, FontWeight.w400, 1.3),
      labelLarge: system(text, 17, FontWeight.w600, 1.2, -0.2),
      labelMedium: system(text, 13, FontWeight.w500, 1.25),
      labelSmall: system(text, 11, FontWeight.w500, 1.2, 0.1),
    );
  }
}
```

- [ ] **Step 4: Replace the theme builder in `premium_theme.dart`**

Replace everything from `class PremiumTheme {` down to the line before `// === PREMIUM SHADOW SYSTEM ===` with the code below, and add `import 'package:flutter/foundation.dart';`, `import 'biso_colors.dart';` and `import 'biso_typography.dart';` to the imports.

```dart
/// BISO foundations. Colors come from [BisoPalette] and type from
/// [BisoTypography]; component themes only arrange those tokens.
class PremiumTheme {
  static final lightTheme = build(Brightness.light);
  static final darkTheme = build(Brightness.dark);

  static ThemeData build(Brightness brightness, {TargetPlatform? platform}) {
    final dark = brightness == Brightness.dark;
    final p = dark ? BisoPalette.dark : BisoPalette.light;
    final text = BisoTypography.textTheme(
      platform ?? defaultTargetPlatform,
    ).apply(bodyColor: p.ink, displayColor: p.ink);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.biNavy,
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: AppColors.biLightBlue,
      onSecondary: AppColors.biNavy,
      error: p.error,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: p.muted,
      outlineVariant: p.hairline,
      surfaceContainerHighest: p.surfaceRaised,
    );
    const pill = StadiumBorder();
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    OutlineInputBorder field([Color? color, double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      platform: platform,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: p.paper,
      extensions: [p],
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.ink.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        centerTitle: true,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleSmall?.copyWith(fontSize: 17),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: p.surfaceRaised,
          foregroundColor: p.ink,
          side: BorderSide.none,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.link,
          minimumSize: const Size(44, 44),
          textStyle: text.bodyLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        border: field(),
        enabledBorder: field(),
        focusedBorder: field(p.link, 1.5),
        errorBorder: field(p.error),
        focusedErrorBorder: field(p.error, 1.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: p.muted),
        labelStyle: text.bodyLarge?.copyWith(color: p.muted),
        errorStyle: text.bodySmall?.copyWith(color: p.error),
      ),
      dividerTheme: DividerThemeData(
        color: p.hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: p.muted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: p.muted),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.link : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceRaised,
        selectedColor: p.primary,
        labelStyle: text.labelMedium?.copyWith(color: p.ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onPrimary),
        side: BorderSide.none,
        shape: pill,
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.link,
        linearTrackColor: p.surfaceRaised,
      ),
    );
  }

```

- [ ] **Step 5: Run the test, then the full suite**

Run: `flutter test test/core/theme/premium_theme_test.dart`
Expected: PASS (4 tests).

Run: `flutter test`
Expected: all tests pass. If a widget test relied on the old global Museo font or on input borders, fix its finders or expectations to match the new theme without weakening what it checks.

Run: `flutter analyze`
Expected: no issues beyond the baseline.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/biso_typography.dart lib/core/theme/premium_theme.dart test/core/theme/premium_theme_test.dart
git commit -m "Build the theme from BISO tokens with system UI type and Museo headlines" -m "<attribution lines>"
```

---

## Task 3: Neutral active tab pill

**Files:**
- Modify: `lib/core/theme/biso_navigation.dart`, inside `BisoNavigationBar.build` (the `Material` color, the `Icon` color and the label `Text` color in the expanded row, plus the collapsed `Icon` color).
- Test: `test/presentation/widgets/biso_navigation_test.dart` (add one test).

**Interfaces:**
- Consumes: `BisoPalette.of` (Task 1).

- [ ] **Step 1: Write the failing test.** Append inside `main()` and add `import 'package:biso/core/theme/biso_colors.dart';`:

```dart
  testWidgets('active tab uses a neutral pill with link-colored icon and label', (
    tester,
  ) async {
    await tester.pumpWidget(app(index: 1));
    const palette = BisoPalette.light;
    Material pillFor(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    Icon iconFor(String label) => tester.widget<Icon>(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first,
        matching: find.byType(Icon),
      ),
    );
    expect(pillFor('Explore').color, palette.ink.withValues(alpha: 0.08));
    expect(pillFor('Home').color, Colors.transparent);
    expect(tester.widget<Text>(find.text('Explore')).style!.color, palette.link);
    expect(tester.widget<Text>(find.text('Home')).style!.color, palette.ink);
    expect(iconFor('Explore').color, palette.link);
    expect(iconFor('Home').color, palette.ink);
  });
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/presentation/widgets/biso_navigation_test.dart --plain-name 'neutral pill'`
Expected: FAIL. The pill color is the light-blue tint `AppColors.biLightBlue.withValues(alpha: 0.17)`.

- [ ] **Step 3: Implement.** In `BisoNavigationBar.build`, after `final theme = Theme.of(context);` add:

```dart
    final palette = BisoPalette.of(context);
    final selectedFill = palette.ink.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
```

Then make these replacements:
- The `Material` `color:` becomes `currentIndex == i ? selectedFill : Colors.transparent`.
- The expanded `Icon` `color:` becomes `currentIndex == i ? palette.link : palette.ink`.
- The label `copyWith(... color: ...)` becomes `color: currentIndex == i ? palette.link : palette.ink`.
- The collapsed `Icon` `color:` becomes `palette.link`.

Replace `import '../constants/app_colors.dart';` with `import 'biso_colors.dart';` if `AppColors` is no longer used in the file.

- [ ] **Step 4: Run the navigation tests**

Run: `flutter test test/presentation/widgets/biso_navigation_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/biso_navigation.dart test/presentation/widgets/biso_navigation_test.dart
git commit -m "Give the active tab a neutral pill with a link-colored icon" -m "<attribution lines>"
```

---

## Task 4: Page header (band, titles, capsule, back, search)

**Files:**
- Create: `lib/core/theme/biso_page_header.dart`
- Test: `test/core/theme/biso_page_header_test.dart`

**Interfaces:**
- Consumes: `BisoPalette` (Task 1), `BisoChrome` (existing, `lib/core/theme/biso_chrome.dart`).
- Produces:
  - `const double kBisoHeaderHeight = 52;`
  - `class BisoHeaderAction({required IconData icon, required String tooltip, required VoidCallback? onPressed, int? badge})`
  - `class BisoHeaderSearch({required String hintText, required ValueChanged<String> onChanged, String initialQuery = '', Duration debounce = const Duration(milliseconds: 350), ValueChanged<bool>? onExpansionChanged})`
  - `class BisoGlassCapsule({required List<Widget> children})`
  - `class BisoCapsuleButton({required IconData icon, required String tooltip, required VoidCallback? onPressed, Color? color, int? badge})`
  - `class BisoBackButton({VoidCallback? onPressed})`
  - `class BisoPageHeader({required ValueListenable<double> offset, required ValueListenable<double> largeTitleExtent, String? title, bool showLargeTitle = true, Widget? leading, List<BisoHeaderAction> actions = const [], BisoHeaderSearch? search, bool overImage = false})`
  - Keys that tests and later tasks rely on: `ValueKey('biso-page-header')` on the header box, `ValueKey('biso-header-band')` on the band, `ValueKey('biso-compact-title')` on the compact title `Text`, and `ValueKey('biso-header-search')` on the expanded search row.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:biso/core/theme/biso_chrome.dart';
import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_page_header.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget header({
  ValueNotifier<double>? offset,
  double titleExtent = 60,
  bool showLargeTitle = true,
  bool overImage = false,
  bool reducedMotion = false,
  bool highContrast = false,
  List<BisoHeaderAction> actions = const [],
  BisoHeaderSearch? search,
  Widget? leading,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: PremiumTheme.build(brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 47),
          disableAnimations: reducedMotion,
          highContrast: highContrast,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: BisoPageHeader(
              offset: offset ?? ValueNotifier(0),
              largeTitleExtent: ValueNotifier(titleExtent),
              title: 'Shop',
              showLargeTitle: showLargeTitle,
              overImage: overImage,
              actions: actions,
              search: search,
              leading: leading,
            ),
          ),
        ),
      ),
    ),
  );
}

double titleOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('biso-compact-title')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

double bandTintAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(const ValueKey('biso-header-band')),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color!.a;
}

final favorite = BisoHeaderAction(
  icon: CupertinoIcons.heart,
  tooltip: 'Favorite',
  onPressed: () {},
);

void main() {
  testWidgets('at rest there is no band, no blur and no compact title', (
    tester,
  ) async {
    await tester.pumpWidget(header());
    expect(find.byKey(const ValueKey('biso-header-band')), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(titleOpacity(tester), 0);
    expect(
      tester.getSize(find.byKey(const ValueKey('biso-page-header'))).height,
      47 + kBisoHeaderHeight,
    );
  });

  testWidgets('band fades in over 12 pt; title follows the large title', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(0);
    await tester.pumpWidget(header(offset: offset));
    offset.value = 6;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(bandTintAlpha(tester), closeTo(0.78 * 0.5, 0.001));
    expect(titleOpacity(tester), 0);
    offset.value = 58; // extent 60 - 8 = 52, so (58 - 52) / 12 = 0.5
    await tester.pump();
    expect(titleOpacity(tester), closeTo(0.5, 0.001));
    offset.value = 200;
    await tester.pump();
    expect(bandTintAlpha(tester), closeTo(0.78, 0.001));
    expect(titleOpacity(tester), 1);
  });

  testWidgets('dark mode tints the band with 72% paper', (tester) async {
    await tester.pumpWidget(
      header(offset: ValueNotifier(200), brightness: Brightness.dark),
    );
    expect(bandTintAlpha(tester), closeTo(0.72, 0.001));
  });

  testWidgets('reduced motion switches the band and title without fading', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(1);
    await tester.pumpWidget(header(offset: offset, reducedMotion: true));
    expect(bandTintAlpha(tester), closeTo(0.78, 0.001));
    expect(titleOpacity(tester), 0);
    offset.value = 53;
    await tester.pump();
    expect(titleOpacity(tester), 1);
  });

  testWidgets('high contrast makes the band opaque without blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      header(offset: ValueNotifier(200), highContrast: true),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(bandTintAlpha(tester), 1);
  });

  testWidgets('detail pages show the compact title immediately', (
    tester,
  ) async {
    await tester.pumpWidget(header(showLargeTitle: false));
    expect(titleOpacity(tester), 1);
  });

  testWidgets('over an image the header starts clear with light content', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(0);
    await tester.pumpWidget(
      header(offset: offset, overImage: true, actions: [favorite]),
    );
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(BisoPageHeader),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        )
        .value;
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.heart)).color,
        Colors.white);
    expect(titleOpacity(tester), 0);
    expect(style(), SystemUiOverlayStyle.light);
    offset.value = 200;
    await tester.pump();
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.heart)).color,
        BisoPalette.light.ink);
    expect(titleOpacity(tester), 1);
    expect(style(), SystemUiOverlayStyle.dark);
  });

  testWidgets('actions and search share one glass capsule', (tester) async {
    await tester.pumpWidget(
      header(
        actions: [favorite],
        search: BisoHeaderSearch(hintText: 'Search shop', onChanged: (_) {}),
      ),
    );
    expect(find.byType(BisoChrome), findsOneWidget);
    expect(find.byTooltip('Favorite'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
  });

  testWidgets('action badges show their count', (tester) async {
    await tester.pumpWidget(
      header(
        actions: [
          BisoHeaderAction(
            icon: CupertinoIcons.bag,
            tooltip: 'Cart',
            onPressed: () {},
            badge: 3,
          ),
        ],
      ),
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('search expands in place, debounces, and closing clears', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      header(
        search: BisoHeaderSearch(
          hintText: 'Search shop',
          onChanged: queries.add,
        ),
      ),
    );
    final headerRect = tester.getRect(
      find.byKey(const ValueKey('biso-page-header')),
    );
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-search')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('biso-page-header'))),
      headerRect,
    );
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.enterText(field, 'hoodie');
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, ['hoodie']);
    await tester.enterText(field, 'cap');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['hoodie', '']);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Recent searches'), findsNothing);
  });

  testWidgets('an initial query starts with search open', (tester) async {
    await tester.pumpWidget(
      header(
        search: BisoHeaderSearch(
          hintText: 'Search shop',
          initialQuery: 'hoodie',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'hoodie'), findsOneWidget);
  });

  testWidgets('back button is a labelled glass button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      header(leading: BisoBackButton(onPressed: () => tapped = true)),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(tapped, isTrue);
  });

  testWidgets('narrow screen with large text fits, searching or not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      header(
        textScale: 2,
        leading: const BisoBackButton(),
        actions: [favorite],
        search: BisoHeaderSearch(hintText: 'Search shop', onChanged: (_) {}),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `flutter test test/core/theme/biso_page_header_test.dart`
Expected: FAIL at compile time: `biso_page_header.dart` doesn't exist.

- [ ] **Step 3: Implement `biso_page_header.dart`**

```dart
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biso_chrome.dart';
import 'biso_colors.dart';

/// Height of the header row below the status bar.
const double kBisoHeaderHeight = 52;

/// Scroll distance over which the header band fades in.
const double _fadeDistance = 12;

class BisoHeaderAction {
  const BisoHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// A count shown on the button, such as the items in the cart.
  final int? badge;
}

class BisoHeaderSearch {
  const BisoHeaderSearch({
    required this.hintText,
    required this.onChanged,
    this.initialQuery = '',
    this.debounce = const Duration(milliseconds: 350),
    this.onExpansionChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final String initialQuery;
  final Duration debounce;
  final ValueChanged<bool>? onExpansionChanged;
}

/// Floating native glass holding one or more [BisoCapsuleButton]s.
class BisoGlassCapsule extends StatelessWidget {
  const BisoGlassCapsule({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BisoChrome(
    radius: 24,
    child: SizedBox(
      height: 48,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class BisoCapsuleButton extends StatelessWidget {
  const BisoCapsuleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Defaults to the ambient icon color, which the header sets.
  final Color? color;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final count = badge ?? 0;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: palette.link,
          textColor: palette.onPrimary,
          child: Icon(
            icon,
            size: 22,
            color: color ?? IconTheme.of(context).color ?? palette.ink,
          ),
        ),
      ),
    );
  }
}

class BisoBackButton extends StatelessWidget {
  const BisoBackButton({super.key, this.onPressed});

  /// Defaults to [Navigator.maybePop]. Routes reached with `context.go` pass
  /// `NavigationUtils.safeGoBack` so there is always somewhere to go.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => BisoGlassCapsule(
    children: [
      BisoCapsuleButton(
        icon: CupertinoIcons.chevron_back,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onPressed ?? () => Navigator.maybePop(context),
      ),
    ],
  );
}

/// The translucent header of a BisoPage.
///
/// At rest it draws no bar: only the floating back button and action capsule.
/// As [offset] grows a blurred, tinted band with a hairline fades in, and the
/// compact title appears once the large title ([largeTitleExtent] tall) has
/// scrolled underneath.
class BisoPageHeader extends StatefulWidget {
  const BisoPageHeader({
    super.key,
    required this.offset,
    required this.largeTitleExtent,
    this.title,
    this.showLargeTitle = true,
    this.leading,
    this.actions = const [],
    this.search,
    this.overImage = false,
  });

  final ValueListenable<double> offset;
  final ValueListenable<double> largeTitleExtent;
  final String? title;
  final bool showLargeTitle;
  final Widget? leading;
  final List<BisoHeaderAction> actions;
  final BisoHeaderSearch? search;
  final bool overImage;

  @override
  State<BisoPageHeader> createState() => _BisoPageHeaderState();
}

class _BisoPageHeaderState extends State<BisoPageHeader> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.search?.initialQuery ?? '',
  );
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  late bool _searching = _controller.text.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    widget.search?.onExpansionChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.clear();
    setState(() => _searching = false);
    widget.search?.onChanged('');
    widget.search?.onExpansionChanged?.call(false);
  }

  void _onQueryChanged(String value) {
    final search = widget.search!;
    _debounce?.cancel();
    if (value.isEmpty || search.debounce == Duration.zero) {
      search.onChanged(value);
    } else {
      _debounce = Timer(search.debounce, () => search.onChanged(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final searching = _searching && widget.search != null;
    return PopScope(
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && searching) _closeSearch();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.offset,
          widget.largeTitleExtent,
        ]),
        builder: (context, _) {
          final offset = widget.offset.value;
          double fadeAfter(double start) => media.disableAnimations
              ? (offset > start ? 1.0 : 0.0)
              : ((offset - start) / _fadeDistance).clamp(0.0, 1.0);
          final band = fadeAfter(0);
          final titleOpacity = widget.overImage
              ? band
              : widget.showLargeTitle
              ? fadeAfter(widget.largeTitleExtent.value - 8)
              : 1.0;
          final onImage = widget.overImage && band < 0.5;
          final palette = BisoPalette.of(context);
          final foreground = onImage ? Colors.white : palette.ink;
          final darkContent =
              onImage || Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: darkContent
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: SizedBox(
              key: const ValueKey('biso-page-header'),
              height: media.padding.top + kBisoHeaderHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (band > 0)
                    _HeaderBand(amount: band, opaque: media.highContrast),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, media.padding.top, 12, 2),
                    child: IconTheme.merge(
                      data: IconThemeData(color: foreground),
                      child: AnimatedSwitcher(
                        duration: media.disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: searching
                            ? _searchRow(context)
                            : _toolbar(context, foreground, titleOpacity),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context, Color foreground, double titleOpacity) {
    final buttons = <Widget>[
      for (final action in widget.actions)
        BisoCapsuleButton(
          icon: action.icon,
          tooltip: action.tooltip,
          onPressed: action.onPressed,
          badge: action.badge,
          color: foreground,
        ),
      if (widget.search != null)
        BisoCapsuleButton(
          icon: CupertinoIcons.search,
          tooltip: MaterialLocalizations.of(context).searchFieldLabel,
          onPressed: _openSearch,
          color: foreground,
        ),
    ];
    return NavigationToolbar(
      key: const ValueKey('biso-header-toolbar'),
      centerMiddle: true,
      middleSpacing: 12,
      leading: widget.leading == null
          ? null
          : Align(widthFactor: 1, child: widget.leading),
      middle: widget.title == null
          ? null
          : Opacity(
              opacity: titleOpacity,
              child: ExcludeSemantics(
                excluding: titleOpacity < 0.5,
                child: Text(
                  widget.title!,
                  key: const ValueKey('biso-compact-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 17,
                    color: foreground,
                  ),
                ),
              ),
            ),
      trailing: buttons.isEmpty
          ? null
          : Align(
              widthFactor: 1,
              child: BisoGlassCapsule(children: buttons),
            ),
    );
  }

  Widget _searchRow(BuildContext context) {
    final palette = BisoPalette.of(context);
    final search = widget.search!;
    return Row(
      key: const ValueKey('biso-header-search'),
      children: [
        Expanded(
          child: BisoChrome(
            radius: 24,
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  search.onChanged(value);
                  _focusNode.unfocus();
                },
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: palette.ink),
                decoration: InputDecoration(
                  hintText: search.hintText,
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    size: 20,
                    color: palette.muted,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        BisoGlassCapsule(
          children: [
            BisoCapsuleButton(
              icon: CupertinoIcons.xmark,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _closeSearch,
              color: palette.ink,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderBand extends StatelessWidget {
  const _HeaderBand({required this.amount, required this.opaque});

  final double amount;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final tintAlpha = opaque ? 1.0 : (darkTheme ? 0.72 : 0.78);
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper.withValues(alpha: tintAlpha * amount),
        border: Border(
          bottom: BorderSide(
            color: palette.hairline.withValues(alpha: amount),
            width: 0.5,
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('biso-header-band'),
      child: opaque
          ? tint
          : ClipRect(
              child: BackdropFilter.grouped(
                filter: ImageFilter.blur(
                  sigmaX: 20 * amount,
                  sigmaY: 20 * amount,
                ),
                child: tint,
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `flutter test test/core/theme/biso_page_header_test.dart`
Expected: PASS (14 tests). If `find.byType(AnnotatedRegion<SystemUiOverlayStyle>)` doesn't compile with a type literal, use `find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>)` instead.

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/biso_page_header.dart test/core/theme/biso_page_header_test.dart
git commit -m "Add the translucent page header with glass actions and search" -m "<attribution lines>"
```

---

## Task 5: BisoPage

**Files:**
- Create: `lib/core/theme/biso_page.dart`
- Test: `test/core/theme/biso_page_test.dart`

**Interfaces:**
- Consumes: `BisoPageHeader`, `BisoHeaderAction`, `BisoHeaderSearch`, `BisoBackButton` and `kBisoHeaderHeight` (Task 4); `BisoNavigationInset` (existing); `BisoPalette` (Task 1).
- Produces:
  - `class BisoPage({String? title, bool largeTitle = true, Widget? leading, bool automaticallyImplyLeading = true, List<BisoHeaderAction> actions = const [], BisoHeaderSearch? search, bool overImage = false, Future<void> Function()? onRefresh, List<Widget>? slivers, Widget? body, Widget? bottomBar, ScrollController? controller, ScrollPhysics? physics, int notificationDepth = 0})`. Exactly one of `slivers` or `body` must be given.
  - `class BisoPageInsets extends InheritedWidget { final double top; final double bottom; static BisoPageInsets? maybeOf(BuildContext); static EdgeInsets padding(BuildContext, [EdgeInsets spacing]); }`
  - `class BisoLargeTitle(String title)`: the large-title `Text` carries `ValueKey('biso-large-title')`.

**Behavior** (from spec §1.3):
- **Slivers mode:** builds a `CustomScrollView` with these slivers in order:
  1. a top spacer of status bar + 52, skipped for `overImage`
  2. the large title
  3. the page's `slivers`
  4. a bottom spacer of navigation clearance + bottom bar height + 16
- **Body mode:** the body applies `BisoPageInsets.padding(context)` itself.
- **Scroll tracking:** the header follows vertical scroll notifications at `notificationDepth`. Onboarding uses depth 1 because its scroll views live inside a `PageView`.
- **Bottom bar:** sits above the tab bar and drops to the bottom edge when the keyboard is open.
- **Pull-to-refresh:** uses `RefreshIndicator.adaptive(edgeOffset: top)`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/core/theme/biso_page_header.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tabs = [
  BisoNavDestination(icon: CupertinoIcons.house, label: 'Home'),
  BisoNavDestination(icon: CupertinoIcons.square_grid_2x2, label: 'Explore'),
  BisoNavDestination(icon: CupertinoIcons.person, label: 'Profile'),
];

List<Widget> rows() => [
  SliverList.builder(
    itemCount: 40,
    itemBuilder: (_, i) =>
        SizedBox(height: 64, child: Text('Row $i', key: ValueKey('row-$i'))),
  ),
];

Widget app(
  Widget page, {
  bool shell = false,
  double keyboard = 0,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: PremiumTheme.build(Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 47, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(textScale),
        ),
        child: shell
            ? BisoNavigationScaffold(
                currentIndex: 0,
                routeKey: 'test',
                destinations: tabs,
                onSelected: (_) {},
                child: page,
              )
            : page,
      ),
    ),
  );
}

void phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder get headerFinder => find.byKey(const ValueKey('biso-page-header'));

Finder get scrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

bool anyRowUnder(WidgetTester tester, Rect area) => List.generate(
  40,
  (i) => find.byKey(ValueKey('row-$i')),
).where((f) => f.evaluate().isNotEmpty).any(
  (f) => tester.getRect(f).overlaps(area),
);

void main() {
  testWidgets('large title and first row start below the header', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump();
    final header = tester.getRect(headerFinder);
    final title = tester.getRect(find.byKey(const ValueKey('biso-large-title')));
    expect(header.height, 47 + kBisoHeaderHeight);
    expect(title.top, greaterThanOrEqualTo(header.bottom));
    expect(
      tester.getRect(find.byKey(const ValueKey('row-0'))).top,
      greaterThanOrEqualTo(title.bottom),
    );
    expect(find.byKey(const ValueKey('biso-header-band')), findsNothing);
  });

  testWidgets('scrolling moves rows under a blurred header with a title', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(anyRowUnder(tester, tester.getRect(headerFinder)), isTrue);
    final compact = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('biso-compact-title')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(compact.opacity, 1);
  });

  testWidgets('over-image pages start content at the top edge', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(BisoPage(title: 'Hoodie', overImage: true, slivers: rows())),
    );
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('row-0'))).top, 0);
    expect(find.byKey(const ValueKey('biso-large-title')), findsNothing);
  });

  testWidgets('last row clears the bottom bar, which clears the tab bar', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Cart',
          slivers: rows(),
          bottomBar: const SizedBox(
            key: ValueKey('bar'),
            height: 72,
            child: ColoredBox(color: Colors.black),
          ),
        ),
        shell: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.extentAfter, 0);
    final bar = tester.getRect(find.byKey(const ValueKey('bar')));
    final nav = tester.getRect(find.byKey(const ValueKey('biso-nav-expanded')));
    expect(
      tester.getRect(find.byKey(const ValueKey('row-39'))).bottom,
      lessThanOrEqualTo(bar.top),
    );
    expect(bar.bottom, lessThanOrEqualTo(nav.top));
  });

  testWidgets('the keyboard drops the bottom bar to the keyboard edge', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Chat',
          largeTitle: false,
          slivers: rows(),
          bottomBar: const SizedBox(key: ValueKey('bar'), height: 56),
        ),
        shell: true,
        keyboard: 300,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('bar'))).bottom,
      closeTo(844 - 300, 0.5),
    );
  });

  testWidgets('pull to refresh starts below the header', (tester) async {
    phone(tester);
    var refreshed = false;
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Orders',
          slivers: rows(),
          onRefresh: () async => refreshed = true,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset,
      47 + kBisoHeaderHeight,
    );
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, isTrue);
  });

  testWidgets('body pages receive the same insets and drive the header', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Scanner',
          body: Builder(
            builder: (context) => ListView(
              padding: BisoPageInsets.padding(context),
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(
                    height: 64,
                    child: Text('Row $i', key: ValueKey('row-$i')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('row-0'))).top,
      greaterThanOrEqualTo(tester.getRect(headerFinder).bottom),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });

  testWidgets('nested scroll views drive the header at their depth', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Onboarding',
          notificationDepth: 1,
          body: PageView(
            children: [
              Builder(
                builder: (context) => ListView(
                  padding: BisoPageInsets.padding(context),
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 64, child: Text('Row $i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });

  testWidgets('back button appears only when the route can pop', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    expect(find.byTooltip('Back'), findsNothing);
    Navigator.of(tester.element(find.byType(BisoPage))).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const BisoPage(title: 'Detail', largeTitle: false, slivers: []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('large text on a narrow phone does not overflow', (tester) async {
    phone(tester, const Size(320, 720));
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Reimbursements and expenses',
          actions: [
            BisoHeaderAction(
              icon: CupertinoIcons.plus,
              tooltip: 'New',
              onPressed: () {},
            ),
          ],
          slivers: rows(),
        ),
        textScale: 2,
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `flutter test test/core/theme/biso_page_test.dart`
Expected: FAIL at compile time: `biso_page.dart` doesn't exist.

- [ ] **Step 3: Implement `biso_page.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'biso_colors.dart';
import 'biso_navigation.dart';
import 'biso_page_header.dart';

/// Scroll clearance inside a [BisoPage]. [top] clears the translucent header;
/// [bottom] clears the tab bar and the page's bottom bar.
class BisoPageInsets extends InheritedWidget {
  const BisoPageInsets({
    super.key,
    required this.top,
    required this.bottom,
    required super.child,
  });

  final double top;
  final double bottom;

  static BisoPageInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BisoPageInsets>();

  /// [spacing] plus header and bottom clearance, for `body:` pages whose
  /// scroll views set their own padding.
  static EdgeInsets padding(
    BuildContext context, [
    EdgeInsets spacing = EdgeInsets.zero,
  ]) {
    final insets = maybeOf(context);
    final top =
        insets?.top ?? MediaQuery.paddingOf(context).top + kBisoHeaderHeight;
    final bottom = insets?.bottom ?? BisoNavigationInset.of(context);
    return spacing.copyWith(
      top: spacing.top + top,
      bottom: spacing.bottom + bottom,
    );
  }

  @override
  bool updateShouldNotify(BisoPageInsets oldWidget) =>
      top != oldWidget.top || bottom != oldWidget.bottom;
}

class BisoLargeTitle extends StatelessWidget {
  const BisoLargeTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Semantics(
      header: true,
      child: Text(
        title,
        key: const ValueKey('biso-large-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          color: BisoPalette.of(context).ink,
        ),
      ),
    ),
  );
}

/// One scaffold for every BISO screen: a full-screen scroll body with the
/// translucent [BisoPageHeader] floating over it, the way the tab bar floats
/// over the bottom.
class BisoPage extends StatefulWidget {
  const BisoPage({
    super.key,
    this.title,
    this.largeTitle = true,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const [],
    this.search,
    this.overImage = false,
    this.onRefresh,
    this.slivers,
    this.body,
    this.bottomBar,
    this.controller,
    this.physics,
    this.notificationDepth = 0,
  }) : assert(
         (slivers == null) != (body == null),
         'Provide exactly one of slivers or body.',
       );

  final String? title;

  /// Large Museo title at the start of the content. Detail pages turn it off
  /// and show only the compact title.
  final bool largeTitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<BisoHeaderAction> actions;
  final BisoHeaderSearch? search;

  /// The content starts with a full-bleed photo under the header.
  final bool overImage;
  final Future<void> Function()? onRefresh;
  final List<Widget>? slivers;
  final Widget? body;

  /// Pinned above the tab bar, e.g. a purchase bar or a message composer.
  final Widget? bottomBar;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  /// Depth of the scroll view that drives the header. Pages whose scroll
  /// views sit inside a PageView use 1.
  final int notificationDepth;

  @override
  State<BisoPage> createState() => _BisoPageState();
}

class _BisoPageState extends State<BisoPage> {
  final _offset = ValueNotifier<double>(0);
  final _largeTitleExtent = ValueNotifier<double>(double.infinity);
  final _bottomBarHeight = ValueNotifier<double>(0);

  @override
  void dispose() {
    _offset.dispose();
    _largeTitleExtent.dispose();
    _bottomBarHeight.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == widget.notificationDepth &&
        notification.metrics.axis == Axis.vertical) {
      _offset.value =
          notification.metrics.pixels - notification.metrics.minScrollExtent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + kBisoHeaderHeight;
    final navigationBottom = media.viewInsets.bottom > 0
        ? 0.0
        : BisoNavigationInset.of(context);
    final showLargeTitle =
        widget.largeTitle && widget.title != null && !widget.overImage;
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final leading =
        widget.leading ??
        (widget.automaticallyImplyLeading && canPop
            ? const BisoBackButton()
            : null);

    return Scaffold(
      backgroundColor: BisoPalette.of(context).paper,
      body: BackdropGroup(
        child: ValueListenableBuilder<double>(
          valueListenable: _bottomBarHeight,
          builder: (context, barHeight, _) {
            final bottom = navigationBottom + barHeight;
            Widget content =
                widget.body ??
                CustomScrollView(
                  controller: widget.controller,
                  physics:
                      widget.physics ?? const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (!widget.overImage)
                      SliverToBoxAdapter(child: SizedBox(height: top)),
                    if (showLargeTitle)
                      SliverToBoxAdapter(
                        child: _SizeReporter(
                          onSize: (size) =>
                              _largeTitleExtent.value = size.height,
                          child: BisoLargeTitle(widget.title!),
                        ),
                      ),
                    ...widget.slivers!,
                    SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
                  ],
                );
            if (widget.onRefresh != null) {
              content = RefreshIndicator.adaptive(
                onRefresh: widget.onRefresh!,
                edgeOffset: top,
                notificationPredicate: (n) =>
                    n.depth == widget.notificationDepth,
                child: content,
              );
            }
            return BisoPageInsets(
              top: top,
              bottom: bottom,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: content,
                    ),
                  ),
                  if (widget.bottomBar != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: navigationBottom,
                      child: _SizeReporter(
                        onSize: (size) => _bottomBarHeight.value = size.height,
                        child: widget.bottomBar!,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: BisoPageHeader(
                      offset: _offset,
                      largeTitleExtent: _largeTitleExtent,
                      title: widget.title,
                      showLargeTitle: showLargeTitle,
                      leading: leading,
                      actions: widget.actions,
                      search: widget.search,
                      overImage: widget.overImage,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reports its child's size after layout, so clearance can follow content
/// that changes height (large text, localized titles, bottom bars).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `flutter test test/core/theme/biso_page_test.dart`
Expected: PASS (10 tests).

If the refresh test does not trigger, check that `notificationPredicate` depth matches 0 and that the fling starts on the scroll view rather than on the header. Do not delete the assertion.

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/biso_page.dart test/core/theme/biso_page_test.dart
git commit -m "Add BisoPage, a full-screen scaffold under the translucent header" -m "<attribution lines>"
```

---

## Task 6: Grouped lists and icon tiles

**Files:**
- Create: `lib/presentation/widgets/biso/biso_icon_tile.dart`
- Create: `lib/presentation/widgets/biso/biso_list.dart`
- Test: `test/presentation/widgets/biso/biso_list_test.dart`

**Interfaces:**
- Consumes: `BisoPalette`, `BisoAccent` (Task 1).
- Produces:
  - `class BisoIconTile({required IconData icon, BisoAccent accent = BisoAccent.neutral, double size = 32})`
  - `class BisoSection({String? title, Widget? action, String? footer, required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 24, 16, 0)})`
  - `class BisoListGroup({required List<Widget> children, double dividerIndent = 60})`
  - `class SliverBisoListGroup({required int itemCount, required IndexedWidgetBuilder itemBuilder, double dividerIndent = 60, EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 8, 16, 0)})`
  - `class BisoListRow({required String title, String? subtitle, Widget? leading, String? value, Widget? trailing, bool? showChevron, VoidCallback? onTap, bool destructive = false, int titleMaxLines = 2})`
  - `class BisoRowDivider({double indent = 60})`
  - Divider indent is 60 for rows with a tile (16 padding + 32 tile + 12 gap) and 16 for rows without one.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/presentation/widgets/biso/biso_icon_tile.dart';
import 'package:biso/presentation/widgets/biso/biso_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: PremiumTheme.build(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets('icon tiles use the accent fill and glyph', (tester) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            BisoIconTile(icon: CupertinoIcons.calendar, accent: BisoAccent.blue),
            BisoIconTile(icon: CupertinoIcons.gear),
          ],
        ),
      ),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(BisoIconTile),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((b) => (b.decoration as BoxDecoration).color)
        .toList();
    expect(boxes, [
      BisoAccent.blue.fixedFill,
      BisoPalette.light.surfaceRaised,
    ]);
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.calendar)).color,
      BisoAccent.blue.fixedGlyph,
    );
    expect(
      tester.getSize(find.byType(BisoIconTile).first),
      const Size(32, 32),
    );
  });

  testWidgets('rows show a chevron only when tappable without trailing', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        BisoListGroup(
          children: [
            BisoListRow(title: 'Orders', onTap: () => taps++),
            BisoListRow(
              title: 'Dark mode',
              trailing: Switch.adaptive(value: true, onChanged: (_) {}),
              onTap: () {},
            ),
            const BisoListRow(title: 'Email', value: 'student@bi.no'),
          ],
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.chevron_forward), findsOneWidget);
    await tester.tap(find.text('Orders'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(BisoListRow).first).height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('groups separate rows with inset hairlines', (tester) async {
    await tester.pumpWidget(
      app(
        const BisoListGroup(
          dividerIndent: 16,
          children: [
            BisoListRow(title: 'A'),
            BisoListRow(title: 'B'),
            BisoListRow(title: 'C'),
          ],
        ),
      ),
    );
    expect(find.byType(BisoRowDivider), findsNWidgets(2));
    expect(
      tester.widget<BisoRowDivider>(find.byType(BisoRowDivider).first).indent,
      16,
    );
  });

  testWidgets('a row reads as one semantic node with its value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const BisoListRow(title: 'Language', value: 'English')),
    );
    expect(find.bySemanticsLabel(RegExp('Language.*English', dotAll: true)),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sections title their content and can carry an action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        BisoSection(
          title: 'Favorites',
          action: TextButton(onPressed: () {}, child: const Text('See all')),
          footer: 'Pinned items',
          child: const BisoListGroup(children: [BisoListRow(title: 'A')]),
        ),
      ),
    );
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Pinned items'), findsOneWidget);
  });

  testWidgets('sliver groups build lazily', (tester) async {
    await tester.pumpWidget(
      app(
        CustomScrollView(
          slivers: [
            SliverBisoListGroup(
              itemCount: 1000,
              itemBuilder: (_, i) => BisoListRow(title: 'Row $i'),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(BisoListRow).evaluate().length, lessThan(40));
    expect(find.byType(BisoRowDivider), findsWidgets);
  });

  testWidgets('long text at large scale on a narrow screen fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        BisoListGroup(
          children: [
            BisoListRow(
              leading: const BisoIconTile(icon: CupertinoIcons.bag),
              title: 'A very long localized row title that wraps',
              subtitle: 'And a subtitle that is also rather long',
              value: 'NOK 1 299',
              onTap: () {},
            ),
          ],
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `flutter test test/presentation/widgets/biso/biso_list_test.dart`
Expected: FAIL at compile time: the widget files don't exist.

- [ ] **Step 3: Implement `biso_icon_tile.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

/// A small rounded square carrying a category glyph, like the tiles in iOS
/// Settings. Decorative: the row it sits in carries the meaning.
class BisoIconTile extends StatelessWidget {
  const BisoIconTile({
    super.key,
    required this.icon,
    this.accent = BisoAccent.neutral,
    this.size = 32,
  });

  final IconData icon;
  final BisoAccent accent;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: accent.fill(context),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * 0.625, color: accent.glyph(context)),
      ),
    ),
  );
}
```

- [ ] **Step 4: Implement `biso_list.dart`**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

const _groupRadius = 20.0;

/// A titled block of content, such as a grouped list.
class BisoSection extends StatelessWidget {
  const BisoSection({
    super.key,
    this.title,
    this.action,
    this.footer,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 0),
  });

  final String? title;

  /// A trailing control beside the title, such as "See all" or a menu.
  final Widget? action;
  final String? footer;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: text.headlineSmall?.copyWith(color: palette.ink),
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          child,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                footer!,
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class BisoRowDivider extends StatelessWidget {
  const BisoRowDivider({super.key, this.indent = 60});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: indent),
    child: Divider(
      height: 0.5,
      thickness: 0.5,
      color: BisoPalette.of(context).hairline,
    ),
  );
}

/// Rows on one rounded surface, separated by inset hairlines. For long or
/// unbounded lists use [SliverBisoListGroup].
class BisoListGroup extends StatelessWidget {
  const BisoListGroup({
    super.key,
    required this.children,
    this.dividerIndent = 60,
  });

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) => Material(
    color: BisoPalette.of(context).surface,
    borderRadius: BorderRadius.circular(_groupRadius),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) BisoRowDivider(indent: dividerIndent),
          children[i],
        ],
      ],
    ),
  );
}

/// A lazily built [BisoListGroup] for use inside a CustomScrollView.
class SliverBisoListGroup extends StatelessWidget {
  const SliverBisoListGroup({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = 60,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final surface = BisoPalette.of(context).surface;
    return SliverPadding(
      padding: margin,
      sliver: SliverList.separated(
        itemCount: itemCount,
        separatorBuilder: (context, _) => ColoredBox(
          color: surface,
          child: BisoRowDivider(indent: dividerIndent),
        ),
        itemBuilder: (context, index) {
          final first = index == 0;
          final last = index == itemCount - 1;
          return ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(first ? _groupRadius : 0),
              bottom: Radius.circular(last ? _groupRadius : 0),
            ),
            child: Material(color: surface, child: itemBuilder(context, index)),
          );
        },
      ),
    );
  }
}

class BisoListRow extends StatelessWidget {
  const BisoListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.showChevron,
    this.onTap,
    this.destructive = false,
    this.titleMaxLines = 2,
  });

  final String title;
  final String? subtitle;

  /// Usually a BisoIconTile or an avatar.
  final Widget? leading;

  /// Right-aligned secondary text, such as a setting's current value.
  final String? value;
  final Widget? trailing;

  /// Defaults to true when the row is tappable and has no [trailing].
  final bool? showChevron;
  final VoidCallback? onTap;
  final bool destructive;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: destructive ? palette.error : palette.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: text.bodyLarge?.copyWith(color: palette.muted),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                if (chevron) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: palette.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `flutter test test/presentation/widgets/biso/biso_list_test.dart`
Expected: PASS (7 tests).

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/biso/biso_icon_tile.dart lib/presentation/widgets/biso/biso_list.dart test/presentation/widgets/biso/biso_list_test.dart
git commit -m "Add grouped list rows, sections and category icon tiles" -m "<attribution lines>"
```

---

## Task 7: States, forms, bottom bar and the barrel export

**Files:**
- Create: `lib/presentation/widgets/biso/biso_states.dart`
- Create: `lib/presentation/widgets/biso/biso_form.dart`
- Create: `lib/presentation/widgets/biso/biso_bottom_bar.dart`
- Create: `lib/presentation/widgets/biso/biso.dart`
- Modify: `lib/generated/l10n/app_en.arb` and `lib/generated/l10n/app_no.arb` (add `loadingMessage`), then regenerate with `flutter gen-l10n`.
- Test: `test/presentation/widgets/biso/biso_states_form_test.dart`

**Interfaces:**
- Consumes: `BisoPalette`, `BisoAccent` (Task 1); `BisoIconTile`, `BisoSection`, `BisoListGroup` (Task 6); `AppLocalizations` (`retry`, `somethingWentWrongMessage`, and the new `loadingMessage`).
- Produces:
  - `class BisoEmptyState({required IconData icon, required String title, String? message, Widget? action, BisoAccent accent = BisoAccent.neutral})`
  - `class BisoErrorState({String? message, required VoidCallback onRetry})`
  - `class BisoSkeleton.rows({int count = 6})`, `BisoSkeleton.grid({int count = 6})`, `BisoSkeleton.card()`: static placeholders with no animation, so `pumpAndSettle` never hangs.
  - `class BisoFormGroup({String? title, String? footer, required List<Widget> children})`
  - `class BisoFormRow({required String label, required Widget child})`
  - `InputDecoration bisoInputDecoration(BuildContext context, {String? hintText, Widget? prefixIcon, Widget? suffixIcon, String? prefixText, String? suffixText})`
  - `class BisoBottomBar({required Widget child})`
  - Barrel `biso.dart`: screens import this single file.

- [ ] **Step 1: Add the localized string.**
  - In `app_en.arb`, before the closing `}`, add a comma after the current last entry, then:
    ```json
      "loadingMessage": "Loading",
      "@loadingMessage": {
        "description": "Accessibility label for skeleton placeholders while content loads"
      }
    ```
  - In `app_no.arb`, add the same, with `"loadingMessage": "Laster inn"`.
  - Run `flutter gen-l10n`. Expected: exit 0, and `lib/generated/l10n/app_localizations.dart` now contains `String get loadingMessage;`.

- [ ] **Step 2: Write the failing tests**

```dart
import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: PremiumTheme.build(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('error state offers a localized retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      app(BisoErrorState(onRetry: () => retried = true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('empty state shows its tile, title and message', (tester) async {
    await tester.pumpWidget(
      app(
        const BisoEmptyState(
          icon: CupertinoIcons.calendar,
          accent: BisoAccent.blue,
          title: 'No events',
          message: 'Check back soon',
        ),
      ),
    );
    expect(find.byType(BisoIconTile), findsOneWidget);
    expect(find.text('No events'), findsOneWidget);
    expect(find.text('Check back soon'), findsOneWidget);
  });

  testWidgets('skeletons are static and labelled for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            BisoSkeleton.rows(count: 3),
            BisoSkeleton.grid(count: 4),
            BisoSkeleton.card(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle(); // would time out if skeletons animated
    expect(find.bySemanticsLabel('Loading'), findsNWidgets(3));
    semantics.dispose();
  });

  testWidgets('form rows label fields and show validation below them', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      app(
        Form(
          key: formKey,
          child: Builder(
            builder: (context) => BisoFormGroup(
              title: 'Bank account',
              footer: 'Norwegian accounts have 11 digits',
              children: [
                BisoFormRow(
                  label: 'Account number',
                  child: TextFormField(
                    decoration: bisoInputDecoration(
                      context,
                      hintText: '1234 56 78901',
                    ),
                    validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Account number'), findsOneWidget);
    formKey.currentState!.validate();
    await tester.pump();
    final label = tester.getRect(find.text('Account number'));
    final error = tester.getRect(find.text('Required'));
    expect(error.top, greaterThan(label.bottom));
  });

  testWidgets('bottom bar is a floating surface card', (tester) async {
    await tester.pumpWidget(
      app(BisoBottomBar(child: FilledButton(onPressed: () {}, child: const Text('Buy')))),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BisoBottomBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, BisoPalette.light.surface);
  });

  testWidgets('states and forms fit large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            BisoErrorState(onRetry: () {}),
            const BisoSkeleton.grid(count: 2),
            BisoFormGroup(
              children: [
                BisoFormRow(label: 'Name', child: TextFormField()),
              ],
            ),
          ],
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run the tests to confirm they fail**

Run: `flutter test test/presentation/widgets/biso/biso_states_form_test.dart`
Expected: FAIL at compile time: `biso.dart` doesn't exist.

- [ ] **Step 4: Implement `biso_states.dart`**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'biso_icon_tile.dart';

class BisoEmptyState extends StatelessWidget {
  const BisoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accent = BisoAccent.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final BisoAccent accent;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BisoIconTile(icon: icon, accent: accent, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: palette.ink),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class BisoErrorState extends StatelessWidget {
  const BisoErrorState({super.key, this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BisoEmptyState(
      icon: CupertinoIcons.exclamationmark_triangle,
      title:
          message ?? l10n?.somethingWentWrongMessage ?? 'Something went wrong',
      action: FilledButton(
        onPressed: onRetry,
        child: Text(l10n?.retry ?? 'Retry'),
      ),
    );
  }
}

enum _SkeletonKind { rows, grid, card }

/// Static placeholders shaped like the content they stand in for.
class BisoSkeleton extends StatelessWidget {
  const BisoSkeleton.rows({super.key, this.count = 6})
    : _kind = _SkeletonKind.rows;
  const BisoSkeleton.grid({super.key, this.count = 6})
    : _kind = _SkeletonKind.grid;
  const BisoSkeleton.card({super.key}) : count = 1, _kind = _SkeletonKind.card;

  final int count;
  final _SkeletonKind _kind;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    Widget block({double? width, required double height, double radius = 8}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    Widget row() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          block(width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(width: 180, height: 12, radius: 6),
                const SizedBox(height: 8),
                block(width: 120, height: 10, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );

    Widget card() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        block(height: 160, radius: 18),
        const SizedBox(height: 12),
        block(width: 200, height: 14, radius: 7),
        const SizedBox(height: 8),
        block(width: 120, height: 10, radius: 5),
      ],
    );

    final Widget child = switch (_kind) {
      _SkeletonKind.rows => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [for (var i = 0; i < count; i++) row()]),
      ),
      _SkeletonKind.grid => Column(
        children: [
          for (var i = 0; i < count; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(child: card()),
                  const SizedBox(width: 12),
                  Expanded(child: i + 1 < count ? card() : const SizedBox()),
                ],
              ),
            ),
        ],
      ),
      _SkeletonKind.card => card(),
    };

    return Semantics(
      label: AppLocalizations.of(context)?.loadingMessage ?? 'Loading',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement `biso_form.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';
import 'biso_list.dart';

/// Form fields grouped on one surface, like iOS Settings.
class BisoFormGroup extends StatelessWidget {
  const BisoFormGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BisoSection(
    title: title,
    footer: footer,
    child: BisoListGroup(dividerIndent: 16, children: children),
  );
}

/// A label above its field. Validation messages render below the field.
class BisoFormRow extends StatelessWidget {
  const BisoFormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: BisoPalette.of(context).muted,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    ),
  );
}

/// Borderless decoration for fields inside a [BisoFormRow]; the group's
/// surface and hairlines already outline the field.
InputDecoration bisoInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? prefixText,
  String? suffixText,
}) {
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixText: prefixText,
    suffixText: suffixText,
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
  );
}
```

- [ ] **Step 6: Implement `biso_bottom_bar.dart` and the barrel**

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

/// A floating surface for BisoPage.bottomBar, holding the page's main action.
class BisoBottomBar extends StatelessWidget {
  const BisoBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.hairline, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: palette.ink.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}
```

`lib/presentation/widgets/biso/biso.dart`:

```dart
/// The BISO design system for screens: tokens, page scaffold and building
/// blocks. See docs/superpowers/specs/2026-09-11-glass-header-and-screen-redesign-design.md.
library;

export '../../../core/theme/biso_colors.dart';
export '../../../core/theme/biso_page.dart';
export '../../../core/theme/biso_page_header.dart'
    show
        BisoBackButton,
        BisoCapsuleButton,
        BisoGlassCapsule,
        BisoHeaderAction,
        BisoHeaderSearch,
        kBisoHeaderHeight;
export 'biso_bottom_bar.dart';
export 'biso_form.dart';
export 'biso_icon_tile.dart';
export 'biso_list.dart';
export 'biso_states.dart';
```

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `flutter test test/presentation/widgets/biso/biso_states_form_test.dart`
Expected: PASS (6 tests).

Run: `flutter analyze && flutter test`
Expected: no new issues; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/widgets/biso/ lib/generated/l10n/ test/presentation/widgets/biso/biso_states_form_test.dart
git commit -m "Add empty, error and loading states, grouped forms and the bottom bar" -m "<attribution lines>"
```

---

## Task 8: Screen test harness and design rules

**Files:**
- Create: `test/helpers/biso_screen_harness.dart`
- Create: `test/presentation/design_rules_test.dart`

**Interfaces:**
- Consumes: `PremiumTheme.build` (Task 2), `BisoNavigationScaffold` (existing), `BisoPage` (Task 5).
- Produces:
  - `Future<void> pumpBisoScreen(WidgetTester tester, Widget screen, {List<Override> overrides = const [], Brightness brightness = Brightness.light, double textScale = 1, bool inShell = true, bool routed = false, Size size = const Size(390, 844)})`
  - `Future<void> expectBuildsCleanly(WidgetTester tester, Widget Function() screen, {List<Override> overrides = const [], bool inShell = true, bool routed = false})`
  - `const migratedFiles` in `design_rules_test.dart`. Every later task appends its files to this list.

- [ ] **Step 1: Write the design-rules test.** It fails first on its scanner self-test, which calls a function that doesn't exist yet. Then implement the function in the same file.

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files already moved onto the BISO design system. Each migration task adds
/// its files here, and from then on the rules below hold for them.
const migratedFiles = <String>[
  'lib/core/theme/biso_page.dart',
  'lib/core/theme/biso_page_header.dart',
  'lib/presentation/widgets/biso/biso_bottom_bar.dart',
  'lib/presentation/widgets/biso/biso_form.dart',
  'lib/presentation/widgets/biso/biso_icon_tile.dart',
  'lib/presentation/widgets/biso/biso_list.dart',
  'lib/presentation/widgets/biso/biso_states.dart',
];

final _lineRules = <String, RegExp>{
  'Material Icons (use CupertinoIcons or add // biso:allow)': RegExp(
    r'(?<![A-Za-z])Icons\.',
  ),
  'off-brand AppColors (use BisoAccent or BisoPalette)': RegExp(
    r'AppColors\.(orange|green|purple|pink|red|yellow|emerald|forest|royal|amethyst|burnished|copper|warmGold|sunGold|deepAmber|strongGold|defaultGold|accentGold|success|warning|error|info)',
  ),
  'brightness color branch (use BisoPalette)': RegExp(r'isDark\s*\?'),
  'manual navigation clearance (BisoPage owns it)': RegExp(
    r'BisoNavigationInset\.',
  ),
};

/// Finds Museo styles (display*, headlineLarge, headlineMedium) given any
/// weight other than 300 inside their copyWith call.
List<String> museoWeightViolations(String source) {
  final start = RegExp(
    r'\b(displayLarge|displayMedium|displaySmall|headlineLarge|headlineMedium)\b\??\.copyWith\(',
  );
  final problems = <String>[];
  for (final match in start.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    while (i < source.length && depth > 0) {
      final char = source[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      i++;
    }
    final args = source.substring(match.end, i - 1);
    final weight = RegExp(r'fontWeight:\s*FontWeight\.(\w+)').firstMatch(args);
    if (weight != null && weight.group(1) != 'w300') {
      problems.add('${match.group(1)} with FontWeight.${weight.group(1)}');
    }
  }
  return problems;
}

void main() {
  test('Museo weight scan catches bold large type only', () {
    expect(
      museoWeightViolations(
        't.headlineLarge?.copyWith(color: c.withValues(alpha: 0.5), fontWeight: FontWeight.bold)',
      ),
      isNotEmpty,
    );
    expect(
      museoWeightViolations('t.headlineLarge?.copyWith(fontWeight: FontWeight.w300)'),
      isEmpty,
    );
    expect(
      museoWeightViolations('t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)'),
      isEmpty,
    );
  });

  for (final path in migratedFiles) {
    test('$path follows the BISO design rules', () {
      final lines = File(path).readAsLinesSync();
      final problems = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('biso:allow')) continue;
        for (final rule in _lineRules.entries) {
          // The page scaffold itself is what owns navigation clearance.
          if (rule.key.startsWith('manual navigation') &&
              path.startsWith('lib/core/')) {
            continue;
          }
          if (rule.value.hasMatch(lines[i])) {
            problems.add('${i + 1}: ${rule.key}: ${lines[i].trim()}');
          }
        }
      }
      problems.addAll(museoWeightViolations(lines.join('\n')));
      expect(problems, isEmpty);
    });
  }
}
```

Run: `flutter test test/presentation/design_rules_test.dart`
Expected: PASS (1 scanner test plus 7 file tests). If a foundation file breaks a rule, fix the file, not the rule. The Material `Badge`, `IconButton`, `Divider` and `Switch` widgets are fine; the rule only matches the `Icons.` class.

- [ ] **Step 2: Write the harness**

```dart
import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _tabs = [
  BisoNavDestination(icon: CupertinoIcons.house, label: 'Home'),
  BisoNavDestination(icon: CupertinoIcons.square_grid_2x2, label: 'Explore'),
  BisoNavDestination(icon: CupertinoIcons.person_crop_circle, label: 'Profile'),
];

/// Pumps [screen] the way the app shows it: themed and localized, on a
/// 390x844 phone with a notch and home indicator, inside the tab shell.
/// Set [routed] for screens that read GoRouterState during build.
Future<void> pumpBisoScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool inShell = true,
  bool routed = false,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  Widget framed(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
      textScaler: TextScaler.linear(textScale),
    ),
    child: inShell
        ? BisoNavigationScaffold(
            currentIndex: 1,
            routeKey: 'test',
            destinations: _tabs,
            onSelected: (_) {},
            child: screen,
          )
        : screen,
  );

  final themeMode = brightness == Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: routed
          ? MaterialApp.router(
              theme: PremiumTheme.build(Brightness.light),
              darkTheme: PremiumTheme.build(Brightness.dark),
              themeMode: themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: GoRouter(
                routes: [
                  GoRoute(path: '/', builder: (context, _) => framed(context)),
                ],
              ),
            )
          : MaterialApp(
              theme: PremiumTheme.build(Brightness.light),
              darkTheme: PremiumTheme.build(Brightness.dark),
              themeMode: themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(builder: framed),
            ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pumps the screen in light and dark, at normal and enlarged text, and fails
/// on any layout exception or if the screen is not built on BisoPage.
Future<void> expectBuildsCleanly(
  WidgetTester tester,
  Widget Function() screen, {
  List<Override> overrides = const [],
  bool inShell = true,
  bool routed = false,
}) async {
  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 1.6]) {
      await pumpBisoScreen(
        tester,
        screen(),
        overrides: overrides,
        brightness: brightness,
        textScale: textScale,
        inShell: inShell,
        routed: routed,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$brightness at text scale $textScale',
      );
      expect(find.byType(BisoPage), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }
  }
}
```

- [ ] **Step 3: Check the harness against a known page.** Create `test/helpers/biso_screen_harness_test.dart`:

```dart
import 'package:biso/core/theme/biso_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'biso_screen_harness.dart';

void main() {
  testWidgets('harness pumps a BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const BisoPage(
        title: 'Harness',
        slivers: [SliverToBoxAdapter(child: Text('Content'))],
      ),
    );
  });
}
```

Run: `flutter test test/helpers/biso_screen_harness_test.dart test/presentation/design_rules_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/helpers/ test/presentation/design_rules_test.dart
git commit -m "Add a screen test harness and design rules for migrated files" -m "<attribution lines>"
```

---

## Task 9: Debug deep link for scrolled screenshots

The simulator can't be scrolled from the command line. In debug builds, a deep link opens any route with its page pre-scrolled, so every header can be screenshotted at rest and scrolled with `xcrun simctl`.

**Files:**
- Modify: `lib/core/theme/biso_page.dart` (add `BisoPageDebug` and a hook in `_BisoPageState`)
- Modify: `lib/data/services/deep_link_service.dart` (add a `debug` host)
- Test: `test/core/theme/biso_page_test.dart` (add one test)

**Interfaces:**
- Produces: `class BisoPageDebug { static final ValueNotifier<double> initialScroll; }` and the URL `biso://debug/open?path=<route>&scroll=<points>`.

- [ ] **Step 1: Write the failing test.** Append to `biso_page_test.dart`:

```dart
  testWidgets('debug initial scroll pre-scrolls the next page', (tester) async {
    phone(tester);
    BisoPageDebug.initialScroll.value = 300;
    addTearDown(() => BisoPageDebug.initialScroll.value = 0);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      300,
    );
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });
```

Run: `flutter test test/core/theme/biso_page_test.dart --plain-name 'debug initial scroll'`
Expected: FAIL at compile time: `BisoPageDebug` isn't defined.

- [ ] **Step 2: Implement the hook.** In `biso_page.dart`:
  - Add `import 'dart:async';` and `import 'package:flutter/foundation.dart';`.
  - Add this class above `BisoPage`:

```dart
/// Debug builds only. A scroll offset applied to the next BisoPage built, so
/// a scrolled header can be screenshotted on a simulator without gestures.
class BisoPageDebug {
  BisoPageDebug._();

  static final ValueNotifier<double> initialScroll = ValueNotifier(0);
}
```

  - Add to `_BisoPageState`:

```dart
  Timer? _debugScroll;

  @override
  void initState() {
    super.initState();
    final target = BisoPageDebug.initialScroll.value;
    if (kDebugMode && target > 0 && widget.slivers != null) {
      // Content usually arrives asynchronously; wait for it before jumping.
      _debugScroll = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final controller =
            widget.controller ?? PrimaryScrollController.maybeOf(context);
        if (controller == null || !controller.hasClients) return;
        final position = controller.position;
        controller.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      });
    }
  }
```

  - Add `_debugScroll?.cancel();` as the first line of `dispose()`.

`CustomScrollView` uses the route's `PrimaryScrollController` when no controller is passed, so the jump reaches it. If the test finds no clients, pass `primary: widget.controller == null` explicitly to the `CustomScrollView`.

- [ ] **Step 3: Implement the deep link.** In `deep_link_service.dart`:
  - Add `import '../../core/theme/biso_page.dart';`.
  - Add a case to the `switch (uri.host)` in `_handleDeepLink`, before `default:`:

```dart
        case 'debug':
          if (kDebugMode) _handleDebugDeepLink(uri);
          break;
```

  - Add the handler to the class:

```dart
  /// Debug builds only: `biso://debug/open?path=/explore/products&scroll=320`
  /// opens a route with its page pre-scrolled, so each screen's header can be
  /// screenshotted from the command line with `xcrun simctl openurl`.
  void _handleDebugDeepLink(Uri uri) {
    final context = navigatorKey.currentContext;
    final path = uri.queryParameters['path'];
    if (context == null || path == null) return;
    BisoPageDebug.initialScroll.value =
        double.tryParse(uri.queryParameters['scroll'] ?? '') ?? 0;
    GoRouter.of(context).go(path);
  }
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/theme/biso_page_test.dart && flutter analyze`
Expected: PASS; no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/biso_page.dart lib/data/services/deep_link_service.dart test/core/theme/biso_page_test.dart
git commit -m "Add a debug deep link that opens a route pre-scrolled" -m "<attribution lines>"
```

### Screenshot procedure (used by later tasks)

Run once per session:

```bash
xcrun simctl list devices booted            # note the booted device id
flutter run -d <device-id>                  # keep running in the background
```

Then, per screen (URL-encode the path):

```bash
S=/private/tmp/claude-501/-Users-markus-Documents-dev-BISO-Flutter/<session>/scratchpad
xcrun simctl openurl booted "biso://debug/open?path=%2Fexplore%2Fproducts&scroll=0"
sleep 4 && xcrun simctl io booted screenshot "$S/products-rest.png"
xcrun simctl openurl booted "biso://debug/open?path=%2Fexplore%2Fproducts&scroll=400"
sleep 4 && xcrun simctl io booted screenshot "$S/products-scrolled.png"
xcrun simctl ui booted appearance dark      # repeat both shots, then:
xcrun simctl ui booted appearance light
```

Read each PNG and check:
- at rest there is no band
- when scrolled, a blurred band and hairline show, content is visible through the band, and the compact title appears
- glass buttons render over the band without black boxes
- nothing is hidden behind the tab bar at the end of a list

Screens that need a signed-in user: ask the user to sign in on the simulator once. Screens reached only by `MaterialPageRoute` (settings pages, edit profile, chats): ask the user to open them, then take the screenshot.

---

## Task 10: Remove dead code

**Files** (each verified unused on 2026-09-11; re-verify before deleting):
- Delete:
  - `lib/presentation/screens/home/home_screen.dart`
  - `lib/presentation/widgets/ai_chat/ai_assistant_fab.dart`
  - `lib/presentation/widgets/ai_chat/future_tool_preview.dart`
  - `lib/presentation/widgets/ai_chat/sharepoint_search_widget.dart`
  - `lib/presentation/widgets/ai_chat/tool_output_widget.dart`
  - `lib/presentation/widgets/membership_status_widget.dart`
  - `lib/presentation/widgets/premium/large_event_hero.dart`
  - `lib/presentation/widgets/premium/premium_navigation.dart`
  - `lib/presentation/widgets/premium/wonderous_bottom_nav.dart`
  - `lib/presentation/widgets/premium/wonderous_story_card.dart`
  - `lib/core/theme/app_theme.dart`
- Modify:
  - `lib/presentation/widgets/premium/premium_components.dart`: remove `PremiumCard`, `PremiumTextField`, `PremiumChip`, `PremiumSwitch`.
  - `lib/presentation/widgets/premium/premium_layouts.dart`: remove `PremiumAppBar`, `PremiumIconButton`, `PremiumList`, `PremiumHero`; change `PremiumScaffold.appBar` to `PreferredSizeWidget?`.
  - `lib/core/theme/biso_glass.dart`: remove `BisoGlassScope`, `BisoGlassNavItem`, `BisoGlassBottomNavigation`.
  - `lib/presentation/screens/home/premium_home_screen.dart`: remove the unused `PremiumHomeScreen` and `_PremiumHomeScreenState` (lines 36–80); `main.dart` renders `PremiumHomePage` directly.
  - `lib/presentation/screens/ai_chat/README.md`: remove references to deleted widgets.

- [ ] **Step 1: Re-verify nothing references them.** For each deleted file, check it isn't imported:

```bash
for f in home/home_screen ai_chat/ai_assistant_fab ai_chat/future_tool_preview ai_chat/sharepoint_search_widget ai_chat/tool_output_widget membership_status_widget premium/large_event_hero premium/premium_navigation premium/wonderous_bottom_nav premium/wonderous_story_card app_theme; do
  echo "== $f"; rg -n "$(basename $f)\.dart" lib test --glob '!**/README.md'
done
for c in PremiumCard PremiumTextField PremiumChip PremiumSwitch PremiumAppBar PremiumIconButton PremiumList PremiumHero BisoGlassScope BisoGlassNavItem BisoGlassBottomNavigation PremiumHomeScreen; do
  echo "== $c"; rg -n "\b$c\b" lib test
done
```

Expected: each file is referenced only by itself or by another file in this list, and each class only by its own declaration, by other listed classes, or (for `PremiumAppBar`) by `PremiumScaffold`'s field type. Anything else means stop and leave that item in place.

- [ ] **Step 2: Delete the files and classes listed above.** Remove imports that become unused.
- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: no new issues; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A lib test
git commit -m "Remove unused screens, widgets and legacy glass helpers" -m "<attribution lines>"
```

---

## Screen Migration Recipe

Tasks 11–36 migrate screens. Each task names its screen-specific decisions; this recipe covers everything else. Read the screen file completely before editing it.

**R1. Scaffold.**
- Replace `Scaffold` + `AppBar`/`SliverAppBar`/`BisoSearchAppBar`/`BisoGlassAppBar` with `BisoPage` (import `package:biso/presentation/widgets/biso/biso.dart`, relative path from the screen).
- Early returns (loading, error, unauthenticated) also return a `BisoPage`, with `largeTitle: false` and a `slivers:` body:
  - loading: `SliverToBoxAdapter(child: BisoSkeleton.rows())` (or `.grid()` / `.card()`)
  - error: `SliverFillRemaining(hasScrollBody: false, child: BisoErrorState(onRetry: …))`
- `leading`:
  - Leave it unset when the route is pushed (the automatic back button).
  - Pass `BisoBackButton(onPressed: () => NavigationUtils.safeGoBack(context, fallbackRoute: '<parent>'))` where the screen already used `NavigationUtils` or a custom back.

**R2. Scroll body.**
- Convert to `slivers:` so content passes under the header:
  - `ListView.builder/separated` of plain rows → `SliverBisoListGroup`, or `SliverList.separated` for cards
  - `GridView.builder` → `SliverPadding(padding: EdgeInsets.symmetric(horizontal: 16), sliver: SliverGrid.builder(...))`
  - fixed widgets above a list (chips, summaries, search fields, filters) → `SliverToBoxAdapter`
  - `SingleChildScrollView(child: Column(...))` → one or more `SliverToBoxAdapter`s, split per section
- Use `body:` only where the task says so (chats, camera, PageView).
- Delete every `BisoNavigationInset` use, top/bottom `SafeArea`, and trailing spacer in the screen; `BisoPage` owns clearance.

**R3. Refresh and actions.**
- `RefreshIndicator(onRefresh: f)` → `BisoPage(onRefresh: f)`.
- AppBar `actions` and FABs → `BisoHeaderAction`s, unless the task says otherwise.
- `CartIconButton` → `BisoHeaderAction(icon: CupertinoIcons.bag, tooltip: <existing cart tooltip or l10n>, badge: ref.watch(cartItemCountProvider), onPressed: () => context.push('/explore/products/cart'))`.

**R4. Pinned bars.**
- `bottomNavigationBar:` or bottom-anchored Columns (purchase bars, cart summaries) → `bottomBar: BisoBottomBar(child: …)`.
- Composers → `bottomBar:` holding a `BisoChrome` capsule (Tasks 29 and 31).

**R5. Surfaces.** `BisoGlassCard`/`BisoGlassContainer`/`Card`/custom white `Container`s:
- lists of rows → `BisoListGroup` + `BisoListRow`
- rich cards (images, prices) → `Material(color: palette.surface, borderRadius: BorderRadius.circular(20), clipBehavior: Clip.antiAlias)`
- Remove decorative gradients and shadows from content. Photos may keep a dark scrim: `Colors.black.withValues(alpha: 0.35)`.

**R6. Colors.** Take `final palette = BisoPalette.of(context);` once per build. Map by meaning, not by the old hue:

| Old | New |
|---|---|
| text colors (`onSurface`, `charcoalBlack`, `pearl`, `strongBlue` as text) | `palette.ink` |
| secondary text (`stoneGray`, `mist`, `onSurfaceVariant`, `gray*`) | `palette.muted` |
| page backgrounds (`pearl`, `charcoalBlack`, `Colors.white` pages) | `palette.paper` (usually just drop it) |
| card/sheet backgrounds (`Colors.white`, `smokeGray`, `surfaceDark`) | `palette.surface` |
| fills, wells, chips (`cloud`, `iceBlue`, `subtleBlue`) | `palette.surfaceRaised` |
| borders, dividers (`outlineVariant`, `cloud`) | `palette.hairline` |
| links, selected, active, progress | `palette.link` |
| paid, approved, verified, success | `palette.success` |
| pending, draft, warning | `palette.warning` |
| rejected, failed, destructive, `Colors.red`, `AppColors.error` | `palette.error` |
| category decoration: events/departures/calendar | `BisoAccent.blue` |
| shop/orders/membership | `BisoAccent.gold` |
| units/clubs/people/volunteering/chat | `BisoAccent.teal` |
| expenses/payment/reimbursement | `BisoAccent.coral` |
| help/AI/info | `BisoAccent.violet` |
| anything else decorative | `BisoAccent.neutral` |
| campus-specific colors (`_getCampusColor`) | removed; use `palette.link` |

Delete `isDark` variables once nothing uses them.

**R7. Icons.** Material → Cupertino:

| Material | Cupertino | Material | Cupertino |
|---|---|---|---|
| arrow_back | (BisoPage back) / chevron_back | arrow_forward_ios | chevron_forward |
| close | xmark | search | search |
| refresh | arrow_clockwise | error_outline | exclamationmark_circle |
| info_outline | info_circle | check_circle | checkmark_circle_fill |
| add | plus | edit | pencil |
| delete, delete_outline | trash | share | share |
| favorite | heart_fill | favorite_border | heart |
| shopping_bag(_outlined) | bag_fill / bag | shopping_cart | cart |
| person | person_fill | people, group | person_2 |
| location_on | location_solid | calendar_today, event | calendar |
| access_time, schedule | clock | email(_outlined) | mail |
| phone | phone | home | house |
| settings | gear | notifications | bell |
| logout | square_arrow_right | camera_alt | camera |
| photo, image | photo | attach_file | paperclip |
| send | paperplane_fill | receipt, receipt_long | doc_text |
| payment, credit_card | creditcard | school | book |
| language, web, public | globe | lock | lock |
| visibility | eye | more_vert, more_horiz | ellipsis |
| filter_list | line_horizontal_3_decrease | sort | arrow_up_arrow_down |
| star | star_fill | link | link |
| download | arrow_down_circle | upload | arrow_up_circle |
| qr_code_scanner | qrcode_viewfinder | check | checkmark |
| warning | exclamationmark_triangle | psychology, smart_toy | sparkles |
| work | briefcase | volunteer_activism | hand_raised |
| directions_bus, train | bus / tram_fill | storefront | bag |
| save | tray_arrow_down | local_offer | tag |

If an icon is missing from this table, find the nearest name in `/Users/markus/Documents/dev/flutter/packages/flutter/lib/src/cupertino/icons.dart`. The analyzer rejects names that don't exist.

**R8. Type.**
- Prices, totals, big counts and hero titles use `headlineMedium` / `headlineLarge` / `displaySmall` **without** `fontWeight`.
- Section titles go through `BisoSection`.
- Rows use `BisoListRow` or `titleMedium` / `bodyMedium`.
- Remove `fontWeight` from any Museo style.

**R9. Behavior stays.** Keep every provider read, callback, navigation call, validation, dialog, sheet, snackbar and `PopScope`. Restyle modal sheets by removing their custom colors and shapes (the theme styles them) and building their content from groups and rows.

**R10. Tests for every screen task.**
1. Add the migrated file(s) to `migratedFiles` in `test/presentation/design_rules_test.dart`.
2. Add a smoke test at `test/presentation/screens/<area>/<screen>_design_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';
// import the screen and its providers

void main() {
  testWidgets('<Screen> builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const <Screen>(/* args */),
      overrides: [
        // One override per provider the screen watches, with fixed data.
        // Find them with: rg -n "ref\.(watch|read|listen)\(" <screen file>
      ],
    );
  });
}
```

   - Build fake data from the models' `fromJson`/constructors, as `test/presentation/widgets/navigation_content_clearance_test.dart` does.
   - Fake services the same way (`implements` + `noSuchMethod`).
   - If the screen starts a periodic `Timer`, pump past it or override the provider that owns it. The test must not end with pending timers.

3. Keep the existing tests that touch the screen passing. Update finders (for example `ListView` → `CustomScrollView`) without weakening what they assert.
4. Run `flutter test <new test> test/presentation/design_rules_test.dart <existing screen tests>`, then `flutter analyze`, then the full `flutter test`.
5. Take the screenshots (Task 9 procedure) at rest and scrolled, light and dark, and inspect them before committing.

---

## Task 11: Home

**Files:**
- Modify: `lib/presentation/screens/home/premium_home_screen.dart` (`PremiumHomePage` and helpers; `PremiumAuthRequiredPage` and its dialog)
- Modify: `lib/presentation/widgets/dynamic_hero_carousel.dart` (`_Cover`)
- Modify: `lib/presentation/widgets/home/discovery_sections.dart` (tokens only)
- Modify: `lib/presentation/widgets/premium/premium_layouts.dart` (only if `PremiumSection` still carries hardcoded colors used by Home)
- Test: `test/presentation/screens/home/home_design_test.dart`, `test/presentation/widgets/campus_cover_test.dart` (keep passing)

**Decisions:**
- **Page:** `PremiumHomePage.build` returns `BisoPage(overImage: true, title: campus.name, largeTitle: false, actions: [notifications], slivers: [...])`.
  - `slivers` keep today's order: `DynamicHeroCarousel`, events, webshop, jobs. Drop the trailing `BisoNavigationInset` spacer (R2).
  - The compact title (campus name) appears once the cover has scrolled under the header.
- **Notifications move into the header:**
  - Home header action: `BisoHeaderAction(icon: CupertinoIcons.bell, tooltip: l10n.notificationsMessage, badge: ref.watch(unreadCountProvider), onPressed: () => context.push('/notifications'))`.
  - Remove the bell `IconButton` from `_Cover` (lines ~95–101). The campus switch button stays in the cover.
  - In `campus_cover_test.dart`, remove only assertions about the bell, if there are any.
- **Sections:** Home doesn't use `BisoSection`, because its horizontal carousels need to run edge to edge while `BisoSection` insets its child. Replace `PremiumSection` in `_buildPremiumContentSection` with:

  ```dart
  Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: text.headlineSmall?.copyWith(color: palette.ink)),
              ),
            ),
            TextButton(onPressed: onViewAll, child: Text(l10n.viewAllMessage)),
          ],
        ),
      ),
      <existing asyncData.when(...) content>,
    ],
  )
  ```

  The subtitle and section icon are dropped; GitHub-style sections are title-only.
  - Replace `_PremiumEmptyState`, `_PremiumErrorState` and `_PremiumLoadingCarousel` with `BisoEmptyState`, `BisoErrorState` and `BisoSkeleton.card()`.
- **Colors and type:**
  - Remove the Museo bold violations in this file (`headlineLarge w700`, `headlineMedium w700`) and in `dynamic_hero_carousel.dart` (`headlineLarge w600`).
  - The campus switcher modal (`_CampusSwitcherModal`, `_CampusModalCard`) uses `BisoListGroup` + `BisoListRow` with the campus name, a `CupertinoIcons.checkmark` trailing icon for the selected campus, and `palette.link` for that checkmark. Remove `_getCampusColor`.
- **Unauthenticated profile (`PremiumAuthRequiredPage`):** `BisoPage(title: title, slivers: [SliverFillRemaining(hasScrollBody: false, child: BisoEmptyState(icon: icon, title: title, message: description, action: FilledButton(...existing sign-in action...)))])`.
- **Unused code:** remove `_PremiumStatsRow`, `_PremiumStatItem`, `_PremiumQuickActions`, `_PremiumActionCard` and `_PatternPainter` if `rg` shows they are only referenced from the commented-out block, and remove that commented-out block.
- **Smoke test overrides:** follow R10 for the campus, events, webshop, jobs, auth and unread-count providers. Use `routed: true` because the page calls `context.go` / `context.push` and reads `GoRouter` in callbacks.

- [ ] **Step 1:** Write `home_design_test.dart` with `expectBuildsCleanly(tester, () => PremiumHomePage(navigateToTab: (_) {}), routed: true, overrides: [...])`, plus this test:

```dart
  testWidgets('home header carries notifications with the unread badge', (tester) async {
    await pumpBisoScreen(
      tester,
      PremiumHomePage(navigateToTab: (_) {}),
      routed: true,
      overrides: [/* same overrides */ unreadCountProvider.overrideWithValue(4)],
    );
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
```

Add `'lib/presentation/screens/home/premium_home_screen.dart'`, `'lib/presentation/widgets/dynamic_hero_carousel.dart'` and `'lib/presentation/widgets/home/discovery_sections.dart'` to `migratedFiles`.

- [ ] **Step 2:** Run both tests. Expected: FAIL (the screen isn't a `BisoPage`, the tooltip is in the cover without a badge, and the rules report violations).
- [ ] **Step 3:** Apply the decisions above and R1–R9.
- [ ] **Step 4:** Run the new test, the design rules, `test/presentation/widgets/campus_cover_test.dart`, `test/presentation/widgets/discovery_sections_test.dart`, then `flutter analyze` and `flutter test`. Expected: all pass.
- [ ] **Step 5:** Screenshots of `/home` at `scroll=0` and `scroll=500`, light and dark. At rest the cover runs under the status bar with the glass bell capsule over it; scrolled, the blurred band shows the campus name.
- [ ] **Step 6:** Commit: `git commit -m "Move Home onto BisoPage with notifications in the glass header"`.

---

## Task 12: Explore, and the compositing check

**Files:**
- Modify: `lib/presentation/screens/explore/explore_screen.dart`
- Test: `test/presentation/screens/explore/explore_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: l10n.explore, search: BisoHeaderSearch(hintText: l10n.searchExploreMessage, onChanged: (v) => setState(() => _query = v.trim().toLowerCase())), actions: [language], slivers: [...])`.
- **Language switch:**
  - Header action `BisoHeaderAction(icon: CupertinoIcons.globe, tooltip: l10n.languageMessage, onPressed: _showLanguageSheet)`.
  - `_showLanguageSheet` opens `showModalBottomSheet` containing a `BisoListGroup` with two `BisoListRow`s (English and Norsk). The current one gets `trailing: Icon(CupertinoIcons.checkmark, color: palette.link)`, and tapping calls `ref.read(localeProvider.notifier).setLocale(code)` and closes the sheet.
  - Delete `_LanguageSwitcher`.
- **Slivers:**
  1. the large event banner (`if (_query.isEmpty)`), kept as an image card with 16 pt margins
  2. intro text
  3. the categories group
  4. the quick links group
  5. the campus contact section
- **Categories:** `_CategoryCard` becomes `BisoListRow(leading: BisoIconTile(icon: …, accent: …), title:, subtitle:, onTap:)` inside `BisoListGroup` in a `BisoSection`. Accents:

  | Category | Accent |
  |---|---|
  | events | blue |
  | departures | blue |
  | shop | gold |
  | units | teal |
  | expenses | coral |
  | volunteer | teal |
  | AI assistant | violet |

- **Quick links:** rows with `BisoAccent.neutral` tiles (website: `globe`, academic calendar: `calendar` with `BisoAccent.blue`). The remaining quick links and contact rows map their icons with R7.
- **No results:** when the query matches nothing, show `BisoEmptyState(icon: CupertinoIcons.search, title: l10n.noSearchResultsMessage)`.

- [ ] **Step 1:** Write `explore_design_test.dart`. Use `expectBuildsCleanly` with overrides for `featuredLargeEventProvider`, `appConfigProvider`, `localeProvider`, `selectedCampusProvider` and any others the screen watches (`rg -n "ref\.(watch|read)" explore_screen.dart`). Add these tests:

```dart
  testWidgets('categories are accent-tiled rows and search filters them', (tester) async {
    await pumpBisoScreen(tester, const ExploreScreen(), overrides: [/* … */]);
    expect(find.byType(BisoIconTile), findsWidgets);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BisoEmptyState), findsOneWidget);
  });

  testWidgets('language action opens a two-option sheet', (tester) async {
    await pumpBisoScreen(tester, const ExploreScreen(), overrides: [/* … */]);
    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Norsk'), findsOneWidget);
  });
```

Add the screen to `migratedFiles`.

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement per the decisions and R1–R9.
- [ ] **Step 4:** Run the new test, the design rules, `flutter analyze` and `flutter test`. Expected: pass.
- [ ] **Step 5: Compositing check (spec §5 risk).** Run the app on the simulator and open `/explore` at `scroll=0` and `scroll=500`, light and dark.
  - Confirm in the screenshots that:
    - the band blurs the rows underneath
    - the glass capsule (search + globe) renders fully above the band, with no black rectangle, clipped corners or missing icons
    - the tab bar still shows content through it
  - Then ask the user to scroll Explore up and down on the simulator and report any flicker of the capsule while the band fades.
  - **If the capsule composites incorrectly:** change `BisoGlassCapsule.build` so that, when the ambient `BisoPageHeader` band is visible, it wraps its row in `DecoratedBox(color: palette.surface, borderRadius: 24)` instead of `BisoChrome`. Pass `bandVisible` down from `_toolbar` as a constructor flag. Add a header test for that fallback, and note the fallback in the spec's Risks section.
- [ ] **Step 6:** Commit: `git commit -m "Move Explore onto BisoPage with accent-tiled directory rows"`.

---

## Task 13: Events

**Files:**
- Modify: `lib/presentation/screens/explore/events_screen.dart`
- Test: `test/presentation/screens/explore/events_design_test.dart`
- Keep passing: `events_screen_date_format_test.dart`, `events_screen_locale_reload_test.dart`, `events_screen_staleness_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: l10n.eventsMessage, leading: BisoBackButton(onPressed: () => NavigationUtils.safeGoBack(context, fallbackRoute: '/explore')), search: BisoHeaderSearch(hintText: l10n.searchEventsMessage, initialQuery: ref.read(eventsSearchTermProvider) ?? '', onChanged: _applySearch), onRefresh: _reload, controller: _scrollController, slivers: [...])`.
  - The existing `_scrollController` pagination listener keeps working through `controller:`.
  - Remove the `Divider(height: 1)` and the `Column`/`Expanded` wrapper.
- **States:**
  - `_isLoading` → `SliverToBoxAdapter(child: Column(children: [BisoSkeleton.card(), BisoSkeleton.card()]))`.
  - Empty → `SliverFillRemaining(hasScrollBody: false, child: BisoEmptyState(icon: CupertinoIcons.calendar, accent: BisoAccent.blue, title: 'No Events Found', message: 'There are no events matching your criteria.'))`. The strings are copied verbatim, since they already exist hardcoded.
  - The list → `SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverList.separated(...))` using the existing event card builder, restyled per R5 (image top, date in `palette.link` with `labelLarge`, title `titleLarge`, venue `bodyMedium` muted). Keep the pagination footer item.
- **Detail sheet** (`ListView` at ~line 748): restyle per R9.
- **Existing tests:** if they find `ListView` or `RefreshIndicator` by type, update them to `CustomScrollView` / `RefreshIndicator` (still present through `onRefresh`).

- [ ] **Step 1:** Write `events_design_test.dart` (`expectBuildsCleanly` with the providers the screen watches, `routed: true`). Add a test that scrolling to the bottom still triggers the next page load. The pagination provider or service fake records a second fetch. Copy how `events_screen_staleness_test.dart` fakes the service. Add the file to `migratedFiles`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the new test, the three existing events tests, the design rules, `flutter analyze` and `flutter test`. Expected: pass.
- [ ] **Step 5:** Screenshots of `/explore/events` at rest and scrolled, light and dark.
- [ ] **Step 6:** Commit: `git commit -m "Move Events onto BisoPage with header search and pull to refresh"`.

---

## Task 14: Profile

**Files:**
- Modify: `lib/presentation/screens/profile/profile_screen.dart`
- Test: `test/presentation/screens/profile/profile_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: l10n.profile, actions: [BisoHeaderAction(icon: CupertinoIcons.gear, tooltip: l10n.settingsMessage, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())))], slivers: [...])`.
  - Loading state: `BisoPage(title: l10n.profile, largeTitle: false, slivers: [SliverToBoxAdapter(child: BisoSkeleton.rows(count: 4))])`.
- **Membership card:** keep the navy card; it is brand, not decoration.
  - `color: palette.primary` in light is navy; in dark `primary` is blue, so use `AppColors.biNavy` explicitly with a `// biso:allow brand card` comment.
  - Replace `Color(0xFF20405D)` with `Colors.white.withValues(alpha: 0.12)`.
  - Names stay `headlineSmall` (system font).
- **Completion banner:** `BisoSection(child: BisoListGroup(children: [BisoListRow(leading: const BisoIconTile(icon: CupertinoIcons.info_circle, accent: BisoAccent.violet), title: 'Complete Your Profile', subtitle: 'Get the most out of BISO…'), Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => context.push('/onboarding'), child: const Text('Complete Profile'))))]))`.
- **Quick actions:** the two `_ActionCard`s become a `BisoListGroup`:
  - `BisoListRow(leading: BisoIconTile(icon: CupertinoIcons.pencil), title: 'Edit Profile', onTap: …)`
  - `BisoListRow(leading: BisoIconTile(icon: CupertinoIcons.book, accent: BisoAccent.gold), title: 'Student ID', subtitle: 'We're improving Student ID. Thanks for your patience.', showChevron: false)`, with no `onTap`, so it is disabled
- **Sections:** `_ProfileSection` / `_ProfileInfoTile` / `_ProfileActionTile` → `BisoSection` + `BisoListGroup` + `BisoListRow`.
  - Info rows: `title: label`, `value: value`, neutral tiles.
  - Action rows, with accents by meaning:

    | Row | Icon | Accent |
    |---|---|---|
    | Expense History | doc_text | coral |
    | Your Orders | bag | gold |
    | Payment Information | creditcard | coral |
    | Notification Preferences | bell | neutral |
    | Language Settings | globe | neutral |

  - The campus row's blue dot is removed.
- **Sign out:** a `BisoListGroup` with `BisoListRow(title: 'Sign Out', destructive: true, leading: BisoIconTile(icon: CupertinoIcons.square_arrow_right), showChevron: false, onTap: …)`.
- **Spacing:** remove `SizedBox(height: 132)` and the double `SizedBox(height: 24)`.
- **Settings entries:** "Notification Preferences" and "Language Settings" keep `SettingsScreen(initialTab: 1/4)` until Task 28 replaces them.

- [ ] **Step 1:** Write `profile_design_test.dart`. Override `authStateProvider` (authenticated user with phone and address), `selectedCampusProvider` and `expenseFeatureFlagProvider` (`overrideWith((_) async => true)`), and use `expectBuildsCleanly`. Add:

```dart
  testWidgets('profile rows use accent tiles and sign out is destructive', (tester) async {
    await pumpBisoScreen(tester, const ProfileScreen(), overrides: [/* … */]);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings'), findsOneWidget);
    final signOut = tester.widget<BisoListRow>(
      find.ancestor(of: find.text('Sign Out'), matching: find.byType(BisoListRow)),
    );
    expect(signOut.destructive, isTrue);
  });
```

Add the screen to `migratedFiles`.

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the new test, the design rules, `flutter analyze` and `flutter test`. Expected: pass.
- [ ] **Step 5:** Screenshots of `/profile` (signed in) at rest and scrolled, light and dark.
- [ ] **Step 6:** Commit: `git commit -m "Move Profile onto BisoPage with grouped account rows"`.

---

## Group A: Explore directories

Every task in this group follows the Screen Migration Recipe (R1–R10) and its test steps:
1. Write `<screen>_design_test.dart` and add the file(s) to `migratedFiles`.
2. Run it and confirm it fails.
3. Implement the decisions.
4. Run the new test, the design rules and the existing tests for the screen, then `flutter analyze` and `flutter test`.
5. Take the screenshots.
6. Commit.

Each task lists only its decisions and its screen-specific test.

## Task 15: Clubs & Units and Unit detail

**Files:**
- Modify: `lib/presentation/screens/explore/units_overview_screen.dart`, `lib/presentation/screens/explore/unit_detail_screen.dart`
- Test: `test/presentation/screens/explore/units_design_test.dart`

**Decisions:**
- **Units overview:**
  - `BisoPage(title: <existing title>, slivers: [SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: SliverGrid.builder(...existing delegate...))])`.
  - Each department card becomes an R5 rich card: logo on `palette.surfaceRaised`, name `titleMedium`, and a one-line `toCompactHtml` description in `palette.muted`.
  - Cards with no logo use `BisoIconTile(icon: CupertinoIcons.person_2, accent: BisoAccent.teal, size: 48)`.
- **Unit detail:**
  - `BisoPage(title: departmentName, largeTitle: false, slivers: [...])`.
  - The header group holds the logo (64 pt, rounded 16) and the name as `headlineMedium` (Museo, no weight).
  - Chips go in a `SliverToBoxAdapter` `Wrap`.
  - The HTML body sits in a `BisoSection` on a surface `Material` with padding 16.
  - Links become `BisoListRow`s: `globe` for web, `mail` for email, and similar.

**Screen test:** the overview shows one card per fake department and tapping a card pushes the detail route. Use `routed: true` with a GoRouter that has `/explore/units/:id`: build a small router in the test and pump with `MaterialApp.router`, as the harness does. Also check that the detail page's compact title equals the department name.

Commit: `Move Clubs & Units onto BisoPage`.

## Task 16: Volunteer (jobs)

**Files:**
- Modify: `lib/presentation/screens/explore/jobs_screen.dart`
- Test: `test/presentation/screens/explore/jobs_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing l10n title>, onRefresh: <existing refresh>, slivers: [...])`.
  - Remove the existing back button if it only pops; keep it as `BisoBackButton(onPressed: safeGoBack '/explore')` if the screen used `NavigationUtils`.
  - The extra action maps per R3.
- **List:** `SliverBisoListGroup(dividerIndent: 60, itemCount:, itemBuilder:)`. Each row:
  - `BisoIconTile(icon: CupertinoIcons.hand_raised, accent: BisoAccent.teal)`
  - the title via `toCompactHtml(style: titleMedium, maxLines: 2)`
  - the description via `toCompactHtml(style: bodyMedium muted, maxLines: 2)`
  - a chevron, laid out like `BisoJobList` in `discovery_sections.dart`
  - Build it as a private `_JobRow` in the same file; `BisoListRow` only takes plain strings.
- **Empty:** `SliverFillRemaining(hasScrollBody: false, child: BisoEmptyState(icon: CupertinoIcons.briefcase, accent: BisoAccent.teal, title: <existing empty title>))`.
- **Detail sheet:** the `DraggableScrollableSheet` keeps its behavior, including opening automatically for `openJobId`. Restyle the content per R9; the apply button becomes a `FilledButton`.

**Screen test:** with `openJobId` passed the way `main.dart` passes it (`extra: {'openJobId': id}` → constructor argument; check with `rg -n "JobsScreen\(" lib/main.dart`), the detail sheet opens after `pumpAndSettle` and shows the job title.

Commit: `Move Volunteer onto BisoPage with grouped job rows`.

## Task 17: Departures

**Files:**
- Modify: `lib/presentation/screens/explore/departures_screen.dart`
- Test: `test/presentation/screens/explore/departures_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing title>, slivers: [SliverToBoxAdapter(chips Wrap/row), SliverBisoListGroup(departure rows)])`.
- **Rows:** `BisoListRow` with:
  - `leading`: a line badge. A `Container` with the transit line color when the data has one (add `// biso:allow data color` on that line if it's a `Color` parsed from data), otherwise `BisoIconTile(icon: CupertinoIcons.tram_fill or bus, accent: BisoAccent.blue)`.
  - `title`: destination.
  - `subtitle`: platform or stop.
  - `value`: minutes until departure, or the time.
  - Realtime delays use `palette.warning`.
- **Timers:** if the screen refreshes on a `Timer.periodic`, keep it and cancel it in `dispose()`. The smoke test must `pumpWidget(const SizedBox())` so the timer is cancelled.

**Screen test:** two fake departures render two rows, and a delayed departure's value text uses `palette.warning`.

Commit: `Move Departures onto BisoPage`.

## Task 18: Notifications and Announcement

**Files:**
- Modify: `lib/presentation/screens/notifications/notifications_screen.dart`, `lib/presentation/screens/notifications/announcement_detail_screen.dart`, `lib/presentation/widgets/premium/notification_tile.dart` (if either screen uses it)
- Test: `test/presentation/screens/notifications/notifications_design_test.dart`

**Decisions:**
- **Notifications** is a top-level route outside the shell, so use `inShell: false` in tests.
  - `BisoPage(title: <existing title>, leading: BisoBackButton(onPressed: () => NavigationUtils.safeGoBack(context)), onRefresh: <existing>, slivers: [SliverBisoListGroup(...)])`.
  - Each row is a `BisoListRow`:
    - `leading`: `BisoIconTile` by topic, using `notification_topics` where available (events blue, products gold, jobs teal, expenses coral, otherwise neutral `bell`)
    - `title` and `subtitle`: the notification text
    - `value`: relative time
    - `trailing`: an 8 pt `palette.link` dot when unread
  - Empty: `BisoEmptyState(icon: CupertinoIcons.bell, title: <existing empty text>)`.
- **Announcement:**
  - `BisoPage(title: <existing title>, largeTitle: false, leading: BisoBackButton(onPressed: () => NavigationUtils.safeGoBack(context, fallbackRoute: '/notifications')), slivers: [...])`.
  - The announcement title is `headlineMedium` (Museo) in a `SliverToBoxAdapter`.
  - Category chips are a `Wrap` of `Chip`s (themed).
  - The HTML body sits on a surface `Material` with padding 16.
- **`notification_tile.dart`:** migrate its 3 off-brand colors per R6, and add it to `migratedFiles`.

**Screen test:** an unread notification shows the link-colored dot; a read one doesn't.

Commit: `Move Notifications and Announcement onto BisoPage`.

---

## Group B: Shop

## Task 19: Marketplace, and retire BisoSearchAppBar

**Files:**
- Modify: `lib/presentation/screens/explore/marketplace_screen.dart`
- Delete: `lib/core/theme/biso_search_app_bar.dart`, `test/presentation/widgets/biso_search_app_bar_test.dart` (their behavior is covered by `biso_page_header_test.dart`)
- Test: `test/presentation/screens/explore/marketplace_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <mode-dependent title as today>, search: BisoHeaderSearch(hintText: <existing hint for mode>, onChanged: <existing>), actions: [...], slivers: [...])`.
- **Actions:**
  1. Favorites: `heart` / `heart_fill` depending on the filter state, with the existing toggle.
  2. Cart: per R3, with the `cartItemCountProvider` badge.
  3. Sell (marketplace mode only): `BisoHeaderAction(icon: CupertinoIcons.plus, tooltip: 'Sell Item', onPressed: <existing FAB action>)`. Remove the FAB.
- **Slivers:**
  1. `SliverToBoxAdapter`: the mode chips (webshop / marketplace) as a segmented row of themed `ChoiceChip`s.
  2. `SliverToBoxAdapter`: a `SizedBox(height: 44, child: ListView(scrollDirection: horizontal, ...))` of category chips.
  3. `SliverPadding(horizontal: 16) > SliverGrid.builder`: product cards per R5 (image 1:1 rounded 16, title `titleSmall`, price `titleMedium` in `palette.ink`).
- **States:** the loading AppBars become `BisoPage(largeTitle: false)` with `BisoSkeleton.grid()`. An empty grid shows `BisoEmptyState(icon: CupertinoIcons.bag, accent: BisoAccent.gold, …)`.
- **Search while favorites are shown:** the existing `searchDisabledInFavoritesMessage` behavior is kept by passing `search: null` while favorites are shown.
- **Retire `BisoSearchAppBar`:** after migrating, check `rg -n "BisoSearchAppBar" lib test` returns only the files being deleted, then delete them.

**Screen test:** search is in the header; the cart badge shows the fake `cartItemCountProvider` count; the sell action exists only in marketplace mode; the grid is a `SliverGrid`.

Commit: `Move the shop onto BisoPage and retire BisoSearchAppBar`.

## Task 20: Product detail (marketplace)

**Files:**
- Modify: `lib/presentation/screens/explore/product_detail_screen.dart`
- Test: `test/presentation/screens/explore/product_detail_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(overImage: true, title: product.name, largeTitle: false, actions: [favorite], slivers: [...], bottomBar: BisoBottomBar(child: <existing action bar content>))`.
- **Favorite action:** `BisoHeaderAction(icon: isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart, tooltip: <existing or 'Favorite'>, onPressed: <existing>)`. The red color goes; the header's foreground applies.
- **Gallery:** a `SliverToBoxAdapter` holding a `SizedBox(height: 400)` with the existing `PageView`, plus page dots at the bottom center (white with a 35% black scrim under them). The round black-30% scrim buttons are removed; the header capsule and back button replace them.
- **Content slivers:**
  - price `headlineMedium` (Museo) and title `titleLarge`
  - the seller row as `BisoListGroup` with an avatar leading, name and campus
  - description on a surface `Material`
  - the existing form field restyled with `bisoInputDecoration` inside a `BisoFormGroup`
- **Colors:** remove the `isDark` branches (10) per R6.
- **Bottom bar:** the existing `bottomNavigationBar` content (contact / buy) moves into `BisoBottomBar`, with the primary action as a full-width `FilledButton`.

**Screen test:** the first content (the gallery) starts at y = 0; the compact title is hidden at rest and visible after scrolling 500 pt; the bottom bar sits above the tab bar.

Commit: `Move marketplace product detail onto an over-image BisoPage`.

## Task 21: Webshop product detail

**Files:**
- Modify: `lib/presentation/screens/explore/webshop_product_detail_screen.dart`
- Keep passing: `test/presentation/screens/explore/webshop_product_detail_screen_test.dart`
- Test: `test/presentation/screens/explore/webshop_product_detail_design_test.dart`
- Delete: `lib/presentation/widgets/shop/cart_icon_button.dart` if `rg -n "CartIconButton" lib test` shows no other users after this task.

**Decisions:**
- **Page:** `Form(key: <existing>, child: BisoPage(overImage: true, title: product.title, largeTitle: false, actions: [cart action per R3], slivers: [...], bottomBar: BisoBottomBar(child: <existing purchase bar>)))`. The `Form` must stay an ancestor of the custom-field inputs.
- **Slivers:**
  1. the gallery at 360 pt full-bleed
  2. title `titleLarge` and price `headlineMedium`, where the member price row uses `palette.success` for the discount label
  3. variations as themed `ChoiceChip`s
  4. custom fields in `BisoFormGroup` + `BisoFormRow` + `bisoInputDecoration`
  5. the HTML description on a surface `Material`
- **Colors:** remove the 10 `isDark` branches per R6.
- **Behavior:** keep `ScrollController` behavior (scroll to an invalid field) by passing the controller to `BisoPage(controller:)`. Keep `member_only` presentation exactly as today.
- **Existing test:** update finders only (for example `SliverAppBar` → `BisoPage`). Every existing assertion about add-to-cart results, validation and member-only must still be there and passing.

**Screen test:** a required custom field left empty shows its validation message below the field when the purchase button in the bottom bar is tapped, and the page scrolls so the field is visible below the header: the field's top is at least `47 + kBisoHeaderHeight`.

Commit: `Move webshop product detail onto an over-image BisoPage`.

## Task 22: Cart and Checkout

**Files:**
- Modify: `lib/presentation/screens/shop/cart_screen.dart`, `lib/presentation/screens/shop/checkout_screen.dart`
- Test: `test/presentation/screens/shop/cart_checkout_design_test.dart`
- Keep passing: `test/providers/shop/cart_provider_test.dart`, `test/providers/shop/checkout_provider_test.dart`

**Decisions:**
- **Cart:**
  - `BisoPage(title: <existing>, leading: BisoBackButton(onPressed: <existing custom back>), actions: <existing 2 actions per R3>, slivers: [SliverBisoListGroup(line items)], bottomBar: items.isEmpty ? null : BisoBottomBar(child: <existing summary: total + checkout button>))`.
  - Each line item is a custom row: 56 pt rounded image, title `titleMedium`, variation and custom-field answers `bodySmall` muted, the quantity stepper as two `BisoCapsuleButton`-sized `IconButton`s (`minus`/`plus`) with the count between, and the price `titleMedium`.
  - The total in the bar is `headlineMedium`.
  - Empty cart: `BisoEmptyState(icon: CupertinoIcons.bag, accent: BisoAccent.gold, title: <existing>, action: <existing browse button>)`.
- **Checkout:**
  - `BisoPage(title: <existing>, leading: BisoBackButton(onPressed: <existing>), slivers: [...])`.
  - Sections become `BisoFormGroup`s: contact fields; payment providers as `BisoListRow`s with a `Radio.adaptive` trailing, showing only `available` providers as today; the order summary as `BisoListGroup` rows with `value:` prices and a total row in `headlineMedium`.
  - The pay button stays inline at the end, as a full-width `FilledButton`.
  - Quote loading: `BisoSkeleton.rows(count: 3)`. Quote error: `BisoErrorState` with the existing retry.
- **Pricing:** no pricing is computed in the UI. Keep reading the quote exactly as today.

**Screen test:**
- Cart with 12 fake lines: after scrolling to the end, the last line's bottom is at or above the bottom bar's top.
- Checkout with two providers where one is unavailable: only one provider row renders.

Commit: `Move cart and checkout onto BisoPage`.

## Task 23: Orders and Order

**Files:**
- Modify: `lib/presentation/screens/shop/orders_screen.dart`, `lib/presentation/screens/shop/order_screen.dart`
- Modify: `test/presentation/widgets/navigation_content_clearance_test.dart` (the OrdersScreen test)
- Test: `test/presentation/screens/shop/orders_design_test.dart`

**Decisions:**
- **Orders:**
  - `BisoPage(title: <existing>, leading: BisoBackButton(onPressed: <existing>), onRefresh: <existing>, slivers: [SliverBisoListGroup(...)])`.
  - Each row is `BisoListRow` with:
    - `leading: BisoIconTile(icon: CupertinoIcons.bag, accent: BisoAccent.gold)`
    - `title: 'Order ${id}'` (keep the existing text)
    - `subtitle`: date
    - `value`: total
    - `trailing`: a status pill — a `Container` with 10% of the status token as background and the token as text; paid → `success`, pending → `warning`, failed or cancelled → `error`
  - Empty: `BisoEmptyState(icon: CupertinoIcons.bag, accent: BisoAccent.gold, title: <existing>)`.
- **Order:**
  - `BisoPage(title: <existing>, largeTitle: false, actions: <existing action>, onRefresh: <existing>, slivers: [...])`.
  - The status header is a `BisoSection` holding:
    - a 56 pt rounded square `DecoratedBox` filled with the status token at 14% opacity, with the status icon (`checkmark_circle_fill` / `clock` / `xmark_circle_fill`, 32 pt) in the full status token. `BisoIconTile` isn't used here because status colors aren't category accents.
    - the status text in `headlineMedium`
    - the explanation in `bodyMedium` muted
  - Lines and totals go in `BisoListGroup`s.
  - Keep `PopScope`, the resume verification and polling exactly.
- **Clearance test update:**
  - The first assertion stays (the order row height is identical inside and outside the shell), with the finder changed from the `InkWell` ancestor of 'Order 0' to the `BisoListRow` ancestor.
  - The drag target changes from `ListView` to `CustomScrollView`.
  - The last-row check stays: the bottom of 'Order 19' is above the expanded tab bar's top.

**Screen test:** a paid order's status pill text color equals `palette.success`.

Commit: `Move orders onto BisoPage with status pills`.

## Task 24: Sell product

**Files:**
- Modify: `lib/presentation/screens/explore/sell_product_screen.dart`
- Test: `test/presentation/screens/explore/sell_product_design_test.dart`

**Decisions:**
- **Page:** `Form(key: <existing>, child: BisoPage(title: <existing>, largeTitle: false, actions: <existing 2 actions per R3; submit uses CupertinoIcons.checkmark>, slivers: [...]))`.
- **Slivers:**
  1. The photo picker grid in a `SliverToBoxAdapter`: 3 columns, 1:1 rounded 14 tiles on `palette.surfaceRaised`; the add tile uses `CupertinoIcons.camera` in `palette.muted`.
  2. `BisoFormGroup`s for details (title, description), price (`prefixText: 'NOK '`) and category and condition (`BisoListRow` with `value:` opening the existing pickers).
- **Colors:** remove the background `isDark` branch.

**Screen test:** submitting with an empty title shows the existing validation message below the title field.

Commit: `Move Sell product onto BisoPage with grouped form sections`.

---

## Group C: Money and forms

## Task 25: Expenses

**Files:**
- Modify: `lib/presentation/screens/explore/expenses_screen.dart`
- Test: `test/presentation/screens/explore/expenses_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing>, search: BisoHeaderSearch(hintText: <existing search hint>, onChanged: <existing filter setter>), actions: [newExpense, ...other existing actions per R3], slivers: [...])`.
  - The title-swapping `TextField` and its toggle state are deleted.
  - `newExpense` is `BisoHeaderAction(icon: CupertinoIcons.plus, tooltip: 'New Expense', onPressed: <existing FAB action>)`. Remove the FAB and its `BisoNavigationInset` padding.
- **Slivers:**
  1. Summary: `SliverToBoxAdapter` holding a `BisoSection` with a surface `Material`. It shows a `BisoIconTile(icon: CupertinoIcons.creditcard, accent: BisoAccent.coral)`, the totals in `headlineMedium`, and their labels in `bodySmall` muted.
  2. Filters: `SliverToBoxAdapter` holding a horizontal `ListView` of themed `ChoiceChip`s (height 44).
  3. `SliverBisoListGroup` rows:
     - `leading`: coral `doc_text` tile
     - `title`: description
     - `subtitle`: date and department
     - `value`: amount
     - `trailing`: a status pill using the Task 23 pill style (approved → `success`, pending → `warning`, rejected → `error`)
- **Detail sheet:** the `DraggableScrollableSheet` is restyled per R9, with amounts in `headlineMedium` and attachments as `BisoListRow`s with `paperclip`.
- **States:** the unauthenticated and loading AppBars become `BisoPage` states. Unauthenticated is `BisoEmptyState` with the existing sign-in action.
- **Colors:** all 7 off-brand colors are mapped per R6.

**Screen test:**
- There is no `FloatingActionButton`, and the header has a 'New Expense' tooltip.
- Typing in header search filters the fake expenses down to one row.

Commit: `Move Expenses onto BisoPage with header search and a new-expense action`.

## Task 26: New expense

**Files:**
- Modify: `lib/presentation/screens/expense/create_expense_screen.dart`
- Test: `test/presentation/screens/expense/create_expense_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing dynamic title: New/Draft reimbursement>, largeTitle: false, leading: BisoGlassCapsule(children: [BisoCapsuleButton(icon: CupertinoIcons.xmark, tooltip: MaterialLocalizations.of(context).closeButtonTooltip, onPressed: <existing close-with-confirmation>)]), automaticallyImplyLeading: false, actions: [BisoHeaderAction(icon: CupertinoIcons.tray_arrow_down, tooltip: 'Save draft', onPressed: <existing save draft>)], slivers: [...])`.
- **Slivers:** the existing `ListView` children split into sections:
  - payment details, department, attachments, event and description, each a `BisoFormGroup` with `BisoFormRow` + `bisoInputDecoration`
  - receipt tiles (`_buildGroupedReceiptTiles`) in a `BisoListGroup`: a 44 pt rounded thumbnail or `doc_text` coral tile as `leading`, file name as `title`, amount or OCR state as `subtitle`, and a `trash` `IconButton` as `trailing`
  - department and event pickers as `BisoListRow`s with `value:` and a chevron
  - the submit button inline at the end
- **Keep:** `PopScope`, the leave confirmation, the keyboard-following modal (restyle its content only) and all validation (MOD11 bank account).
- **Loading and gate states:** their AppBars become `BisoPage` states.
- **No step indicator:** this screen has no step model (verified: no `step`/`PageController` in the file), so none is added.

**Screen test:**
- Tapping close with a dirty form shows the existing confirmation dialog.
- A bank account that fails MOD11 shows its validation message below its field.

Commit: `Move New expense onto BisoPage with grouped form sections`.

## Task 27: Payment information and Edit profile

**Files:**
- Modify: `lib/presentation/screens/profile/payment_information_screen.dart`, `lib/presentation/screens/profile/edit_profile_screen.dart`
- Test: `test/presentation/screens/profile/profile_forms_design_test.dart`

**Decisions:**
- **Payment information:**
  - `Form(child: BisoPage(title: <existing>, largeTitle: false, slivers: [...]))`.
  - Cards become `BisoFormGroup`s (bank account with the 11-digit hint, prepayment toggle as `BisoListRow` with `Switch.adaptive`).
  - The save button is an inline `FilledButton`.
  - Remove `_getCampusColor` and all 8 off-brand colors per R6.
- **Edit profile:**
  - `Form(child: BisoPage(title: <existing>, largeTitle: false, actions: [BisoHeaderAction(icon: CupertinoIcons.checkmark, tooltip: <existing save text>, onPressed: <existing save>)], slivers: [...]))`.
  - The avatar header is a centered 96 pt avatar with a `BisoGlassCapsule` camera button at the bottom right (the existing `Positioned` badge becomes the capsule).
  - Then the `BisoFormGroup`s: name and phone, then address, then campus and departments (as `BisoListRow` with `value:` opening the existing pickers).
- **Keep:** Norwegian validation and the image picker.

**Screen test:** both screens build cleanly (`expectBuildsCleanly`); Edit profile's save action calls the fake auth service's update method once.

Commit: `Move payment information and profile editing onto grouped forms`.

---

## Group D: Settings

## Task 28: Settings list with section pages

**Files:**
- Modify: `lib/presentation/screens/profile/settings_screen.dart`, `lib/presentation/screens/profile/settings_screen_chat_tab.dart`
- Modify callers: `lib/presentation/screens/profile/profile_screen.dart` (lines ~379, ~390), `lib/presentation/screens/chat/chat_list_screen.dart` (line ~226, unreachable but must compile)
- Modify: `lib/presentation/widgets/premium/notification_tile.dart`, if Task 18 didn't already migrate it
- Test: `test/presentation/screens/profile/settings_design_test.dart`

**Interfaces:**
- Produces:
  - `enum SettingsSection { general, notifications, privacy, chat, language }`
  - `class SettingsScreen extends ConsumerWidget { const SettingsScreen({super.key}); }`. The `initialTab` parameter is removed.
  - `class SettingsSectionPage extends StatelessWidget { const SettingsSectionPage({super.key, required this.section}); }`

**Decisions:**
- **`SettingsScreen`:** `BisoPage(title: l10n.settingsMessage, slivers: [SliverToBoxAdapter(child: BisoSection(child: BisoListGroup(children: rows)))])`. There are five rows:

  | Row | Title | Tile |
  |---|---|---|
  | general | `l10n.generalMessage` | gear, neutral |
  | notifications | `l10n.notificationsMessage` | bell, neutral |
  | privacy | `l10n.privacyMessage` | lock, neutral |
  | chat | `l10n.chatMessage` | bubble_left_bubble_right, teal |
  | language | `l10n.languageMessage` | globe, neutral |

  Each row calls `Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsSectionPage(section: …)))`.
- **`SettingsSectionPage`:** returns `BisoPage(title: <same l10n title>, largeTitle: false, slivers: [SliverToBoxAdapter(child: <section body>)])`.
- **Tab bodies:** `_GeneralSettingsTab`, `_NotificationSettingsTab`, `_PrivacySettingsTab` and `_LanguageSettingsTab` become the section bodies.
  - Rename them to `_GeneralSettingsBody` and so on.
  - Replace each `SingleChildScrollView(padding: BisoNavigationInset…, child: Column(...))` with a `Column`.
  - Restyle cards and `ListTile`/`SwitchListTile` into `BisoSection` + `BisoListGroup` + `BisoListRow(trailing: Switch.adaptive(...))`.
- **Chat tab:** `ChatSettingsTab` in `settings_screen_chat_tab.dart` gets the same treatment and is renamed `ChatSettingsBody`.
- **Remove:** `TabController`, `SingleTickerProviderStateMixin`, `_getCampusColor`, `campusSwitchThumbColor` and `campusSwitchTrackColor` (switch colors come from the theme). Before deleting the helpers, confirm they are only used in these two files (`rg -n "campusSwitch(Thumb|Track)Color" lib`).
- **Callers:**
  - profile `SettingsScreen(initialTab: 1)` → `SettingsSectionPage(section: SettingsSection.notifications)`
  - profile `SettingsScreen(initialTab: 4)` → `SettingsSectionPage(section: SettingsSection.language)`
  - chat_list `SettingsScreen(initialTab: 3)` → `SettingsSectionPage(section: SettingsSection.chat)`
- **Controller mode:** its entry in General settings keeps pushing `/controller-mode` as today.

**Screen test:**

```dart
  testWidgets('settings lists five sections and each opens its page', (tester) async {
    await pumpBisoScreen(tester, const SettingsScreen(), overrides: [/* … */]);
    for (final title in ['General', 'Notifications', 'Privacy', 'Chat', 'Language']) {
      await tester.tap(find.widgetWithText(BisoListRow, title));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biso-compact-title')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('biso-compact-title'))).data,
        title,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
  });
```

Add a `expectBuildsCleanly` call for each `SettingsSectionPage` value. Add both files to `migratedFiles`.

Commit: `Turn Settings into a grouped list with a page per section`.

---

## Group E: Conversations

## Task 29: Chat conversation

**Files:**
- Modify: `lib/presentation/screens/chat/chat_conversation_screen.dart`
- Modify: `test/presentation/widgets/navigation_content_clearance_test.dart` (the composer test)
- Test: `test/presentation/screens/chat/chat_conversation_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing dynamic title>, largeTitle: false, actions: [BisoHeaderAction(icon: CupertinoIcons.info_circle, tooltip: <existing>, onPressed: <existing info push>)], body: <message list>, bottomBar: <composer>)`.
- **Message list:** the existing `StreamBuilder` → `ListView.builder(reverse: true, ...)` with `padding: BisoPageInsets.padding(context, const EdgeInsets.symmetric(horizontal: 12, vertical: 8))`. `EdgeInsets` stay visual on reversed lists, so top clears the header and bottom clears the composer.
- **Composer:** `Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: BisoChrome(radius: 26, child: Row(children: [attach IconButton(CupertinoIcons.paperclip), Expanded(TextField with bisoInputDecoration hint), send IconButton(CupertinoIcons.paperplane_fill, color: palette.link)])))`. Remove its `BisoNavigationInset` padding and its elevated `Container`.
- **Bubbles:**
  - Others: `palette.surface` with ink text.
  - Self: `palette.primary` with `palette.onPrimary` text.
  - Radius 20, with a 6 pt corner on the tail side.
  - Timestamps: `labelSmall` muted (on primary, `onPrimary` at 70%).
  - Reactions: a `palette.surfaceRaised` pill.
  - Reply previews: a 3 pt `palette.link` bar.
- **Icons and colors:** all 24 Material icons per R7 and all 4 off-brand colors per R6. SnackBars keep their text and get theme styling.
- **Clearance test:** keep both assertions: the composer `TextField` bottom is above the expanded tab bar's top, and it can take focus without switching tabs. Nothing else changes; the finders already use `TextField`.

**Screen test:** with 30 fake messages, the newest message is visible directly above the composer; after scrolling to the oldest, it passes under the header.

Commit: `Move chat conversations onto BisoPage with a glass composer`.

## Task 30: Chat info and User picker

**Files:**
- Modify: `lib/presentation/screens/chat/chat_info_screen.dart`, `lib/presentation/screens/chat/user_picker_screen.dart`
- Test: `test/presentation/screens/chat/chat_info_design_test.dart`

**Decisions:**
- **Chat info:**
  - `BisoPage(title: <existing>, largeTitle: false, actions: <existing per R3>, slivers: [...])`.
  - A centered avatar (80 pt) and name (`headlineMedium`).
  - Then `BisoFormGroup`s for the two fields, and `BisoListGroup`s for participants and settings (mute as `Switch.adaptive`).
  - Leave or delete is a destructive row.
  - All 14 icons per R7.
- **User picker:**
  - `BisoPage(title: widget.title, largeTitle: false, search: BisoHeaderSearch(hintText: <existing search hint>, onChanged: <existing>), actions: <existing per R3>, slivers: [SliverToBoxAdapter(selected chips Wrap), SliverBisoListGroup(users)])`.
  - The old search `TextField` above the list is removed.
  - User rows show an avatar leading and a `CupertinoIcons.checkmark_circle_fill` trailing in `palette.link` when selected.

**Screen test:** the user picker filters the fake users through header search; selecting a user shows its chip.

Commit: `Move chat info and user picker onto BisoPage`.

## Task 31: AI assistant

**Files:**
- Modify: `lib/presentation/screens/ai_chat/ai_chat_screen.dart`
- Modify widgets: `lib/presentation/widgets/ai_chat/ai_message_bubble.dart`, `chat_input_field.dart`, `typing_indicator.dart`, `user_message_bubble.dart`, `markdown_text.dart`
- Test: `test/presentation/screens/ai_chat/ai_chat_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: <existing assistant title>, largeTitle: false, actions: [BisoHeaderAction(icon: CupertinoIcons.arrow_clockwise, tooltip: <existing>, onPressed: <existing refresh>)], body: <message list>, bottomBar: <composer>)`.
  - Remove `extendBodyBehindAppBar`, the background `Stack` and its gradients, and the `SafeArea` (the spec's double top inset).
- **Status line:** the header's changing status line becomes the first item in the message list: a centered `labelMedium` muted row with a 20 pt violet `sparkles` tile.
- **Message list:** `ListView.builder` with `padding: BisoPageInsets.padding(context, const EdgeInsets.symmetric(horizontal: 12, vertical: 8))`. Keep its existing `reverse` setting.
- **Composer:** `_buildChatInput` → the Task 29 composer shape (a `BisoChrome` capsule), with no `BisoGlassContainer` and no `BisoNavigationInset`.
- **Widgets:**
  - `ai_message_bubble`: `palette.surface` bubble with a violet `sparkles` 28 pt tile avatar; `markdown_text` uses `palette.ink` / `palette.link` for links; code blocks use `palette.surfaceRaised`.
  - `user_message_bubble`: `palette.primary` / `onPrimary`, gradients removed.
  - `typing_indicator`: three `palette.muted` dots; with `disableAnimations` they are static.
  - `chat_input_field`: tokens only.
- **Add** the screen and all five widgets to `migratedFiles`.

**Screen test:** with the fake assistant service, sending a message shows the user bubble with `palette.primary` fill, and there is no `BackdropFilter` except the header band.

Commit: `Move the AI assistant onto BisoPage with a violet accent`.

---

## Group F: Campus and large events

## Task 32: Campus detail

**Files:**
- Modify: `lib/presentation/screens/explore/campus_detail_screen.dart`, `lib/presentation/screens/explore/campus_detail_components.dart`, `lib/presentation/widgets/campus/campus_leadership_section.dart`
- Test: `test/presentation/screens/explore/campus_detail_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(overImage: true, title: campus.name, largeTitle: false, slivers: [...])`.
  - Remove the `AnimatedBuilder` and `ScrollController` used only for parallax and the floating header FAB.
  - Loading and error AppBars become `BisoPage` states.
- **Cover:** `CampusParallaxHeader` → `CampusCover`, a `SliverToBoxAdapter` holding a `SizedBox(height: 320)`.
  - It shows the campus image (the same asset or URL source the parallax header uses) with a bottom-to-top `Colors.black` scrim from 0% to 55%.
  - Over the image sit the campus name in `displaySmall` white and the weather and stats in a white `bodyMedium` row.
  - Remove the 11+6 animations and the `defaultBlue` background.
- **Sections:**
  - `CampusQuickActions` → `BisoListGroup` rows with accent tiles per R6.
  - `CampusBenefitCard` → R5 rich card without animation.
  - `CampusDepartmentShowcase` → a horizontal list of department cards (as in Units).
  - `CampusContactCard` → `BisoListGroup` rows (`mail`, `phone`, `location_solid`).
  - `campus_leadership_section.dart` → `BisoSection` + `BisoListGroup` rows with avatar `leading`, name `title` and role `subtitle`. It has 44 colors to migrate per R6.
- **Remove FAB:** the extended FAB is deleted; the compact title does its job.

**Screen test:** there is no `FloatingActionButton`; the cover starts at y = 0; after scrolling 400 pt the compact title shows the campus name.

Commit: `Replace the campus parallax header with a photo cover on BisoPage`.

## Task 33: Large event

**Files:**
- Modify: `lib/presentation/screens/events/large_event_screen.dart`
- Test: `test/presentation/screens/events/large_event_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(overImage: true, title: event.name, largeTitle: false, leading: BisoBackButton(onPressed: () => NavigationUtils.safeGoBack(context, fallbackRoute: '/explore')), slivers: [...])`.
  - This is a top-level route, so use `inShell: false` in tests.
- **Hero:** the `FlexibleSpaceBar` image → `SliverToBoxAdapter(SizedBox(height: 360))` with the `event.backgroundImageUrl` image through `CachedNetworkImage` (`memCacheWidth: 1200`), a scrim, and `event.name` in `displaySmall` white at the bottom left.
  - When there is no image, use a `palette.primary` block.
  - Replace `Colors.black54` with `Colors.black.withValues(alpha: 0.45)`.
- **Content:** cards → R5; `ListTile`s → `BisoListRow`s; ticket links → rows with `ticket` gold tiles opening the existing URLs.

**Screen test:** the hero starts at y = 0; the compact title is hidden at rest.

Commit: `Move large events onto an over-image BisoPage`.

---

## Group G: Outside the tab shell

## Task 34: Login, verification code and magic link

**Files:**
- Modify: `lib/presentation/screens/auth/login_screen.dart`, `lib/presentation/screens/auth/otp_verification_screen.dart`, `lib/presentation/screens/auth/magic_link_verify_screen.dart`
- Test: `test/presentation/screens/auth/auth_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(largeTitle: false, slivers: [SliverFillRemaining(hasScrollBody: false, child: Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), child: Column(...existing children...)))])`.
  - `SliverFillRemaining` keeps the `Spacer`s working when there is room and lets content scroll when the keyboard takes space, which fixes the overflow.
  - OTP keeps the automatic back button (`leading` unset). Login and magic link have none.
  - Login stays reachable both as a top-level route and pushed from Home: use `inShell: false` and `inShell: true` in tests.
- **Type:** titles use `displaySmall` / `headlineMedium` without `fontWeight`, which removes 4 Museo violations.
- **Buttons:**
  - Sign in with Apple: `FilledButton` with `backgroundColor: palette.ink` and `foregroundColor: palette.paper`. This follows Apple's rule of a black button in light and a white one in dark, and replaces the 8 `isDark` branches.
  - Google: `OutlinedButton` (themed `surfaceRaised`).
  - Primary: `FilledButton`.
- **Fields:** email and code fields use the theme's filled input decoration. Six raw `Color(0x…)` literals are replaced per R6, except the Google logo SVG.

**Screen test:** at text scale 2 on a 320x640 screen with a 300 pt keyboard inset (`MediaQuery` `viewInsets`), the login screen builds without overflow and the send button can be scrolled into view (`tester.scrollUntilVisible` on the send button succeeds).

Commit: `Move sign-in screens onto BisoPage and make them keyboard safe`.

## Task 35: Onboarding

**Files:**
- Modify: `lib/presentation/screens/onboarding/onboarding_screen.dart`
- Test: `test/presentation/screens/onboarding/onboarding_design_test.dart`

**Decisions:**
- **Page:** `BisoPage(title: '${_currentStep + 1} / 2', largeTitle: false, automaticallyImplyLeading: false, leading: _currentStep > 0 ? BisoBackButton(onPressed: _previousStep) : null, notificationDepth: 1, body: PageView(controller: _pageController, physics: const NeverScrollableScrollPhysics(), children: [step1, step2]))`.
  - The title string is the existing one.
- **Each step:** a `CustomScrollView` with these slivers:
  1. `SliverToBoxAdapter(SizedBox(height: BisoPageInsets.maybeOf(context)!.top))`
  2. `SliverToBoxAdapter(LinearProgressIndicator(value: (_currentStep + 1) / 2))` with 20 pt side padding
  3. the step's heading in `headlineMedium` (no weight)
  4. its `BisoFormGroup`s
  5. `SliverFillRemaining(hasScrollBody: false, child: Align(alignment: Alignment.bottomCenter, child: <existing buttons>))`
  6. `SliverToBoxAdapter(SizedBox(height: BisoPageInsets.maybeOf(context)!.bottom + 16))`
- **Remove:** the fixed-height `SizedBox` (screen height − 200) around the `PageView`, and the outer `SingleChildScrollView`.

**Screen test:** step 1 builds at text scale 1.6 on 320x640 without overflow; after filling the required fake fields and tapping next, the compact title reads `2 / 2` and a back button appears.

Commit: `Move onboarding onto BisoPage with scrollable steps`.

## Task 36: Ticket scanner (controller mode)

**Files:**
- Modify: `lib/presentation/screens/validator/controller_mode_screen.dart`
- Test: `test/presentation/screens/validator/controller_mode_design_test.dart`

**Decisions:**
- **Page:** `Theme(data: PremiumTheme.darkTheme, child: BisoPage(title: <existing title>, largeTitle: false, overImage: true, actions: <existing action per R3>, body: Stack(fit: StackFit.expand, children: [...])))`. The scanner is always dark.
- **Stack children:**
  1. `MobileScanner(...)`, unchanged.
  2. An instruction card: `Positioned(top: BisoPageInsets.maybeOf(context)!.top + 8, left: 16, right: 16)` holding a surface `Material` with radius 20 and the existing instructions.
  3. The existing result cards, as a `Positioned(bottom: BisoPageInsets.maybeOf(context)!.bottom + 8, left: 16, right: 16)` `Material`. Valid uses `palette.success`, invalid `palette.error`, and animations are kept.
- **Remove:** the `charcoalBlack` AppBar, `_getCampusColor`, the gradient and the 4 off-brand colors.
- **Smoke test:** override the scanner. `MobileScanner` needs a platform camera, so extract the scanner into a `scannerBuilder` constructor parameter defaulting to `(onDetect) => MobileScanner(onDetect: onDetect, …existing args)` and pass a `ColoredBox` in tests. Keep the default call identical to today.

**Screen test:** builds with the fake scanner; the header's icons are white (over-image) and the page uses the dark palette.

Commit: `Move the ticket scanner onto an always-dark BisoPage`.

---

## Task 37: Retire legacy styling and verify the whole app

**Files:**
- Modify or delete: `lib/core/theme/biso_glass.dart` (+ `test/core/theme/biso_glass_card_test.dart`), `lib/presentation/widgets/premium/premium_components.dart`, `lib/presentation/widgets/premium/premium_layouts.dart`, `lib/core/constants/app_colors.dart`, `lib/core/theme/premium_theme.dart` (legacy shadow and glass helpers)
- Modify: `CLAUDE.md` (the "UI/UX Design System" section)

- [ ] **Step 1: Find leftovers.**

```bash
rg -n "BisoGlassCard|BisoGlassContainer|BisoGlassAppBar" lib test
rg -n "PremiumTheme\.(softShadow|mediumShadow|strongShadow|glassContainer)" lib test
rg -n "PremiumSection|PremiumGrid|PremiumContainer|PremiumScaffold" lib test
rg -n "AppColors\.(orange|green|purple|pink)\d" lib test
```

Delete each class or helper whose only remaining references are its own declaration and tests. Leave anything still used by the unreachable screens (`student_id_screen.dart`, membership modals, `chat_list_screen.dart`, `new_chat_screen.dart`, `message_search_screen.dart`); those are out of scope.

- [ ] **Step 2: Update `CLAUDE.md`.** Replace the "Color Palette", "Typography" and "Components Style Guide" subsections under "UI/UX Design System" with this pointer:

```markdown
### Design system (2026-09)
Tokens, type and components are defined in
`docs/superpowers/specs/2026-09-11-glass-header-and-screen-redesign-design.md`.
Screens import `lib/presentation/widgets/biso/biso.dart` and build on
`BisoPage`; colors come from `BisoPalette.of(context)` and `BisoAccent`;
Museo Sans is weight 300 and only for large type; icons are CupertinoIcons.
`test/presentation/design_rules_test.dart` enforces this for migrated files.
```

- [ ] **Step 3: Full verification.**

Run: `flutter analyze`
Expected: no issues beyond the 12-info baseline. Record the count.

Run: `flutter test`
Expected: all tests pass. Record the count.

Run: `flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`.

- [ ] **Step 4: Screenshot pass.**
  - For every screen reachable by route, take rest and scrolled shots in light and dark (Task 9 procedure).
  - Ask the user to open Settings pages, Edit profile, Payment information, a marketplace chat and Chat info on the simulator for screenshots.
  - Inspect each image for:
    - no content hidden behind the tab bar at the end
    - the band and hairline when scrolled
    - glass capsules rendering over the band
    - no off-brand colors
    - no Material icons
  - List any defects found and fix them before continuing.

- [ ] **Step 5: Report to the user.** Summarize:
  - analyze and test counts
  - the build result
  - screenshots inspected (and which screens the user had to open)
  - anything left for physical-device profiling, as the spec's "Out of scope" section says

- [ ] **Step 6: Commit**

```bash
git add -A lib test CLAUDE.md
git commit -m "Retire legacy glass styling and document the BISO design system" -m "<attribution lines>"
```

