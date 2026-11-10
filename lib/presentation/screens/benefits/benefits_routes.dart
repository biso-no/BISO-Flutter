/// The benefits screen, inside the Explore tab.
const benefitsPath = '/explore/benefits';

/// The `campus` value for the all-of-BISO list.
const nationalCampusParam = 'national';

/// The benefits screen. Without [campusParam] it starts on the Home campus;
/// with one it starts on that campus, or all of BISO for
/// [nationalCampusParam].
String benefitsRoute({String? campusParam}) => campusParam == null
    ? benefitsPath
    : '$benefitsPath?campus=${Uri.encodeQueryComponent(campusParam)}';

/// One deal, opened from the list loaded for [campusId] (null: all of BISO).
String benefitRoute(String benefitId, {required String? campusId}) =>
    '$benefitsPath/${Uri.encodeComponent(benefitId)}'
    '?campus=${Uri.encodeQueryComponent(pinnedCampusParam(campusId))}';

/// The campus id a `campus` value stands for; null is all of BISO.
String? campusIdFromParam(String param) =>
    param.isEmpty || param == nationalCampusParam ? null : param;

/// The `campus` value that keeps [campusId], including all of BISO.
String pinnedCampusParam(String? campusId) => campusId ?? nationalCampusParam;
