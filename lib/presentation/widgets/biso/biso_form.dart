import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';
import 'biso_list.dart';

/// Form fields grouped on one surface, like iOS Settings.
class BisoFormGroup extends StatelessWidget {
  const BisoFormGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BisoSection(
    title: title,
    footer: footer,
    child: BisoListGroup(dividerIndent: 16, children: children),
  );
}

/// A label above its field. Validation messages render below the field.
class BisoFormRow extends StatelessWidget {
  const BisoFormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: BisoPalette.of(context).muted,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    ),
  );
}

/// Borderless decoration for fields inside a [BisoFormRow]; the group's
/// surface and hairlines already outline the field.
InputDecoration bisoInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? prefixText,
  String? suffixText,
}) {
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixText: prefixText,
    suffixText: suffixText,
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
  );
}
