import 'dart:convert';

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
