import 'dart:convert';

import 'update_policy.dart';

/// Where an [AppConfig] came from.
enum AppConfigSource { network, cache }

/// The feature switches `GET /api/config` reports.
///
/// Every field is a statement about BISO's settings, so one of these may
/// only ever be built from an answer the server actually gave. The defaults
/// below are the shape of a config nobody has filled in — not a verdict to
/// fall back on when the fetch fails: `AppConfigService` throws
/// `AppConfigUnavailableException` for that, so that "we could not ask"
/// stays distinguishable from "it is switched off".
///
/// `source` is the one exception: it is not a BISO setting but *where* this
/// answer came from. Only a `network` answer is fresh enough to act on
/// (an update prompt, say); a `cache` answer may be an hour old.
class AppConfig {
  final bool departuresEnabled;
  final bool expensesEnabled;
  final bool marketplaceEnabled;
  final AppConfigSource source;
  final UpdatePolicy iosUpdates;
  final UpdatePolicy androidUpdates;

  const AppConfig({
    this.departuresEnabled = true,
    this.expensesEnabled = false,
    this.marketplaceEnabled = true,
    this.source = AppConfigSource.network,
    this.iosUpdates = UpdatePolicy.none,
    this.androidUpdates = UpdatePolicy.none,
  });

  factory AppConfig.fromJson(
    Map<String, dynamic> json, {
    AppConfigSource source = AppConfigSource.network,
  }) {
    final features = json['features'] as Map<String, dynamic>? ?? {};
    final versions = json['versions'];
    final byPlatform = versions is Map ? versions : const {};

    return AppConfig(
      departuresEnabled: features['departures'] as bool? ?? true,
      expensesEnabled: features['expenses'] as bool? ?? false,
      marketplaceEnabled: features['marketplace'] as bool? ?? true,
      source: source,
      iosUpdates: UpdatePolicy.fromJson(byPlatform['ios']),
      androidUpdates: UpdatePolicy.fromJson(byPlatform['android']),
    );
  }

  /// Features only: the update policy is never cached, so a cached config
  /// can't prompt anyone.
  String toJsonString() => jsonEncode({
    'features': {
      'departures': departuresEnabled,
      'expenses': expensesEnabled,
      'marketplace': marketplaceEnabled,
    },
  });
}
