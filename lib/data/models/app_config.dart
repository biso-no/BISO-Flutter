import 'dart:convert';

enum ContentSource { wordpress, appwrite, woocommerce }

class AppConfig {
  final ContentSource eventsSource;
  final ContentSource jobsSource;
  final ContentSource productsSource;
  final bool departuresEnabled;
  final bool expensesEnabled;
  final bool marketplaceEnabled;

  const AppConfig({
    this.eventsSource = ContentSource.wordpress,
    this.jobsSource = ContentSource.wordpress,
    this.productsSource = ContentSource.woocommerce,
    this.departuresEnabled = true,
    this.expensesEnabled = false,
    this.marketplaceEnabled = true,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    ContentSource parseSource(String? val, ContentSource fallback) {
      switch (val) {
        case 'appwrite':
          return ContentSource.appwrite;
        case 'woocommerce':
          return ContentSource.woocommerce;
        case 'wordpress':
          return ContentSource.wordpress;
        default:
          return fallback;
      }
    }

    final content = json['content'] as Map<String, dynamic>? ?? {};
    final features = json['features'] as Map<String, dynamic>? ?? {};

    return AppConfig(
      eventsSource: parseSource(
        content['events_source']?.toString(),
        ContentSource.wordpress,
      ),
      jobsSource: parseSource(
        content['jobs_source']?.toString(),
        ContentSource.wordpress,
      ),
      productsSource: parseSource(
        content['products_source']?.toString(),
        ContentSource.woocommerce,
      ),
      departuresEnabled: features['departures'] as bool? ?? true,
      expensesEnabled: features['expenses'] as bool? ?? false,
      marketplaceEnabled: features['marketplace'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode({
    'content': {
      'events_source': eventsSource.name,
      'jobs_source': jobsSource.name,
      'products_source': productsSource.name,
    },
    'features': {
      'departures': departuresEnabled,
      'expenses': expensesEnabled,
      'marketplace': marketplaceEnabled,
    },
  });
}
