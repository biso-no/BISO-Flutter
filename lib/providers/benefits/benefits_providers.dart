import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/campus_benefit.dart';
import '../../data/services/benefits_api_client.dart';
import '../campus/campus_provider.dart';
import 'benefit_showcase.dart';

final benefitsApiProvider = Provider<BenefitsApi>((ref) => BenefitsApiClient());

/// Opens a link outside the app. A provider so tests can see what opens.
final benefitLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

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

/// Whether [campusId]'s list failed because the API has no benefits route
/// yet (an old API). The entry points hide then. While the list loads, or
/// after any other error, they stay: the benefits screen has its own retry.
final benefitsNotDeployedProvider = Provider.autoDispose.family<bool, String?>(
  (ref, campusId) =>
      switch (ref.watch(campusBenefitsProvider(campusId)).error) {
        BenefitsApiException(kind: BenefitsApiErrorKind.notDeployed) => true,
        _ => false,
      },
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

/// The campus row the API keeps all-of-BISO benefits under.
const nationalBenefitCampusId = '5';

/// The name to show for a benefits campus. Empty for all of BISO (null or
/// the national campus): widgets show `benefitsAllOfBiso` for it. While the
/// switcher list loads, or if it fails, a known campus keeps the app's own
/// name for it; only a campus no one knows reads "BISO".
final benefitCampusNameProvider = Provider.autoDispose.family<String, String?>((
  ref,
  campusId,
) {
  if (campusId == null || campusId == nationalBenefitCampusId) return '';
  final filterName = ref.watch(
    filterCampusProvider.select((c) => c.id == campusId ? c.name : null),
  );
  if (filterName != null) return filterName;
  final campuses = ref.watch(switcherCampusesProvider).valueOrNull;
  for (final campus in campuses ?? const []) {
    if (campus.id == campusId) return campus.name;
  }
  return AppConstants.campusNames[campusId] ?? 'BISO';
});
