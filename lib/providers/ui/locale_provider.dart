import 'dart:ui';

import 'package:biso/core/constants/notification_topics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider that manages the app's locale based on user preferences
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

/// The app language for a device locale: Norwegian variants give `'no'`,
/// everything else gives `'en'`.
String appLanguageForDevice(Locale deviceLocale) =>
    pushLocaleFor(deviceLocale.languageCode);

Locale _platformLocale() => PlatformDispatcher.instance.locale;

/// State notifier for managing the app locale.
///
/// An explicit choice (saved under `language`) wins. Otherwise the app follows
/// the device language, including while the app is running.
class LocaleNotifier extends StateNotifier<Locale> with WidgetsBindingObserver {
  LocaleNotifier({
    Locale Function()? deviceLocale,
    Future<SharedPreferences> Function()? prefs,
  }) : _deviceLocale = deviceLocale ?? _platformLocale,
       _prefs = prefs ?? SharedPreferences.getInstance,
       super(
         Locale(appLanguageForDevice((deviceLocale ?? _platformLocale)())),
       ) {
    _observe();
    _loadLocale();
  }

  final Locale Function() _deviceLocale;
  final Future<SharedPreferences> Function() _prefs;
  bool _explicit = false;
  bool _observing = false;

  /// True when the user has chosen a language.
  bool get isExplicit => _explicit;

  void _observe() {
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No binding initialized (plain unit tests): nothing to observe.
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) => onDeviceLocaleChanged();

  /// Re-resolve from the device locale unless the user has chosen a language.
  void onDeviceLocaleChanged() {
    if (_explicit) return;
    state = Locale(appLanguageForDevice(_deviceLocale()));
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    super.dispose();
  }

  /// Load an explicit choice from SharedPreferences, if there is one
  Future<void> _loadLocale() async {
    try {
      final prefs = await _prefs();
      final saved = prefs.getString('language');
      if (saved == null) return;
      _explicit = true;
      if (mounted) state = Locale(saved);
    } catch (e) {
      // Keep the device-derived locale if loading fails
    }
  }

  /// Set the app locale, mark it as an explicit choice and save it
  Future<void> setLocale(String languageCode) async {
    try {
      final prefs = await _prefs();
      await prefs.setString('language', languageCode);
      _explicit = true;
      if (mounted) state = Locale(languageCode);
    } catch (e) {
      // Keep current locale if saving fails
    }
  }

  /// Get the current language code
  String get currentLanguageCode => state.languageCode;

  /// Check if the current locale is Norwegian
  bool get isNorwegian => state.languageCode == 'no';

  /// Check if the current locale is English
  bool get isEnglish => state.languageCode == 'en';
}
