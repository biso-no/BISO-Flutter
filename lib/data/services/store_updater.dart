import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import 'app_store_channel.dart';

/// Google Play's in-app updates, so [StoreUpdater] can be tested without
/// Play. Android only.
abstract interface class PlayUpdates {
  /// Whether Play has a newer build of this app that it allows to install as
  /// an immediate (full-screen, blocking) update.
  Future<bool> immediateUpdateAvailable();

  /// Runs Play's immediate update. On success Play installs and restarts the
  /// app, so this rarely returns; it completes normally when the student
  /// declines, and throws when Play could not run the update.
  Future<void> performImmediateUpdate();
}

/// [PlayUpdates] through the `in_app_update` plugin.
class InAppUpdatePlayUpdates implements PlayUpdates {
  const InAppUpdatePlayUpdates();

  @override
  Future<bool> immediateUpdateAvailable() async {
    final info = await InAppUpdate.checkForUpdate();
    return info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.immediateUpdateAllowed;
  }

  @override
  Future<void> performImmediateUpdate() async {
    final result = await InAppUpdate.performImmediateUpdate();
    if (result == AppUpdateResult.inAppUpdateFailed) {
      throw PlatformException(
        code: 'IN_APP_UPDATE_FAILED',
        message: 'Play could not run the immediate update',
      );
    }
  }
}

/// Opens [uri] outside the app; `false` when nothing could open it.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// What the update prompt's "Update" button does: update the app in place
/// where the store allows it, and otherwise send the student to the app's
/// store listing.
///
/// - **Android:** Play's immediate update when Play has one to offer, else
///   the Play Store app (`market:`), else the Play Store website.
/// - **iOS:** the App Store sheet inside the app ([AppStoreChannel]), else
///   the App Store link.
///
/// Every other platform does nothing: it never sees a prompt.
class StoreUpdater {
  StoreUpdater({
    required TargetPlatform platform,
    PlayUpdates? play,
    AppStoreChannel? appStore,
    UrlOpener? openUrl,
  }) : _platform = platform,
       _play = play ?? const InAppUpdatePlayUpdates(),
       _appStore = appStore ?? const AppStoreChannel(),
       _openUrl = openUrl ?? _openExternally;

  final TargetPlatform _platform;
  final PlayUpdates _play;
  final AppStoreChannel _appStore;
  final UrlOpener _openUrl;

  static final Uri _playStoreApp = Uri.parse(
    'market://details?id=${AppConstants.androidPackageName}',
  );
  static final Uri _playStoreWeb = Uri.parse(
    'https://play.google.com/store/apps/details'
    '?id=${AppConstants.androidPackageName}',
  );
  static final Uri _appStoreWeb = Uri.parse(
    'https://apps.apple.com/app/id${AppConstants.appStoreItemId}',
  );

  /// Starts the update and completes once the store UI is done with it.
  ///
  /// Never throws: a store that cannot be reached is logged, and the prompt
  /// simply stays on screen for another try.
  Future<void> startUpdate() async {
    try {
      switch (_platform) {
        case TargetPlatform.android:
          await _updateOnAndroid();
        case TargetPlatform.iOS:
          await _updateOnIos();
        default:
          return;
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'StoreUpdater: update failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _updateOnAndroid() async {
    try {
      if (await _play.immediateUpdateAvailable()) {
        await _play.performImmediateUpdate();
        return;
      }
    } catch (e, stackTrace) {
      // A sideloaded build, a device without Play, or a Play hiccup: the
      // listing still works.
      AppLogger.warning(
        'StoreUpdater: Play in-app update failed, opening the listing',
        error: e,
        stackTrace: stackTrace,
      );
    }
    if (await _open(_playStoreApp)) return;
    await _open(_playStoreWeb);
  }

  Future<void> _updateOnIos() async {
    try {
      await _appStore.showProductPage(AppConstants.appStoreItemId);
    } on PlatformException catch (e, stackTrace) {
      AppLogger.warning(
        'StoreUpdater: App Store sheet failed (${e.code}), opening the link',
        error: e,
        stackTrace: stackTrace,
      );
      await _open(_appStoreWeb);
    } on MissingPluginException catch (e, stackTrace) {
      AppLogger.warning(
        'StoreUpdater: no App Store channel, opening the link',
        error: e,
        stackTrace: stackTrace,
      );
      await _open(_appStoreWeb);
    }
  }

  /// [UrlOpener] that reads a throw as "could not open".
  Future<bool> _open(Uri uri) async {
    try {
      return await _openUrl(uri);
    } catch (e, stackTrace) {
      AppLogger.warning(
        'StoreUpdater: could not open $uri',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

final storeUpdaterProvider = Provider<StoreUpdater>(
  (ref) => StoreUpdater(platform: defaultTargetPlatform),
);
