import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/expense_type_state.dart';
import '../../../../data/models/expense_cost_type_option.dart';
import '../../../../data/models/expense_v2_models.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/biso/biso.dart';
import 'expense_type_picker_sheet.dart';

/// The expense type of one receipt as a pill, tappable to change it in the
/// picker sheet. Shows nothing for a receipt that takes no type.
///
/// [types] is null while the list could not be read; the pill still shows the
/// current choice and the sheet offers [onRetry].
class ReceiptTypeChip extends StatelessWidget {
  const ReceiptTypeChip({
    super.key,
    required this.receipt,
    required this.types,
    required this.onChanged,
    this.onRetry,
    this.loading = false,
  });

  /// True while [types] is still being read (null then, but not an error).
  final bool loading;
  final ExpenseReceiptDraft receipt;
  final List<ExpenseCostTypeOption>? types;
  final ValueChanged<ExpenseReceiptDraft> onChanged;
  final ReloadExpenseTypes? onRetry;

  static const _tapHeight = 48.0;
  static const _pillHeight = 32.0;

  @override
  Widget build(BuildContext context) {
    if (!needsType(receipt)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);

    final ownText = receipt.costTypeText?.trim();
    final hasOwnText = ownText != null && ownText.isNotEmpty;
    final slug = receipt.costType;
    final listed = slug == null
        ? null
        : types?.where((t) => t.slug == slug).firstOrNull;
    final hasSlug = slug != null && slug.isNotEmpty;
    // Loaded types: a slug that is not among them needs a new choice. Still
    // loading: a neutral mark. Failed to load: the stored slug stands in, so
    // the choice still reads as chosen.
    final String? chosenLabel;
    if (hasOwnText) {
      chosenLabel = '“$ownText”';
    } else if (!hasSlug) {
      chosenLabel = null;
    } else if (types != null) {
      chosenLabel = listed?.labelFor(locale);
    } else {
      chosenLabel = loading ? '…' : slug;
    }

    final isAi =
        receipt.typeState == ExpenseTypeState.aiPicked && chosenLabel != null;
    final needsChoice = chosenLabel == null;

    final label = needsChoice ? l10n.expenseTypeChoose : chosenLabel;
    final color = needsChoice ? palette.warning : palette.ink;
    final fill = needsChoice
        ? palette.warning.withValues(alpha: 0.14)
        : palette.surfaceRaised;

    final pill = Container(
      height: _pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(_pillHeight / 2),
        border: needsChoice
            ? Border.all(color: palette.warning.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAi
                ? CupertinoIcons.sparkles
                : needsChoice
                ? CupertinoIcons.exclamationmark_circle
                : CupertinoIcons.tag,
            size: 15,
            color: isAi ? palette.link : color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_down, size: 12, color: palette.muted),
        ],
      ),
    );

    final tappable = Semantics(
      button: true,
      label: needsChoice
          ? l10n.expenseTypeSemanticsChoose
          : l10n.expenseTypeSemantics(label),
      excludeSemantics: true,
      onTap: () => _open(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(_tapHeight / 2),
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _tapHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: pill,
          ),
        ),
      ),
    );

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: isAi
          ? Tooltip(message: l10n.expenseTypeAiPickedTooltip, child: tappable)
          : tappable,
    );
  }

  Future<void> _open(BuildContext context) async {
    final choice = await showExpenseTypePicker(
      context,
      types: types,
      currentSlug: receipt.costType,
      currentText: receipt.costTypeText,
      onRetry: onRetry,
      loading: loading,
    );
    switch (choice) {
      case PickedType(:final slug):
        onChanged(receipt.chooseType(slug));
      case OwnText(:final text):
        onChanged(receipt.useOwnText(text));
      case null:
        break;
    }
  }
}
