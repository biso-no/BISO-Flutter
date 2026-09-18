import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/presentation/widgets/member_pass/pass_colors.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

  MemberPassView viewAt(
    int now, {
    bool offline = false,
    bool withCode = true,
    PassTerm? term = testTerm,
  }) {
    final session = MemberPassSession()
      ..apply(activePassAt(t0, term: term), t0);
    if (offline) session.applyNetworkFailure(t0);
    final view = session.view(now);
    return withCode
        ? view
        : MemberPassView(
            status: view.status,
            pass: view.pass,
            serverTime: view.serverTime,
          );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the member label, term, color, QR, name and expiry', (
    tester,
  ) async {
    await pump(tester, PassCard(view: viewAt(t0 + 1000)));
    expect(find.text('MEMBER'), findsOneWidget);
    expect(find.text('Fall 2026'), findsOneWidget);
    expect(find.text('TEAL'), findsOneWidget);
    expect(find.text('Kari Nordmann'), findsOneWidget);
    expect(find.textContaining('Valid until'), findsOneWidget);
    expect(find.text('12:00:01'), findsOneWidget); // 10:00:01 UTC in CEST
    expect(
      tester.widget<PassQr>(find.byType(PassQr)).code,
      'v1.user-1.${t0 ~/ 30000}.sig',
    );
    expect(find.byType(HolographicBand), findsOneWidget);
    expect(find.byType(CountdownRing), findsOneWidget);
  });

  testWidgets('speaks Norwegian', (tester) async {
    await pump(tester, PassCard(view: viewAt(t0)), locale: const Locale('no'));
    expect(find.text('MEDLEM'), findsOneWidget);
    expect(find.text('Høst 2026'), findsOneWidget);
    expect(find.text('BLÅGRØNN'), findsOneWidget);
  });

  testWidgets(
    'a null term shows the membership name in the term position, exactly '
    'once',
    (tester) async {
      await pump(tester, PassCard(view: viewAt(t0, term: null)));
      expect(find.text('Semester'), findsOneWidget);
      final style = tester.widget<Text>(find.text('Semester')).style;
      final textTheme = Theme.of(
        tester.element(find.text('Semester')),
      ).textTheme;
      // The term position uses titleMedium; the lower details block (which
      // this must not repeat into) uses bodyMedium.
      expect(style?.fontSize, textTheme.titleMedium?.fontSize);
      expect(style?.fontSize, isNot(textTheme.bodyMedium?.fontSize));
    },
  );

  testWidgets('shows the offline chip', (tester) async {
    await pump(tester, PassCard(view: viewAt(t0, offline: true)));
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('shows Updating when no code is valid', (tester) async {
    await pump(tester, PassCard(view: viewAt(t0, withCode: false)));
    expect(find.text('Updating…'), findsOneWidget);
    expect(tester.widget<PassQr>(find.byType(PassQr)).code, isNull);
  });

  testWidgets('taps open presentation, and the hint is hidden there', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, PassCard(view: viewAt(t0), onTap: () => taps++));
    expect(find.text('Tap to show full screen'), findsOneWidget);
    await tester.tap(find.byType(PassCard));
    expect(taps, 1);

    await pump(tester, PassCard(view: viewAt(t0), presentation: true));
    expect(find.text('Tap to show full screen'), findsNothing);
  });

  testWidgets('the band keeps moving, slower, under reduced motion', (
    tester,
  ) async {
    await pump(tester, const HolographicBand(), reduceMotion: true);
    final controller = tester
        .state<HolographicBandState>(find.byType(HolographicBand))
        .controller;
    expect(controller.isAnimating, isTrue);
    expect(controller.duration, HolographicBandState.reducedLoop);

    await pump(tester, const HolographicBand());
    expect(
      tester
          .state<HolographicBandState>(find.byType(HolographicBand))
          .controller
          .duration,
      HolographicBandState.loop,
    );
  });

  test('ink contrasts with the stripe', () {
    expect(PassColors.inkOn(const Color(0xFFFFE629)), const Color(0xFF111111));
    expect(PassColors.inkOn(const Color(0xFF3E63DD)), const Color(0xFFFFFFFF));
  });

  test('day color names fall back to the raw name', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final name in DayColor.names) {
      expect(dayColorName(en, name), isNot(name), reason: name);
    }
    expect(dayColorName(en, 'mauve'), 'mauve');
  });

  test('scan messages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    String text(ScanMessage m, {int? seconds}) => scanMessageText(
      en,
      ScannerResult(
        tone: ScanTone.orange,
        message: m,
        secondsSincePrevious: seconds,
      ),
    );
    expect(text(ScanMessage.duplicate, seconds: 42), 'Already scanned 42s ago');
    expect(
      text(ScanMessage.duplicate, seconds: 185),
      'Already scanned 3 min ago',
    );
    expect(text(ScanMessage.badCode), 'Not a BISO pass');
    expect(text(ScanMessage.rateLimited), 'Too many scans — wait a moment');
    for (final m in ScanMessage.values) {
      expect(text(m, seconds: 1), isNotEmpty);
    }
  });
}
