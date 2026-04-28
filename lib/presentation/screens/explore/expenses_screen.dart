import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/expense_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/expense/expense_provider.dart';
import '../expense/create_expense_screen.dart';
import '../../../providers/auth/auth_provider.dart';
import '../home/premium_home_screen.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String _selectedStatus = 'all';

  final List<String> _statusFilters = [
    'all',
    'draft',
    'pending',
    'submitted',
    'success',
    'rejected',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) {
      return PremiumAuthRequiredPage(
        title: l10n.expensesMessage,
        description: 'Manage reimbursements',
        icon: Icons.receipt_long_rounded,
      );
    }
    final expensesState = ref.watch(expensesStateProvider);
    final filteredExpenses = ref.watch(
      filteredExpensesProvider(_selectedStatus),
    );

    // Show loading state
    if (expensesState.isLoading && expensesState.expenses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.expensesMessage),
          leading: IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Show error state
    if (expensesState.error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.expensesMessage),
          leading: IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error loading expenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                expensesState.error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.read(expensesStateProvider.notifier).refresh();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.expensesMessage),
        leading: IconButton(
          onPressed: () {
            // Navigate back to home screen (explore tab)
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(expensesStateProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                _showHistory(context, filteredExpenses);
              } else if (value == 'guidelines') {
                _showGuidelines(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history),
                    SizedBox(width: 12),
                    Text('View History'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'guidelines',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Text('Guidelines'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _statusFilters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final status = _statusFilters[index];
                final isSelected = _selectedStatus == status;

                return FilterChip(
                  label: Text(_getStatusDisplayName(status)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedStatus = status;
                    });
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: AppColors.subtleBlue,
                  checkmarkColor: AppColors.defaultBlue,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.defaultBlue
                        : AppColors.onSurfaceVariant,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.defaultBlue
                        : AppColors.outline,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Summary Cards Row
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Draft',
                    amount: expensesState.totalDraftAmount,
                    color: AppColors.onSurfaceVariant,
                    icon: Icons.drafts_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Pending',
                    amount: expensesState.totalPendingAmount,
                    color: AppColors.orange9,
                    icon: Icons.pending,
                  ),
                ),
              ],
            ),
          ),

          // Expenses List
          Expanded(
            child: filteredExpenses.isEmpty
                ? _EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No expenses found',
                    subtitle: 'No expenses match your current filter',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredExpenses.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final expense = filteredExpenses[index];
                      return _ExpenseCard(
                        expense: expense,
                        onTap: () => _showExpenseDetails(context, expense),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startNewExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('New Expense'),
        backgroundColor: AppColors.orange9,
      ),
    );
  }

  void _showHistory(BuildContext context, List<ExpenseModel> expenses) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final recent = expenses.take(20).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Expenses',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: recent.isEmpty
                      ? const Center(child: Text('No recent expenses'))
                      : ListView.separated(
                          itemCount: recent.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final e = recent[index];
                            return ListTile(
                              title: Text(e.description ?? 'No description'),
                              subtitle: Text(
                                '${e.displayDepartment} • ${DateFormat('MMM dd, yyyy').format(e.expenseDate)}',
                              ),
                              trailing: Text(e.displayStatus),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'NOK ${amount.toStringAsFixed(0)}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onTap;

  const _ExpenseCard({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Category Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getCategoryColor(
                        expense.category,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getCategoryIcon(expense.category),
                      color: _getCategoryColor(expense.category),
                      size: 20,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Expense Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.description ?? 'No description',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expense.displayDepartment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Amount and Status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        expense.formattedTotal,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.defaultBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            expense.status,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          expense.displayStatus,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _getStatusColor(expense.status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM dd, yyyy').format(expense.expenseDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.attach_file,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${expense.attachmentCount} files',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (expense.isPrepayment) ...[
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Prepayment',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'event':
        return AppColors.accentBlue;
      case 'travel':
        return AppColors.green9;
      case 'supplies':
        return AppColors.purple9;
      case 'food':
        return AppColors.orange9;
      case 'other':
        return AppColors.onSurfaceVariant;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'event':
        return Icons.event;
      case 'travel':
        return Icons.directions_car;
      case 'supplies':
        return Icons.shopping_cart;
      case 'food':
        return Icons.restaurant;
      case 'other':
        return Icons.receipt;
      default:
        return Icons.receipt;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return AppColors.onSurfaceVariant;
      case 'pending':
        return AppColors.orange9;
      case 'submitted':
        return AppColors.accentBlue;
      case 'success':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.onSurfaceVariant;
    }
  }
}

class _ExpenseDetailSheet extends ConsumerWidget {
  final ExpenseModel expense;
  final ScrollController scrollController;

  const _ExpenseDetailSheet({
    required this.expense,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: ListView(
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
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            expense.displayDepartment,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.defaultBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          expense.status,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        expense.displayStatus,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _getStatusColor(expense.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Amount Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.subtleBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Amount',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.defaultBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expense.formattedTotal,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: AppColors.defaultBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (expense.isPrepayment)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.defaultBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Prepayment Request',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.defaultBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Details Section
                _DetailSection(
                  title: 'Expense Details',
                  children: [
                    _DetailItem(
                      icon: Icons.calendar_today,
                      label: 'Date',
                      value: DateFormat(
                        'MMMM dd, yyyy',
                      ).format(expense.expenseDate),
                    ),
                    _DetailItem(
                      icon: Icons.category,
                      label: 'Category',
                      value: expense.displayCategory,
                    ),
                    if (expense.eventName != null)
                      _DetailItem(
                        icon: Icons.event,
                        label: 'Related Event',
                        value: expense.eventName!,
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Payment Details
                _DetailSection(
                  title: 'Payment Information',
                  children: [
                    _DetailItem(
                      icon: Icons.account_balance,
                      label: 'Bank Account',
                      value: expense.formattedBankAccount,
                    ),
                    if (expense.userName != null)
                      _DetailItem(
                        icon: Icons.person,
                        label: 'Account Holder',
                        value: expense.userName!,
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Attachments
                if (expense.expenseAttachments.isNotEmpty) ...[
                  _DetailSection(
                    title: 'Receipts & Documents',
                    children: expense.expenseAttachments.map((attachment) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.gray200,
                          child: Icon(
                            _getFileIcon(attachment.fileName),
                            color: AppColors.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        title: Text(attachment.fileName),
                        trailing: IconButton(
                          onPressed: () async {
                            final url = attachment.url;
                            if (url == null || url.isEmpty) return;
                            final uri = Uri.parse(url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                        ),
                        contentPadding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Timeline/Status History
                if (expense.approvedAt != null ||
                    expense.rejectionReason != null) ...[
                  _DetailSection(
                    title: 'Status History',
                    children: [
                      _TimelineItem(
                        icon: Icons.create,
                        title: 'Created',
                        subtitle: DateFormat(
                          'MMM dd, yyyy • HH:mm',
                        ).format(expense.createdAt!),
                        isCompleted: true,
                      ),
                      if (expense.approvedAt != null)
                        _TimelineItem(
                          icon: Icons.check_circle,
                          title: 'Approved',
                          subtitle:
                              'By ${expense.approverName} • ${DateFormat('MMM dd, yyyy • HH:mm').format(expense.approvedAt!)}',
                          isCompleted: true,
                        ),
                      if (expense.rejectionReason != null)
                        _TimelineItem(
                          icon: Icons.cancel,
                          title: 'Rejected',
                          subtitle: expense.rejectionReason!,
                          isCompleted: true,
                          isError: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Action Buttons
                if (expense.canEdit) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
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
                            await ref
                                .read(expensesStateProvider.notifier)
                                .refresh();
                            if (context.mounted && result != null) {
                              _showSubmittedSnack(context);
                            }
                          },
                          icon: const Icon(Icons.edit),
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
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete draft'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return AppColors.onSurfaceVariant;
      case 'pending':
        return AppColors.orange9;
      case 'submitted':
        return AppColors.accentBlue;
      case 'success':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  IconData _getFileIcon(String filename) {
    if (filename.toLowerCase().endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else if (filename.toLowerCase().contains('.jpg') ||
        filename.toLowerCase().contains('.png') ||
        filename.toLowerCase().contains('.jpeg')) {
      return Icons.image;
    }
    return Icons.attach_file;
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
    return ref.read(expensesStateProvider.notifier).deleteExpense(expenseId);
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isError;

  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isCompleted = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? AppColors.error
        : isCompleted
        ? AppColors.success
        : AppColors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
