import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/application_model.dart';
import '../../data/services/application_service.dart';

final applicationServiceProvider = Provider<ApplicationService>(
  (ref) => ApplicationService(),
);

/// The signed-in user's job applications with live status.
final myApplicationsProvider = FutureProvider<List<ApplicationModel>>((ref) {
  final service = ref.watch(applicationServiceProvider);
  return service.getMyApplications();
});
