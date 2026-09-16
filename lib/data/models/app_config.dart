import 'dart:convert';

/// The feature switches `GET /api/config` reports.
///
/// Every field is a statement about BISO's settings, so one of these may
/// only ever be built from an answer the server actually gave. The defaults
/// below are the shape of a config nobody has filled in — not a verdict to
/// fall back on when the fetch fails: `AppConfigService` throws
/// `AppConfigUnavailableException` for that, so that "we could not ask"
/// stays distinguishable from "it is switched off".
class AppConfig {
  final bool departuresEnabled;
  final bool expensesEnabled;
  final bool marketplaceEnabled;

  const AppConfig({
    this.departuresEnabled = true,
    this.expensesEnabled = false,
    this.marketplaceEnabled = true,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final features = json['features'] as Map<String, dynamic>? ?? {};

    return AppConfig(
      departuresEnabled: features['departures'] as bool? ?? true,
      expensesEnabled: features['expenses'] as bool? ?? false,
      marketplaceEnabled: features['marketplace'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode({
    'features': {
      'departures': departuresEnabled,
      'expenses': expensesEnabled,
      'marketplace': marketplaceEnabled,
    },
  });
}
