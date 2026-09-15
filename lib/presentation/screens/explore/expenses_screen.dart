import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/expense_attachment_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/expense/expense_provider.dart';
import '../../widgets/biso/biso.dart';
import '../expense/create_expense_screen.dart';
import '../home/premium_home_screen.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String _selectedStatus = 'all';
  String _searchQuery = '';

  final List<String> _statusFilters = [
    'all',
    'draft',
    'pending',
    'submitted',
    'success',
    'rejected',
  ];

  Widget _leading(BuildContext context) => BisoBackButton(
    onPressed: () =>
        NavigationUtils.safeGoBack(context, fallbackRoute: '/home'),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) {
      return PremiumAuthRequiredPage(
        title: l10n.expensesMessage,
        description: 'Manage reimbursements',
        icon: CupertinoIcons.doc_text,
      );
    }

    final expensesState = ref.watch(expensesStateProvider);
    final filteredByStatus = ref.watch(
      filteredExpensesProvider(_selectedStatus),
    );
    final filteredExpenses = _searchQuery.isEmpty
        ? filteredByStatus
        : filteredByStatus
              .where(
                (e) =>
                    (e.description ?? '').toLowerCase().contains(
                      _searchQuery,
                    ) ||
                    e.displayDepartment.toLowerCase().contains(_searchQuery),
              )
              .toList();

    // Show loading state
    if (expensesState.isLoading && expensesState.expenses.isEmpty) {
      return BisoPage(
        title: l10n.expensesMessage,
        largeTitle: false,
        leading: _leading(context),
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    // Show error state
    if (expensesState.error != null) {
      return BisoPage(
        title: l10n.expensesMessage,
        largeTitle: false,
        leading: _leading(context),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              message: expensesState.error,
              onRetry: () => ref.read(expensesStateProvider.notifier).refresh(),
            ),
          ),
        ],
      );
    }

    return BisoPage(
      title: l10n.expensesMessage,
      leading: _leading(context),
      search: BisoHeaderSearch(
        hintText: 'Search expenses...',
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase().trim()),
      ),
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.plus,
          tooltip: 'New Expense',
          onPressed: () => _startNewExpense(context),
        ),
        BisoHeaderAction(
          icon: CupertinoIcons.ellipsis,
          tooltip: l10n.moreMessage,
          onPressed: () => _showMoreSheet(context, filteredExpenses),
        ),
      ],
      onRefresh: () => ref.read(expensesStateProvider.notifier).refresh(),
      slivers: [
        SliverToBoxAdapter(
          child: BisoSection(
            child: _ExpenseSummaryCard(
              draftTotal: expensesState.totalDraftAmount,
              pendingTotal: expensesState.totalPendingAmount,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _statusFilters.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final status = _statusFilters[index];
                  return ChoiceChip(
                    label: Text(_getStatusDisplayName(status)),
                    selected: _selectedStatus == status,
                    onSelected: (selected) =>
                        setState(() => _selectedStatus = status),
                  );
                },
              ),
            ),
          ),
        ),
        if (filteredExpenses.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.doc_text,
              accent: BisoAccent.coral,
              title: 'No expenses found',
              message: 'No expenses match your current filter',
            ),
          )
        else
          SliverBisoListGroup(
            itemCount: filteredExpenses.length,
            itemBuilder: (context, index) {
              final expense = filteredExpenses[index];
              return _ExpenseRow(
                expense: expense,
                onTap: () => _showExpenseDetails(context, expense),
              );
            },
          ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, List<ExpenseModel> expenses) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.clock),
                title: 'View History',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showHistory(context, expenses);
                },
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.info_circle),
                title: 'Guidelines',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showGuidelines(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistory(BuildContext context, List<ExpenseModel> expenses) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final palette = BisoPalette.of(context);
        final recent = expenses.take(20).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Expenses',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: palette.ink),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: recent.isEmpty
                      ? const Center(child: Text('No recent expenses'))
                      : ListView.separated(
                          itemCount: recent.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final e = recent[index];
                            return BisoListRow(
                              title: e.description ?? 'No description',
                              subtitle:
                                  '${e.displayDepartment} • ${DateFormat('MMM dd, yyyy').format(e.expenseDate)}',
                              value: e.displayStatus,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGuidelines(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Expense Statuses'),
        content: const Text(
          '• Draft: Your local draft before submission.\n'
          '• Pending: Reimbursement reached our invoice mailbox.\n'
          '• Submitted: Registered to be sent in our invoice service.\n'
          '• Success: Transaction confirmed in accounting.\n'
          '• Rejected: Expense was not approved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getStatusDisplayName(String status) {
    switch (status) {
      case 'all':
        return 'All';
      case 'draft':
        return 'Draft';
      case 'pending':
        return 'Pending';
      case 'submitted':
        return 'Submitted';
      case 'success':
        return 'Success';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  void _showExpenseDetails(BuildContext context, ExpenseModel expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _ExpenseDetailSheet(
          expense: expense,
          scrollController: scrollController,
        ),
      ),
    );
  }

  Future<void> _startNewExpense(BuildContext context) async {
    final result = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(builder: (context) => const CreateExpenseScreen()),
    );
    if (!mounted) return;
    await ref.read(expensesStateProvider.notifier).refresh();
    if (result != null && context.mounted) {
      _showExpenseDetails(context, result);
    }
  }
}

/// Maps an expense's raw `status` string onto the status pill's token (the
/// Task 23 pill style: the token at 10% opacity behind, full token text).
/// `success` is this schema's "approved and paid" state, so it takes
/// [BisoPalette.success]; `draft`, `pending` and `submitted` are all still in
/// progress, so they share [BisoPalette.warning]; `rejected` takes
/// [BisoPalette.error]. Any other value (not currently used by the schema)
/// is treated the same as the in-progress states — its nearest meaning.
Color _statusColor(String status, BisoPalette palette) {
  switch (status) {
    case 'success':
      return palette.success;
    case 'rejected':
      return palette.error;
    case 'draft':
    case 'pending':
    case 'submitted':
      return palette.warning;
    default:
      return palette.warning;
  }
}

/// A small pill: [color] at 10% opacity behind, full [color] text. Reused
/// for the status pill (rows and the detail sheet header) and the
/// prepayment tag.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

/// One "label — amount" row (a summary total, or the detail sheet's Amount),
/// sized so the amount is never scaled down, and never silently clipped, at
/// any text scale (R11). Mirrors `_AmountRow` in `checkout_screen.dart` and
/// `order_screen.dart` — see either's doc comment for the full layout
/// rationale: side by side when the label can keep a real share of the row,
/// otherwise stacked; either way the amount renders on one line if it fits,
/// or, as a last resort, wraps only on the single space between the
/// currency code and the number.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.title,
    required this.amount,
    this.titleStyle,
    this.amountStyle,
  });

  final String title;
  final String amount;
  final TextStyle? titleStyle;
  final TextStyle? amountStyle;

  static const _spacing = 8.0;
  static const _minLabelFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
        child: MergeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final painter = TextPainter(
                text: TextSpan(text: amount, style: amountStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final sideBySide =
                  maxWidth.isFinite &&
                  (maxWidth - painter.width - _spacing) >=
                      maxWidth * _minLabelFraction;
              final fitsOneLine =
                  sideBySide || !maxWidth.isFinite || painter.width <= maxWidth;

              final amountText = fitsOneLine
                  ? Text(
                      amount,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      softWrap: false,
                      style: amountStyle,
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        for (final piece in amount.split(' '))
                          Text(
                            piece,
                            maxLines: 1,
                            softWrap: false,
                            style: amountStyle,
                          ),
                      ],
                    );

              final label = Text(
                title,
                maxLines: sideBySide ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              );

              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: _spacing),
                    amountText,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  label,
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: amountText),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  const _ExpenseSummaryCard({
    required this.draftTotal,
    required this.pendingTotal,
  });

  final double draftTotal;
  final double pendingTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: palette.muted,
    );
    final amountStyle = theme.textTheme.headlineMedium?.copyWith(
      color: palette.ink,
    );

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: BisoIconTile(
              icon: CupertinoIcons.creditcard,
              accent: BisoAccent.coral,
            ),
          ),
          _AmountRow(
            title: 'Draft',
            amount: 'NOK ${draftTotal.toStringAsFixed(0)}',
            titleStyle: labelStyle,
            amountStyle: amountStyle,
          ),
          _AmountRow(
            title: 'Pending',
            amount: 'NOK ${pendingTotal.toStringAsFixed(0)}',
            titleStyle: labelStyle,
            amountStyle: amountStyle,
          ),
        ],
      ),
    );
  }
}

