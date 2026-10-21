import 'package:flutter/services.dart';

/// The App Store inside the app through `biso/app_store` in
/// `AppDelegate.swift`: Apple's product sheet, so a student can update
/// without leaving for the App Store app. iOS only.
class AppStoreChannel {
  const AppStoreChannel([
    this._channel = const MethodChannel('biso/app_store'),
  ]);

  final MethodChannel _channel;

  /// Presents the App Store sheet for [itemId] (a numeric App Store item id)
  /// and completes once the student dismisses it.
  ///
  /// Throws a [PlatformException] with code `load_failed` when the App Store
  /// could not load the product (or [itemId] is not numeric), `no_presenter`
  /// when the sheet could not be shown, and `busy` while another sheet is on
  /// screen. Throws a [MissingPluginException] where the native channel does
  /// not exist (any platform but iOS).
  Future<void> showProductPage(String itemId) async {
    await _channel.invokeMethod<void>('showProductPage', {'itemId': itemId});
  }
}
