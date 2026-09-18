import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/navigation_utils.dart';
import '../../providers/config/app_config_provider.dart';
import 'biso/biso.dart';

/// Shown instead of the reimbursement screens while BISO has reimbursements
/// switched off — that is, only when the server actually said so.
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

/// Shown when the app could not find out whether reimbursements are on.
///
/// Distinct from [ExpensesUnavailablePage] on purpose: a config fetch that
/// failed says nothing about BISO's settings, so the student is told what
/// actually happened — we could not load this — and given the retry that
/// re-reads the config.
class ExpensesCheckFailedPage extends ConsumerWidget {
  const ExpensesCheckFailedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BisoPage(
      title: 'Reimbursements',
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            accent: BisoAccent.coral,
            title: "We couldn't load reimbursements",
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(appConfigProvider),
              child: const Text('Try again'),
            ),
          ),
        ),
      ],
    );
  }
}
