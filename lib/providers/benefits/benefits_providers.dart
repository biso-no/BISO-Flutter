import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/campus_benefit.dart';
import '../../data/services/benefits_api_client.dart';

final benefitsApiProvider = Provider<BenefitsApi>((ref) => BenefitsApiClient());

/// The benefits for a campus (null: national only), in the API's order.
///
/// Auto-disposed, so each visit fetches afresh: the app stays open for days,
/// and a new deal has to show up and an ended one has to go.
///
/// Holds the list only. A revealed code is never kept in a provider.
final campusBenefitsProvider = FutureProvider.autoDispose
    .family<List<CampusBenefit>, String?>(
      (ref, campusId) =>
          ref.watch(benefitsApiProvider).fetchBenefits(campusId: campusId),
    );
