import 'package:flutter/material.dart';

import '../../../../core/utils/expense_approval_switch.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/biso/biso.dart';

/// A labelled card with a switch for the expense form's self-declaration: "I'm
/// this department's financial manager" or "I'm the campus controller". The
/// hint under the label says who approves instead when it is on.
class ApprovalSwitchCard extends StatelessWidget {
  const ApprovalSwitchCard({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
    this.national = false,
  });

  final ApprovalSwitch kind;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// True on the National campus, where the controller switch reads "I'm the
  /// controller" and the general manager approves instead.
  final bool national;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final label = switch (kind) {
      ApprovalSwitch.financialManager => l10n.expenseFinancialManagerLabel,
      ApprovalSwitch.controller when national =>
        l10n.expenseNationalControllerLabel,
      ApprovalSwitch.controller => l10n.expenseControllerLabel,
    };
    final hint = switch (kind) {
      ApprovalSwitch.financialManager => l10n.expenseFinancialManagerHint,
      ApprovalSwitch.controller when national =>
        l10n.expenseNationalControllerHint,
      ApprovalSwitch.controller => l10n.expenseControllerHint,
    };
    return BisoFormGroup(
      children: [
        MergeSemantics(
          child: InkWell(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: text.bodyLarge?.copyWith(color: palette.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: text.bodySmall?.copyWith(color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch.adaptive(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
