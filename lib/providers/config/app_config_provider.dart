import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_config.dart';
import '../../data/services/app_config_service.dart';

final _appConfigServiceProvider = Provider<AppConfigService>(
  (_) => AppConfigService(),
);

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  return ref.watch(_appConfigServiceProvider).getConfig();
});
