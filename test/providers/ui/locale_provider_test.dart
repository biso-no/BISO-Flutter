import 'dart:ui';

import 'package:biso/providers/ui/locale_provider.dart';
import 'package:biso/providers/provider_retry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LocaleNotifier build(Locale Function() device) {
    final container = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        localeProvider.overrideWith(
          () => LocaleNotifier(
            deviceLocale: device,
            prefs: SharedPreferences.getInstance,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(localeProvider.notifier);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a Bokmål phone gets Norwegian', () async {
    final n = build(() => const Locale('nb', 'NO'));
    expect(n.state.languageCode, 'no');
    await _settle();
    expect(n.state.languageCode, 'no');
    expect(n.isExplicit, isFalse);
  });

  test('an English or Swedish phone gets English', () async {
    final en = build(() => const Locale('en', 'GB'));
    await _settle();
    expect(en.state.languageCode, 'en');
    final sv = build(() => const Locale('sv', 'SE'));
    await _settle();
    expect(sv.state.languageCode, 'en');
  });

  test('an explicit choice wins over the phone', () async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    final n = build(() => const Locale('nb', 'NO'));
    await _settle();
    expect(n.state.languageCode, 'en');
    expect(n.isExplicit, isTrue);
  });

  test('setLocale makes the choice explicit and persists it', () async {
    final n = build(() => const Locale('en'));
    await _settle();
    await n.setLocale('no');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('language'), 'no');
    expect(n.isExplicit, isTrue);
  });

  test('follows the phone when it changes, until a choice is made', () async {
    var device = const Locale('en');
    final n = build(() => device);
    await _settle();
    expect(n.state.languageCode, 'en');
    device = const Locale('nb');
    n.onDeviceLocaleChanged();
    expect(n.state.languageCode, 'no');
    await n.setLocale('en');
    device = const Locale('nn');
    n.onDeviceLocaleChanged();
    expect(n.state.languageCode, 'en');
  });
}
