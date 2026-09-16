import 'package:flutter/cupertino.dart';

import '../../core/utils/navigation_utils.dart';
import 'biso/biso.dart';

/// Shown instead of the reimbursement screens while BISO has reimbursements
/// switched off.
///
/// Every way in — Explore, Profile, deep links, the share sheet and home
/// screen shortcuts — lands on those screens, so checking the switch there
/// covers them all. The API refuses submissions either way.
class ExpensesUnavailablePage extends StatelessWidget {
  const ExpensesUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BisoPage(
      title: 'Reimbursements',
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      slivers: const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.doc_text,
            accent: BisoAccent.coral,
            title: 'Reimbursements are currently unavailable',
            message:
                'You can submit expenses here again as soon as BISO switches '
                'reimbursements back on.',
          ),
        ),
      ],
    );
  }
}
