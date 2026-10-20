import 'dart:ui';

import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LocaleNotifier build(Locale Function() device) =>
      LocaleNotifier(deviceLocale: device, prefs: SharedPreferences.getInstance);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a Bokmål phone gets Norwegian', () async {
    final n = build(() => const Locale('nb', 'NO'));
    expect(n.state.languageCode, 'no');
    await _settle();
    expect(n.state.languageCode, 'no');
    expect(n.isExplicit, isFalse);
    n.dispose();
  });

  test('an English or Swedish phone gets English', () async {
    final en = build(() => const Locale('en', 'GB'));
    await _settle();
    expect(en.state.languageCode, 'en');
    final sv = build(() => const Locale('sv', 'SE'));
    await _settle();
    expect(sv.state.languageCode, 'en');
    en.dispose();
    sv.dispose();
  });

  test('an explicit choice wins over the phone', () async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    final n = build(() => const Locale('nb', 'NO'));
    await _settle();
    expect(n.state.languageCode, 'en');
    expect(n.isExplicit, isTrue);
    n.dispose();
  });

  test('setLocale makes the choice explicit and persists it', () async {
    final n = build(() => const Locale('en'));
    await _settle();
    await n.setLocale('no');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('language'), 'no');
    expect(n.isExplicit, isTrue);
    n.dispose();
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
    n.dispose();
  });
}
