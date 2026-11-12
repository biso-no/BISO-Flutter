import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/expense_type_search.dart';
import '../../../../core/utils/expense_type_state.dart';
import '../../../../data/models/expense_cost_type_option.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/biso/biso.dart';

/// What the student chose in the type picker.
sealed class ExpenseTypeChoice {
  const ExpenseTypeChoice();
}

/// A type from the list.
class PickedType extends ExpenseTypeChoice {
  const PickedType(this.slug);

  final String slug;
}

/// Words the student typed themselves; finance places them later.
class OwnText extends ExpenseTypeChoice {
  const OwnText(this.text);

  final String text;
}

/// Reads the types again for the sheet's retry. Null means still unavailable.
typedef ReloadExpenseTypes = Future<List<ExpenseCostTypeOption>?> Function();

/// Opens the type picker. [types] is null while the list could not be read:
/// the sheet then says so and offers [onRetry]. Returns null when dismissed.
Future<ExpenseTypeChoice?> showExpenseTypePicker(
  BuildContext context, {
  required List<ExpenseCostTypeOption>? types,
  String? currentSlug,
  String? currentText,
  ReloadExpenseTypes? onRetry,
}) {
  return showBisoSheet<ExpenseTypeChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetContext, scrollController) => ExpenseTypePickerSheet(
        types: types,
        currentSlug: currentSlug,
        currentText: currentText,
        onRetry: onRetry,
        scrollController: scrollController,
      ),
    ),
  );
}

/// The searchable list of expense types. The last row offers the typed words
/// as the type when no listed type has exactly that name.
class ExpenseTypePickerSheet extends StatefulWidget {
  const ExpenseTypePickerSheet({
    super.key,
    required this.types,
    required this.scrollController,
    this.currentSlug,
    this.currentText,
    this.onRetry,
  });

  final List<ExpenseCostTypeOption>? types;
  final String? currentSlug;
  final String? currentText;
  final ReloadExpenseTypes? onRetry;
  final ScrollController scrollController;

  @override
  State<ExpenseTypePickerSheet> createState() => _ExpenseTypePickerSheetState();
}

class _ExpenseTypePickerSheetState extends State<ExpenseTypePickerSheet> {
  late final TextEditingController _controller;
  late List<ExpenseCostTypeOption>? _types;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _types = widget.types;
    final ownText = widget.currentSlug == null ? widget.currentText : null;
    _controller = TextEditingController(text: ownText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(ExpenseCostTypeOption type) =>
      Navigator.pop(context, PickedType(type.slug));

  void _submit() {
    final types = _types;
    final typed = _controller.text.trim();
    if (types == null || typed.isEmpty) return;
    final match = exactTypeMatch(types, typed);
    Navigator.pop(
      context,
      match != null ? PickedType(match.slug) : OwnText(typed),
    );
  }

  Future<void> _retry() async {
    final reload = widget.onRetry;
    if (reload == null || _retrying) return;
    setState(() => _retrying = true);
    final types = await reload();
    if (!mounted) return;
    setState(() {
      _types = types;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final types = _types;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.expenseTypePickerTitle,
                  style: text.headlineSmall?.copyWith(color: palette.ink),
                ),
              ),
            ),
            if (types == null)
              Expanded(child: _buildLoadError(l10n, palette, text))
            else ...[
              _buildSearchField(l10n, palette),
              const SizedBox(height: 12),
              Expanded(child: _buildList(types, l10n, palette, text)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n, BisoPalette palette) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: maxOwnTypeTextLength,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) => null,
          decoration: bisoInputDecoration(
            context,
            hintText: l10n.expenseTypeSearchHint,
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    List<ExpenseCostTypeOption> types,
    AppLocalizations l10n,
    BisoPalette palette,
    TextTheme text,
  ) {
    final locale = Localizations.localeOf(context);
    final typed = _controller.text.trim();
    final matches = searchTypes(types, typed, locale);
    final showOwn = typed.isNotEmpty && exactTypeMatch(types, typed) == null;
    return CustomScrollView(
      controller: widget.scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (types.isEmpty && !showOwn)
          SliverToBoxAdapter(
            child: _StateMessage(
              icon: CupertinoIcons.tag,
              message: l10n.expenseTypePickerEmpty,
            ),
          ),
        if (matches.isNotEmpty)
          SliverBisoListGroup(
            itemCount: matches.length,
            margin: const EdgeInsets.only(bottom: 16),
            dividerIndent: 16,
            itemBuilder: (context, index) {
              final type = matches[index];
              final selected = type.slug == widget.currentSlug;
              return BisoListRow(
                title: type.labelFor(locale),
                trailing: selected
                    ? Icon(CupertinoIcons.checkmark, color: palette.link)
                    : null,
                showChevron: false,
                onTap: () => _pick(type),
              );
            },
          ),
        if (showOwn)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _OwnTextRow(
                typed: typed,
                onTap: () => Navigator.pop(context, OwnText(typed)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadError(
    AppLocalizations l10n,
    BisoPalette palette,
    TextTheme text,
  ) {
    return ListView(
      controller: widget.scrollController,
      children: [
        _StateMessage(
          icon: CupertinoIcons.exclamationmark_triangle,
          color: palette.warning,
          title: l10n.expenseTypesLoadFailedTitle,
          message: l10n.expenseTypesLoadFailedBody,
          action: widget.onRetry == null
              ? null
              : FilledButton(
                  onPressed: _retrying ? null : _retry,
                  child: _retrying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.expenseTypesRetry),
                ),
        ),
      ],
    );
  }
}

/// The last row: the typed words as the type, set apart by a tinted surface
/// and a pencil, with a line saying finance will place it.
class _OwnTextRow extends StatelessWidget {
  const _OwnTextRow({required this.typed, required this.onTap});

  final String typed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    return Material(
      color: palette.link.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: BisoListRow(
        leading: const BisoIconTile(
          icon: CupertinoIcons.pencil,
          accent: BisoAccent.blue,
        ),
        title: l10n.expenseTypeUseOwn(typed),
        subtitle: l10n.expenseTypeUseOwnHint,
        showChevron: false,
        onTap: onTap,
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.message,
    this.title,
    this.color,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? title;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color ?? palette.muted),
          const SizedBox(height: 12),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: palette.ink),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: palette.muted),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
