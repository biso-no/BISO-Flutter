import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `DeepLinkService` (through `app_links`) is the only thing that may route an
/// incoming link. Flutter's own deep linking, on by default since Flutter
/// 3.27, hands the raw URL to GoRouter as well: a sign-in link
/// `https://biso.no/auth/verify?...` then lands on GoRouter's "Page Not
/// Found", and a link both handlers did route would be followed twice.
void main() {
  test('iOS opts out of Flutter deep linking', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false\s*/>')),
    );
  });

  test('Android opts out of Flutter deep linking', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      matches(
        RegExp(
          r'android:name="flutter_deeplinking_enabled"\s+'
          r'android:value="false"',
        ),
      ),
    );
  });

  // `pathPrefix="/app"` also matches `/applications` (the web's My
  // applications page) and any other `/app…` path: Android would open the
  // app for it and the app would do nothing. iOS claims `/app/*` only.
  test('Android claims only /app and /app/… on both hosts', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('android:pathPrefix="/app"')));

    final filters = RegExp(
      r'<intent-filter\b[\s\S]*?</intent-filter>',
    ).allMatches(manifest).map((match) => match.group(0)!);
    for (final host in ['biso.no', 'www.biso.no']) {
      final appLinks = filters.where(
        (filter) =>
            filter.contains('android:host="$host"') &&
            filter.contains('android:pathPattern="/app/.*"'),
      );
      expect(appLinks, hasLength(1), reason: host);
      final filter = appLinks.single;
      expect(filter, contains('android:autoVerify="true"'), reason: host);
      expect(filter, contains('android:path="/app"'), reason: host);
      expect(filter, contains('android:scheme="https"'), reason: host);
    }
  });
}
