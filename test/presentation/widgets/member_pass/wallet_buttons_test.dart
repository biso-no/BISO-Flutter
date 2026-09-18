import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/data/services/wallet_channel.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/member_pass/wallet_buttons.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

class _FakeWallet implements WalletChannel {
  bool canAdd = true;
  Object? addError;
  WalletAddResult result = WalletAddResult.added;
  final added = <Uint8List>[];

  @override
  Future<bool> canAddPasses() async => canAdd;

  @override
  Future<WalletAddResult> addPass(Uint8List bytes) async {
    added.add(bytes);
    if (addError != null) throw addError!;
    return result;
  }
}

void main() {
  late FakeMemberPassApi api;
  late _FakeWallet wallet;
  late List<Uri> launched;
  late FixedMemberPass pass;

  setUp(() {
    api = FakeMemberPassApi()
      ..onFetchApplePass = (() => Uint8List.fromList([1, 2, 3]))
      ..onFetchGoogleSaveUrl = () =>
          Uri.parse('https://pay.google.com/gp/v/save/x');
    wallet = _FakeWallet();
    launched = [];
    pass = FixedMemberPass(activeView());
  });

  // `debugDefaultTargetPlatformOverride` must be back to null before the
  // test body returns: the binding checks foundation debug variables right
  // after the body runs, which is earlier than any `tearDown`/`addTearDown`
  // callback fires.
  void platformTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required TargetPlatform platform,
    WalletAvailability wallets = const WalletAvailability(
      apple: true,
      google: true,
    ),
    Locale locale = const Locale('en'),
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberPassApiProvider.overrideWithValue(api),
          walletChannelProvider.overrideWithValue(wallet),
          memberPassProvider.overrideWith(() => pass),
          membershipUrlLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(body: WalletButtons(wallets: wallets)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  String? badge(WidgetTester tester) {
    final finder = find.byType(SvgPicture);
    if (finder.evaluate().isEmpty) return null;
    final loader = tester.widget<SvgPicture>(finder).bytesLoader;
    return (loader as SvgAssetLoader).assetName;
  }

  platformTest('iOS shows the Apple badge in the app language', (tester) async {
    await pump(tester, platform: TargetPlatform.iOS);
    expect(badge(tester), appleWalletBadge['en']);
    await pump(
      tester,
      platform: TargetPlatform.iOS,
      locale: const Locale('no'),
    );
    expect(badge(tester), appleWalletBadge['no']);
  });

  platformTest(
    'iOS hides the badge when the flag is off or Wallet cannot add',
    (tester) async {
      await pump(
        tester,
        platform: TargetPlatform.iOS,
        wallets: const WalletAvailability(apple: false, google: true),
      );
      expect(badge(tester), isNull);

      wallet.canAdd = false;
      await pump(tester, platform: TargetPlatform.iOS);
      expect(badge(tester), isNull);
    },
  );

  platformTest('Android shows only the Google badge', (tester) async {
    await pump(tester, platform: TargetPlatform.android);
    expect(badge(tester), googleWalletBadge['en']);

    await pump(
      tester,
      platform: TargetPlatform.android,
      wallets: const WalletAvailability(apple: true, google: false),
    );
    expect(badge(tester), isNull);
  });

  platformTest('adding on iOS hands the pass to Wallet and says so', (
    tester,
  ) async {
    await pump(tester, platform: TargetPlatform.iOS);
    // The badge's own render object never registers a hit (flutter_svg's
    // picture layer isn't interactive; `_Badge` claims the tap with
    // `HitTestBehavior.opaque` on its GestureDetector instead), so the
    // framework's "did this finder's widget see the tap" warning is a false
    // positive here — silenced rather than chasing a hit exactly through the
    // SVG's own layer.
    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(api.applePassCalls, 1);
    expect(wallet.added.single, [1, 2, 3]);
    expect(find.text('Added to Wallet'), findsOneWidget);
    expect(badge(tester), isNull);
  });

  platformTest('a cancelled sheet keeps the badge', (tester) async {
    wallet.result = WalletAddResult.cancelled;
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Added to Wallet'), findsNothing);
    expect(badge(tester), appleWalletBadge['en']);
  });

  platformTest('a rejected pass explains itself', (tester) async {
    wallet.addError = PlatformException(code: 'invalid_pass');
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(find.text("The pass couldn't be read."), findsOneWidget);
  });

  platformTest('other Wallet failures are generic', (tester) async {
    for (final code in ['cannot_add', 'no_presenter', 'busy']) {
      wallet.addError = PlatformException(code: code);
      await pump(tester, platform: TargetPlatform.iOS);
      await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      expect(
        find.text("Couldn't reach Wallet — try again."),
        findsOneWidget,
        reason: code,
      );
      expect(find.text("The pass couldn't be read."), findsNothing);
    }
  });

  platformTest('server refusals explain themselves', (tester) async {
    for (final (status, text) in [
      (403, "Your membership isn't active."),
      (404, "Wallet isn't available yet."),
      (500, "Couldn't reach Wallet — try again."),
    ]) {
      api.onFetchApplePass = () =>
          throw MemberPassApiException('x', statusCode: status);
      await pump(tester, platform: TargetPlatform.iOS);
      await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: '$status');
      ScaffoldMessenger.of(
        tester.element(find.byType(WalletButtons)),
      ).removeCurrentSnackBar();
      await tester.pump();
    }
  });

  platformTest('a 401 lets the pass screen re-check the session', (
    tester,
  ) async {
    api.onFetchApplePass = () =>
        throw const MemberPassApiException('x', statusCode: 401);
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(pass.retries, 1);
  });

  platformTest('adding on Android opens the save link', (tester) async {
    await pump(tester, platform: TargetPlatform.android);
    await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(launched, [Uri.parse('https://pay.google.com/gp/v/save/x')]);
  });

  test('every badge asset is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final path in [
      ...appleWalletBadge.values,
      ...googleWalletBadge.values,
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });
}
