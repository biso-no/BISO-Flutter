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