/// The amount, above its status pill, right-aligned, sized to [width]. See
/// `_OrderAmountAndStatus` in `orders_screen.dart` (copied approach, per the
/// R11 controller ruling): [width] is content-sized, measured by
/// [_ExpenseRow] itself, so a non-flex trailing block can never make the
/// whole row overflow. [amount] never truncates or scales down: it renders
/// on one line if it fits [width], or, as a last resort, splits only on the
/// single space between the currency code and the number.
class _ExpenseAmountAndStatus extends StatelessWidget {
  const _ExpenseAmountAndStatus({
    required this.amount,
    required this.amountStyle,
    required this.statusLabel,
    required this.statusColor,
    required this.width,
  });

  final String amount;
  final TextStyle? amountStyle;
  final String statusLabel;
  final Color statusColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: amount, style: amountStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              if (painter.width <= constraints.maxWidth) {
                return Text(
                  amount,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  style: amountStyle,
                );
              }
              return Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  for (final piece in amount.split(' '))
                    Text(
                      piece,
                      maxLines: 1,
                      softWrap: false,
                      style: amountStyle,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          _Badge(label: statusLabel, color: statusColor),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.onTap});

  final ExpenseModel expense;
  final VoidCallback onTap;

  /// Everything the trailing block (`Row`'s non-flex `trailing` slot, or the
  /// stacked footer line) is reserved space for, besides itself: the
  /// [SliverBisoListGroup] margin (16pt each side), `BisoListRow`'s own
  /// padding (16pt each side), the leading icon tile (32pt) and its gap
  /// (12pt), and the gap before `trailing` (8pt). 32+32+32+12+8 = 116.
  static const _rowOverhead = 116.0;

  /// What's reserved for a stacked footer line: just the list-group margin
  /// and its own matching horizontal padding (no leading icon or gaps, since
  /// it isn't inside `BisoListRow`'s own `Row`). 16+16+16+16 = 64.
  static const _footerOverhead = 64.0;

  static const _pillPadding = 20.0; // 10pt each side, matches the Container.

  String get _subtitle {
    final date = DateFormat('MMM dd, yyyy').format(expense.expenseDate);
    final attachments = expense.attachmentCount == 1
        ? '1 file'
        : '${expense.attachmentCount} files';
    final parts = [date, expense.displayDepartment, attachments];
    if (expense.isPrepayment) parts.add('Prepayment');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final color = _statusColor(expense.status, palette);
    final label = expense.displayStatus;
    final subtitle = _subtitle;
    final amount = expense.formattedTotal;
    final amountStyle = theme.textTheme.titleSmall?.copyWith(
      color: palette.ink,
    );
    final pillStyle = theme.textTheme.labelSmall?.copyWith(color: color);

    // Measured, not guessed — see `_OrderRow` in orders_screen.dart, whose
    // approach this copies: a fixed trailing width either wastes space or
    // starves the title. Sizing the block to what its own content actually
    // needs, capped by the row's real width, gives the title back that space
    // whenever the amount/pill don't need it.
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final rowWidth = (screenWidth - _rowOverhead).clamp(0.0, double.infinity);
    final contentWidth = [
      measure(amount, amountStyle),
      measure(label, pillStyle) + _pillPadding,
    ].reduce((a, b) => a > b ? a : b);
    final trailingWidth = contentWidth < rowWidth ? contentWidth : rowWidth;

    // Side by side only if the title would still keep a real share of the
    // row (about 40%), otherwise a long description would be squeezed down
    // to almost nothing beside a trailing block sized for the amount/pill.
    final sideBySide =
        rowWidth > 0 && (rowWidth - trailingWidth) >= rowWidth * 0.4;

    final leading = const BisoIconTile(
      icon: CupertinoIcons.doc_text,
      accent: BisoAccent.coral,
    );

    final title = expense.description ?? 'No description';

    if (sideBySide) {
      return BisoListRow(
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: _ExpenseAmountAndStatus(
          amount: amount,
          amountStyle: amountStyle,
          statusLabel: label,
          statusColor: color,
          width: trailingWidth,
        ),
      );
    }

    // Not enough room beside the title: put the amount and pill on their own
    // right-aligned line under the subtitle instead.
    final footerWidth = (screenWidth - _footerOverhead).clamp(
      0.0,
      double.infinity,
    );
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: palette.ink,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _ExpenseAmountAndStatus(
                  amount: amount,
                  amountStyle: amountStyle,
                  statusLabel: label,
                  statusColor: color,
                  width: footerWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineIcon extends StatelessWidget {
  const _TimelineIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 16),
    ),
  );
}

