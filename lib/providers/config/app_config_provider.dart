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
/// or null while the config is still loading. The API enforces the same
/// switch; this only decides what the app offers.
final expensesEnabledProvider = Provider<bool?>((ref) {
  return ref.watch(appConfigProvider).valueOrNull?.expensesEnabled;
});
