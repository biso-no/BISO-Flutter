import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/biso/biso.dart';

/// The longest occasion text the server keeps.
const maxOccasionLength = 500;

/// The occasion question on the report: what the expense was for and who
/// attended. Types such as team meals ask for it. [errorText] is the field's own
/// error, shown below it in the error colour and announced with it.
class OccasionField extends StatelessWidget {
  const OccasionField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollPadding,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final EdgeInsets scrollPadding;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final error = errorText;
    return BisoFormGroup(
      children: [
        BisoFormRow(
          label: l10n.expenseOccasionLabel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('expense-occasion-field'),
                controller: controller,
                focusNode: focusNode,
                scrollPadding: scrollPadding,
                minLines: 2,
                maxLines: 4,
                maxLength: maxOccasionLength,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: onChanged,
                decoration: bisoInputDecoration(context, errorText: error)
                    .copyWith(
                      errorStyle: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.error),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