class _ExpenseDetailSheet extends ConsumerWidget {
  final ExpenseModel expense;
  final ScrollController scrollController;

  const _ExpenseDetailSheet({
    required this.expense,
    required this.scrollController,
  });

  Future<void> _openAttachment(ExpenseAttachmentModel attachment) async {
    final url = attachment.url;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final color = _statusColor(expense.status, palette);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description ?? 'No description',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expense.displayDepartment,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: palette.link,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Badge(label: expense.displayStatus, color: color),
          ],
        ),

        const SizedBox(height: 24),

        // Amount card
        Material(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AmountRow(
                title: 'Amount',
                amount: expense.formattedTotal,
                titleStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
                amountStyle: theme.textTheme.headlineMedium?.copyWith(
                  color: palette.ink,
                ),
              ),
              if (expense.isPrepayment)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _Badge(
                      label: 'Prepayment Request',
                      color: palette.link,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Details Section
        BisoSection(
          padding: EdgeInsets.zero,
          title: 'Expense Details',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.calendar),
                title: 'Date',
                value: DateFormat('MMMM dd, yyyy').format(expense.expenseDate),
              ),
              BisoListRow(
                // Material's category icon has no direct CupertinoIcons
                // equivalent (not in R7); `tag` is the nearest fit.
                leading: const BisoIconTile(icon: CupertinoIcons.tag),
                title: 'Category',
                value: expense.displayCategory,
              ),
              if (expense.eventName != null)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.calendar,
                    accent: BisoAccent.blue,
                  ),
                  title: 'Related Event',
                  value: expense.eventName!,
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Payment Details
        BisoSection(
          padding: EdgeInsets.zero,
          title: 'Payment Information',
          child: BisoListGroup(
            children: [
              BisoListRow(
                // Material's account_balance icon has no direct
                // CupertinoIcons equivalent (not in R7); `creditcard` is the
                // nearest fit.
                leading: const BisoIconTile(
                  icon: CupertinoIcons.creditcard,
                  accent: BisoAccent.coral,
                ),
                title: 'Bank Account',
                value: expense.formattedBankAccount,
              ),
              if (expense.userName != null)
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.person_fill),
                  title: 'Account Holder',
                  value: expense.userName!,
                ),
            ],
          ),
        ),

        // Attachments
        if (expense.expenseAttachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          BisoSection(
            padding: EdgeInsets.zero,
            title: 'Receipts & Documents',
            child: BisoListGroup(
              children: [
                for (final attachment in expense.expenseAttachments)
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.paperclip),
                    title: attachment.fileName,
                    onTap: () => _openAttachment(attachment),
                  ),
              ],
            ),
          ),
        ],

        // Timeline/Status History
        if (expense.approvedAt != null || expense.rejectionReason != null) ...[
          const SizedBox(height: 16),
          BisoSection(
            padding: EdgeInsets.zero,
            title: 'Status History',
            child: BisoListGroup(
              children: [
                BisoListRow(
                  leading: _TimelineIcon(
                    icon: CupertinoIcons.add_circled,
                    color: palette.muted,
                  ),
                  title: 'Created',
                  subtitle: DateFormat(
                    'MMM dd, yyyy • HH:mm',
                  ).format(expense.createdAt!),
                ),
                if (expense.approvedAt != null)
                  BisoListRow(
                    leading: _TimelineIcon(
                      icon: CupertinoIcons.checkmark_circle_fill,
                      color: palette.success,
                    ),
                    title: 'Approved',
                    subtitle:
                        'By ${expense.approverName} • ${DateFormat('MMM dd, yyyy • HH:mm').format(expense.approvedAt!)}',
                  ),
                if (expense.rejectionReason != null)
                  BisoListRow(
                    leading: _TimelineIcon(
                      icon: CupertinoIcons.xmark_circle_fill,
                      color: palette.error,
                    ),
                    title: 'Rejected',
                    subtitle: expense.rejectionReason!,
                    destructive: true,
                  ),
              ],
            ),
          ),
        ],

        // Action Buttons
        if (expense.canEdit) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final notifier = ref.read(
                      expensesStateProvider.notifier,
                    );
                    Navigator.pop(context);
                    final result = await Navigator.push<ExpenseModel>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateExpenseScreen(
                          draftExpense: expense,
                          eventName: expense.eventName,
                        ),
                      ),
                    );
                    await notifier.refresh();
                    if (context.mounted && result != null) {
                      _showSubmittedSnack(context);
                    }
                  },
                  icon: const Icon(CupertinoIcons.pencil),
                  label: const Text('Continue editing'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final deleted = await _confirmDeleteDraft(
                      context,
                      ref,
                      expense.id,
                    );
                    if (deleted && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(CupertinoIcons.trash),
                  label: const Text('Delete draft'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showSubmittedSnack(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Expense submitted')));
  }

  Future<bool> _confirmDeleteDraft(
    BuildContext context,
    WidgetRef ref,
    String expenseId,
  ) async {
    final notifier = ref.read(expensesStateProvider.notifier);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete draft?'),
            content: const Text(
              'This draft will be removed from your expenses.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return false;
    return notifier.deleteExpense(expenseId);
  }
}
