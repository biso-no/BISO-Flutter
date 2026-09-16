import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_config.dart';
import '../../data/services/app_config_service.dart';

final _appConfigServiceProvider = Provider<AppConfigService>(
  (_) => AppConfigService(),
);

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  return ref.watch(_appConfigServiceProvider).getConfig();
});

/// What the app knows about reimbursements right now — whether they are
/// switched on (`expenses_module` in the admin), and whether the app could
/// find out. The API enforces the same switch; this only decides what the
/// app offers.
///
/// [off] and [unknown] are different claims and must never be shown as the
/// same thing: [off] is a decision BISO made and the app may say so, while
/// [unknown] is only the app failing to ask — an offline launch has no
/// grounds to announce anything about BISO's settings.
enum ExpensesAvailability {
  loading,
  unknown,
  off,
  on;

  /// Whether to offer a way into reimbursements — Explore's category, the
  /// Profile row. Only BISO switching them off hides those, plus the first
  /// moment of a launch before any answer, so a row does not flash in and
  /// out. When the app merely could not ask, they stay: they lead to the page
  /// that says so and offers to try again, and hiding them would leave the
  /// student no way to get there for the rest of the session.
  bool get showsEntryPoints => this == on || this == unknown;
}

final expensesAvailabilityProvider = Provider<ExpensesAvailability>((ref) {
  final config = ref.watch(appConfigProvider);
  // A value we already hold outranks an error on a later re-read: it is
  // still what the server last said.
  final value = config.valueOrNull;
  if (value != null) {
    return value.expensesEnabled
        ? ExpensesAvailability.on
        : ExpensesAvailability.off;
  }
  return config.hasError
      ? ExpensesAvailability.unknown
      : ExpensesAvailability.loading;
});
