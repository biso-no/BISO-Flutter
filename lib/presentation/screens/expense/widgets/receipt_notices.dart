import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/expense_v2_models.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/biso/biso.dart';

/// The entered and the scanned amount differ by more than this many kroner
/// before the receipt says so.
const receiptAmountTolerance = 1.0;

/// Sentences about one receipt: scan issues, a possible duplicate and an
/// amount that differs from what the scan read. They inform and never block
/// submit. [compact] is the smaller form for list rows.
class ReceiptNotices extends StatelessWidget {
  const ReceiptNotices({
    super.key,
    required this.receipt,
    this.compact = false,
  });

  final ExpenseReceiptDraft receipt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final messages = receiptNoticeMessages(
      AppLocalizations.of(context)!,
      Localizations.localeOf(context),
      receipt,
    );
    if (messages.isEmpty) return const SizedBox.shrink();
    final palette = BisoPalette.of(context);
    final style =
        (compact
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(color: palette.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in messages)
          Padding(
            padding: EdgeInsets.only(top: compact ? 2 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: compact ? 13 : 16,
                    color: palette.warning,
                  ),
                ),
                SizedBox(width: compact ? 6 : 8),
                Expanded(child: Text(message, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The notice sentences for [receipt], issues first.
List<String> receiptNoticeMessages(
  AppLocalizations l10n,
  Locale locale,
  ExpenseReceiptDraft receipt,
) {
  return [
    for (final code in receipt.receiptIssues.toSet())
      switch (code) {
        'not_a_receipt' => l10n.expenseReceiptIssueNotAReceipt,
        'no_items' => l10n.expenseReceiptIssueNoItems,
        'unreadable' => l10n.expenseReceiptIssueUnreadable,
        'missing_seller' => l10n.expenseReceiptIssueMissingSeller,
        'missing_date' => l10n.expenseReceiptIssueMissingDate,
        'missing_total' => l10n.expenseReceiptIssueMissingTotal,
        _ => l10n.expenseReceiptIssueGeneric,
      },
    if (receipt.possibleDuplicate) l10n.expenseReceiptDuplicate,
    if (_amountDiffers(receipt))
      l10n.expenseReceiptAmountDiffers(
        _kroner(receipt.ocrAmount!, locale),
        _kroner(receipt.effectiveAmount, locale),
      ),
  ];
}

// Both amounts are in kroner, so they compare whenever the scan read one.
bool _amountDiffers(ExpenseReceiptDraft receipt) {
  final scanned = receipt.ocrAmount;
  if (scanned == null) return false;
  return (scanned - receipt.effectiveAmount).abs() > receiptAmountTolerance;
}

String _kroner(double value, Locale locale) {
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);
  return locale.languageCode == 'en' ? text : text.replaceAll('.', ',');
}
