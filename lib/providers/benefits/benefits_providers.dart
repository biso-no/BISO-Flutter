import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/campus_benefit.dart';
import '../../data/services/benefits_api_client.dart';
import 'benefit_showcase.dart';

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

/// The clock the showcase reads "ending soon" and "new" against. Tests
/// override it.
final benefitClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// [campusBenefitsProvider] grouped for the screen.
final benefitShowcaseProvider = Provider.autoDispose
    .family<AsyncValue<BenefitShowcase>, String?>(
      (ref, campusId) => ref
          .watch(campusBenefitsProvider(campusId))
          .whenData(
            (list) => BenefitShowcase.from(
              list,
              now: ref.watch(benefitClockProvider)(),
            ),
          ),
    );
