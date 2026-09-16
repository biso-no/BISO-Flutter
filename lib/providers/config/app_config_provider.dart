import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_config.dart';
import '../../data/services/app_config_service.dart';

final _appConfigServiceProvider = Provider<AppConfigService>(
  (_) => AppConfigService(),
);

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  return ref.watch(_appConfigServiceProvider).getConfig();
});

/// Whether reimbursements are switched on (`expenses_module` in the admin),
/// or null while the config is still loading — or could not be loaded at
/// all. The API enforces the same switch; this only decides what the app
/// offers.
final expensesEnabledProvider = Provider<bool?>((ref) {
  return ref.watch(appConfigProvider).valueOrNull?.expensesEnabled;
});

/// What the app knows about reimbursements right now.
///
/// [off] and [unknown] are different claims and must never be shown as the
/// same thing: [off] is a decision BISO made and the app may say so, while
/// [unknown] is only the app failing to ask — an offline launch has no
/// grounds to announce anything about BISO's settings.
enum ExpensesAvailability { loading, unknown, off, on }

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
