import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/bi_sign_in_service.dart';

/// Separate from `bi_sign_in_provider.dart`, so `auth_provider.dart` can use
/// it without the two importing each other.
final biSignInServiceProvider = Provider<BiSignInService>(
  (ref) => BiSignInService(),
);
