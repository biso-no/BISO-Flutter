import 'package:go_router/go_router.dart';

import 'scanner_gate.dart';

const membershipScannerPath = '/explore/scan';

/// Full screen, outside the tab shell. The gate checks access on every
/// arrival, including cold starts and deep links.
GoRoute membershipScannerRoute() => GoRoute(
  path: membershipScannerPath,
  name: 'membership-scanner',
  builder: (context, state) => const ScannerGate(),
);
