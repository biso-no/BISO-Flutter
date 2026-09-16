import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/norwegian_bank_account.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/expense_v2_models.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/expense_api_client.dart';
import '../../../data/services/expense_intake_service.dart';
import '../../../data/services/expense_service_v2.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/config/app_config_provider.dart';
import '../../../providers/expense/expense_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/expenses_unavailable_page.dart';
import '../home/premium_home_screen.dart';

class CreateExpenseScreen extends ConsumerStatefulWidget {
  final String? eventId;
  final String? eventName;
  final ExpenseModel? draftExpense;
  final String? intakeBatchId;

  /// Why a share never became a batch — the share sheet already told the
  /// student their receipt was added, so the refusal has to land somewhere
  /// they will read it.
  final String? intakeError;

  const CreateExpenseScreen({
    super.key,
    this.eventId,
    this.eventName,
    this.draftExpense,
    this.intakeBatchId,
    this.intakeError,
  });

  @override
  ConsumerState<CreateExpenseScreen> createState() =>
      _CreateExpenseScreenState();
}

class _CreateExpenseScreenState extends ConsumerState<CreateExpenseScreen> {
  late final ExpenseServiceV2 _expenseService;
  late final ExpenseApiClient _apiClient;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _eventController = TextEditingController();

  List<Map<String, String>> _campuses = [];
  List<Map<String, String>> _departments = [];
  ExpenseAssignment? _assignment;
  List<ExpenseReceiptDraft> _receipts = [];
  String? _selectedReceiptId;
  String? _draftExpenseId;
  String? _lastSummarySnapshot;
  bool _isLoadingLookups = true;
  bool _isSavingDraft = false;
  bool _isSubmitting = false;
  bool _isSummaryLoading = false;
  bool _isImportingIntakeBatch = false;
  String? _flowError;
  int _mobileTabIndex = 0;
  final Set<String> _importedIntakeBatchIds = {};

  @override
  void initState() {
    super.initState();
    _expenseService = ref.read(expenseServiceProvider);
    _apiClient = ref.read(expenseApiClientProvider);
    _draftExpenseId = widget.draftExpense?.id;
    _flowError = widget.intakeError;
    _descriptionController.text = widget.draftExpense?.description ?? '';
    _eventController.text =
        widget.eventName ?? widget.draftExpense?.eventName ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLookups());
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  bool get _hasAssignment => _assignment?.isComplete == true;
  bool get _hasBusyReceipts => _receipts.any((receipt) => receipt.isBusy);
  bool get _hasReadyExpenseReceipts =>
      _receipts.any((receipt) => receipt.isReady && !receipt.isBankStatement);
  List<ExpenseReceiptDraft> get _readyReceipts =>
      _receipts.where((receipt) => receipt.isReady).toList();
  double get _totalAmount => _readyReceipts
      .where((receipt) => !receipt.isBankStatement)
      .fold(0, (sum, receipt) => sum + receipt.effectiveAmount);

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);
    try {
      final rawCampuses = await _expenseService.listCampuses();
      final campuses = rawCampuses
          .map<Map<String, String>>(
            (campus) => {
              'id': (campus['\$id'] ?? campus['id'] ?? '').toString(),
              'name': (campus['name'] ?? '').toString(),
            },
          )
          .where(
            (campus) => campus['id']!.isNotEmpty && campus['name']!.isNotEmpty,
          )
          .toList();

      _campuses = campuses;
      final draft = widget.draftExpense;
      final user = ref.read(currentUserProvider);
      final initialCampusId = draft?.campus.isNotEmpty == true
          ? draft!.campus
          : user?.campusId;
      if (initialCampusId != null && initialCampusId.isNotEmpty) {
        final campusName = campuses.firstWhere(
          (campus) => campus['id'] == initialCampusId,
          orElse: () => {'id': initialCampusId, 'name': initialCampusId},
        )['name']!;
        _assignment = ExpenseAssignment(
          campusId: initialCampusId,
          campusName: campusName,
          departmentId: draft?.department ?? '',
          departmentName: draft?.departmentName ?? draft?.department ?? '',
        );
        await _loadDepartments(initialCampusId);
      }
      if (draft != null) _hydrateDraft(draft);
    } catch (e) {
      _flowError = 'Failed to load campuses: $e';
    } finally {
      if (mounted) setState(() => _isLoadingLookups = false);
    }
  }

  void _hydrateDraft(ExpenseModel draft) {
    if (draft.expenseAttachments.isEmpty) return;
    _receipts = draft.expenseAttachments.map((attachment) {
      final rawUrl = attachment.url ?? '';
      final fileId = _extractAppwriteFileId(rawUrl);
      return ExpenseReceiptDraft(
        localId: attachment.id ?? _newLocalId(),
        fileName: fileId ?? attachment.fileName,
        fileId: fileId,
        viewUrl: rawUrl.startsWith('http') ? rawUrl : null,
        mimeType: _normalizeAttachmentType(attachment.type),
        status: ExpenseReceiptStatus.ready,
        date: attachment.date,
        amount: attachment.amount,
        amountInNok: attachment.amount,
        description: attachment.description ?? '',
      );
    }).toList();
    _selectedReceiptId = _receipts.isNotEmpty ? _receipts.first.localId : null;
  }

  Future<void> _loadDepartments(String campusId) async {
    final list = await _expenseService.listDepartmentsForCampus(campusId);
    final mapped = list
        .where((department) => department['active'] != false)
        .map<Map<String, String>>(
          (department) => {
            'id': (department['Id'] ?? department['\$id'] ?? '').toString(),
            'name': (department['Name'] ?? department['name'] ?? '').toString(),
          },
        )
        .where(
          (department) =>
              department['id']!.isNotEmpty && department['name']!.isNotEmpty,
        )
        .toList();
    if (!mounted) return;
    setState(() {
      _departments = mapped;
      final current = _assignment;
      if (current != null && current.departmentId.isNotEmpty) {
        final match = mapped.where(
          (dept) => dept['id'] == current.departmentId,
        );
        if (match.isNotEmpty) {
          final dept = match.first;
          _assignment = ExpenseAssignment(
            campusId: current.campusId,
            campusName: current.campusName,
            departmentId: dept['id']!,
            departmentName: dept['name']!,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (ref.watch(expensesAvailabilityProvider)) {
      case ExpensesAvailability.off:
        return const ExpensesUnavailablePage();
      case ExpensesAvailability.unknown:
        return const ExpensesCheckFailedPage();
      case ExpensesAvailability.loading:
      case ExpensesAvailability.on:
        break;
    }

    final user = ref.watch(currentUserProvider);
    final profileReadiness = ExpenseProfileReadiness.fromUser(user);

    if (user == null) {
      return const PremiumAuthRequiredPage(
        title: 'New reimbursement',
        description:
            'Sign in to attach shared receipts and submit reimbursements.',
        icon: CupertinoIcons.doc_text,
      );
    }

    if (_isLoadingLookups) {
      return const BisoPage(
        title: 'New reimbursement',
        largeTitle: false,
        slivers: [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    _scheduleIntakeImportIfReady(user);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeaveIfNeeded();
        if (shouldLeave && context.mounted) {
          NavigationUtils.safeGoBack(
            context,
            fallbackRoute: '/explore/expenses',
          );
        }
      },
      child: BisoPage(
        title: _draftExpenseId == null
            ? 'New reimbursement'
            : 'Draft reimbursement',
        largeTitle: false,
        automaticallyImplyLeading: false,
        leading: BisoGlassCapsule(
          children: [
            BisoCapsuleButton(
              icon: CupertinoIcons.xmark,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () async {
                final shouldLeave = await _confirmLeaveIfNeeded();
                if (shouldLeave && context.mounted) {
                  NavigationUtils.safeGoBack(
                    context,
                    fallbackRoute: '/explore/expenses',
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          BisoHeaderAction(
            icon: CupertinoIcons.tray_arrow_down,
            tooltip: 'Save draft',
            onPressed: _canSaveDraft(user) ? () => _saveDraft(user) : null,
          ),
        ],
        // The wallet/report split (a side-by-side pane on wide screens, a
        // tabbed pane on narrow ones, each with its own selection state) does
        // not decompose into one linear scroll list the way `slivers:` wants
        // — the recipe reserves `body:` for exactly this shape (PageView-like
        // screens). The assignment gate below shares the same `body:` return
        // so both branches of this conditional agree on which BisoPage slot
        // they fill; see the report's Deviations section.
        body: _hasAssignment
            ? _buildSplitFlow(user, profileReadiness)
            : _buildAssignmentGate(user),
      ),
    );
  }

  Widget _buildAssignmentGate(UserModel? user) {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        final text = Theme.of(context).textTheme;
        final insets = BisoPageInsets.maybeOf(context);
        final padding = insets != null
            ? EdgeInsets.fromLTRB(24, insets.top + 24, 24, insets.bottom + 24)
            : const EdgeInsets.all(24);
        return SingleChildScrollView(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: BisoIconTile(
                      icon: CupertinoIcons.building_2_fill,
                      accent: BisoAccent.coral,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Choose cost allocation',
                    style: text.headlineSmall?.copyWith(color: palette.ink),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select the campus and department responsible for this reimbursement before uploading receipts.',
                    style: text.bodyMedium?.copyWith(color: palette.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  BisoFormGroup(
                    children: [
                      BisoListRow(
                        title: 'Campus',
                        value: _assignment?.campusId.isNotEmpty == true
                            ? _assignment!.campusName
                            : 'Select',
                        onTap: _campuses.isEmpty ? null : _showCampusPicker,
                      ),
                      BisoListRow(
                        title: 'Department',
                        value: _assignment?.departmentId.isNotEmpty == true
                            ? _assignment!.departmentName
                            : 'Select',
                        onTap: _assignment == null || _departments.isEmpty
                            ? null
                            : _showDepartmentPicker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _hasAssignment ? () => setState(() {}) : null,
                    icon: const Icon(CupertinoIcons.chevron_forward),
                    label: const Text('Continue'),
                  ),
                  if (_flowError != null) ...[
                    const SizedBox(height: 12),
                    Text(_flowError!, style: TextStyle(color: palette.error)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCampusPicker() async {
    await showBisoSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetContext, scrollController) => _AssignmentPickerSheet(
          title: 'Campus',
          options: _campuses,
          selectedId: _assignment?.campusId,
          scrollController: scrollController,
          onSelected: (id, name) {
            Navigator.pop(sheetContext);
            _selectCampus(id, name);
          },
        ),
      ),
    );
  }

  Future<void> _selectCampus(String campusId, String campusName) async {
    setState(() {
      _assignment = ExpenseAssignment(
        campusId: campusId,
        campusName: campusName,
        departmentId: '',
        departmentName: '',
      );
      _departments = [];
    });
    await _loadDepartments(campusId);
  }

  void _showDepartmentPicker() {
    final assignment = _assignment;
    if (assignment == null) return;
    showBisoSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetContext, scrollController) => _AssignmentPickerSheet(
          title: 'Department',
          options: _departments,
          selectedId: assignment.departmentId,
          scrollController: scrollController,
          onSelected: (id, name) {
            Navigator.pop(sheetContext);
            _selectDepartment(id, name);
          },
        ),
      ),
    );
  }

  void _selectDepartment(String departmentId, String departmentName) {
    final current = _assignment!;
    setState(() {
      _assignment = ExpenseAssignment(
        campusId: current.campusId,
        campusName: current.campusName,
        departmentId: departmentId,
        departmentName: departmentName,
      );
    });
    _maybeGenerateSummary();
  }

  Widget _buildSplitFlow(
    UserModel? user,
    ExpenseProfileReadiness profileReadiness,
  ) {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        final insets = BisoPageInsets.maybeOf(context);
        final topPadding =
            insets?.top ??
            MediaQuery.paddingOf(context).top + kBisoHeaderHeight;
        final isWide = MediaQuery.sizeOf(context).width >= 820;

        final content = isWide
            ? Row(
                children: [
                  SizedBox(width: 390, child: _buildReceiptWallet()),
                  VerticalDivider(width: 1, color: palette.hairline),
                  Expanded(child: _buildReportPane(user, profileReadiness)),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('Receipts'),
                          icon: Icon(CupertinoIcons.doc_text),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('Report'),
                          icon: Icon(CupertinoIcons.doc_plaintext),
                        ),
                      ],
                      selected: {_mobileTabIndex},
                      onSelectionChanged: (selection) {
                        setState(() => _mobileTabIndex = selection.first);
                      },
                    ),
                  ),
                  Expanded(
                    child: _mobileTabIndex == 0
                        ? _buildReceiptWallet()
                        : _buildReportPane(user, profileReadiness),
                  ),
                ],
              );

        return Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: content,
        );
      },
    );
  }

  Widget _buildReceiptWallet() {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        final text = Theme.of(context).textTheme;
        final bottomInset = BisoPageInsets.maybeOf(context)?.bottom ?? 16;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Receipt wallet',
                    style: text.titleLarge?.copyWith(color: palette.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload images or PDFs. OCR runs after upload.',
                    style: text.bodySmall?.copyWith(color: palette.muted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickCameraReceipt(),
                          icon: const Icon(CupertinoIcons.camera),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImageReceipt(),
                          icon: const Icon(CupertinoIcons.photo),
                          label: const Text('Photo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickDocumentReceipt(),
                    icon: const Icon(CupertinoIcons.paperclip),
                    label: const Text('PDF receipt'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.hairline),
            Expanded(
              child: _receipts.isEmpty
                  ? const SingleChildScrollView(
                      child: BisoEmptyState(
                        icon: CupertinoIcons.doc_text,
                        accent: BisoAccent.coral,
                        title: 'No receipts yet',
                        message:
                            'Receipts are required before this can be submitted.',
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        bottomInset + 16,
                      ),
                      children: _buildGroupedReceiptTiles(),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildGroupedReceiptTiles() {
    final topLevel = _receipts.where((r) => r.parentReceiptId == null).toList();
    final rows = <Widget>[];
    for (final receipt in topLevel) {
      rows.add(_receiptRow(receipt, indent: false));
      final children = _receipts
          .where((r) => r.parentReceiptId == receipt.localId)
          .toList();
      for (final child in children) {
        rows.add(_receiptRow(child, indent: true));
      }
    }
    return [BisoListGroup(children: rows)];
  }

  Widget _receiptRow(ExpenseReceiptDraft receipt, {required bool indent}) {
    return _ReceiptRow(
      receipt: receipt,
      isSelected: receipt.localId == _selectedReceiptId,
      indent: indent,
      onTap: () => setState(() {
        _selectedReceiptId = receipt.localId;
        _mobileTabIndex = 1;
      }),
      onRemove: () => _removeReceipt(receipt.localId),
      onRetry: receipt.localPath != null
          ? () => _processReceipt(receipt.localId)
          : null,
    );
  }

  Widget _buildReportPane(
    UserModel? user,
    ExpenseProfileReadiness profileReadiness,
  ) {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        final insets = BisoPageInsets.maybeOf(context);
        final scrollPadding = insets != null
            ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
            : const EdgeInsets.all(20);
        final selected = _selectedReceipt();
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                children: [
                  if (!profileReadiness.isReady)
                    _WarningBanner(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      color: palette.warning,
                      title: 'Complete your profile',
                      message:
                          'Missing: ${profileReadiness.missingFields.join(', ')}',
                      actionLabel: 'Update',
                      onAction: () => _showProfileCompletionSheet(user),
                    ),
                  if (_hasBusyReceipts)
                    _InfoBanner(
                      icon: CupertinoIcons.hourglass,
                      color: palette.link,
                      title: 'Processing receipts',
                      message:
                          'Drafts and submissions wait until upload and OCR finish.',
                    ),
                  if (_isImportingIntakeBatch)
                    _InfoBanner(
                      icon: CupertinoIcons.arrow_up_circle,
                      color: palette.link,
                      title: 'Importing shared receipts',
                      message:
                          'Files shared with BISO are being added to this reimbursement.',
                    ),
                  if (_flowError != null)
                    _WarningBanner(
                      icon: CupertinoIcons.exclamationmark_circle,
                      color: palette.error,
                      title: 'Expense error',
                      message: _flowError!,
                      actionLabel: 'Dismiss',
                      onAction: () => setState(() => _flowError = null),
                    ),
                  _buildReportDocument(context, user, scrollPadding),
                  const SizedBox(height: 20),
                  if (selected != null)
                    _ReceiptDetailEditor(
                      receipt: selected,
                      scrollPadding: scrollPadding,
                      onChanged: _updateReceipt,
                      onAddBankStatement:
                          selected.isForeignCurrency && !selected.isBankStatement
                          ? () => _pickBankStatement(selected.localId)
                          : null,
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + (insets?.bottom ?? 0),
              ),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _canSaveDraft(user)
                          ? () => _saveDraft(user)
                          : null,
                      icon: _isSavingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.tray_arrow_down),
                      label: Text(
                        _draftExpenseId == null ? 'Save draft' : 'Update draft',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canSubmit(user, profileReadiness)
                          ? () => _submit(user)
                          : null,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.paperplane_fill),
                      label: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReportDocument(
    BuildContext context,
    UserModel? user,
    EdgeInsets scrollPadding,
  ) {
    final assignment = _assignment!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: _AmountRow(
              title: 'Reimbursement report',
              subtitle: _draftExpenseId == null
                  ? DateFormat.yMMMd().format(DateTime.now())
                  : 'Draft $_draftExpenseId',
              amount: 'NOK ${_totalAmount.toStringAsFixed(2)}',
              titleStyle: text.titleLarge?.copyWith(color: palette.ink),
              subtitleStyle: text.bodySmall?.copyWith(color: palette.muted),
              amountStyle: text.headlineSmall?.copyWith(color: palette.ink),
            ),
          ),
        ),
        const SizedBox(height: 16),
        BisoFormGroup(
          // Reuses the exact wording expenses_screen.dart's detail sheet
          // already uses for the same concept (a hardcoded title there
          // too, not an ARB key) rather than inventing new copy.
          title: 'Payment Information',
          children: [
            BisoListRow(
              title: user?.name ?? 'Unknown user',
              subtitle: user?.email ?? '',
            ),
            // The refund destination must never truncate or scale (R11),
            // so this is `_AmountRow`'s label-beside-value layout rather
            // than `BisoListRow(value:)`, whose `Flexible`+ellipsis can
            // clip a long formatted account number at large text scales.
            _AmountRow(
              title: 'Bank account',
              amount: user?.bankAccount == null
                  ? 'Missing'
                  : formatNorwegianBankAccount(user!.bankAccount!),
              titleStyle: text.titleMedium?.copyWith(color: palette.ink),
              amountStyle: text.bodyLarge?.copyWith(color: palette.muted),
              allowWrapFallback: false,
            ),
            BisoListRow(
              title: assignment.campusName,
              value: assignment.departmentName,
            ),
          ],
        ),
        const SizedBox(height: 16),
        BisoFormGroup(
          title: _isSummaryLoading ? 'Generating summary...' : 'Accounting summary',
          children: [
            BisoFormRow(
              label: 'What was this expense for?',
              child: TextField(
                controller: _descriptionController,
                maxLines: 4,
                scrollPadding: scrollPadding,
                decoration: bisoInputDecoration(
                  context,
                  suffixIcon: _isSummaryLoading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Regenerate summary',
                          onPressed: _hasReadyExpenseReceipts
                              ? () => _maybeGenerateSummary(force: true)
                              : null,
                          icon: const Icon(CupertinoIcons.sparkles),
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        BisoSection(
          title: 'Receipts',
          padding: EdgeInsets.zero,
          child: BisoListGroup(
            children: [
              if (_readyReceipts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No ready receipts yet.',
                    style: text.bodyMedium?.copyWith(color: palette.muted),
                  ),
                )
              else
                for (final receipt in _readyReceipts)
                  _ReportReceiptRow(receipt: receipt),
              _AmountRow(
                // "Total" lives in the label, not the amount string: the
                // amount must stay exactly `currency code + space + number`
                // so its Tier-3 fallback (wrap only on that one space) still
                // applies — an extra word in the amount string would let it
                // wrap in the wrong place instead.
                title: '${_readyReceipts.length} file(s) · Total',
                amount: 'NOK ${_totalAmount.toStringAsFixed(2)}',
                titleStyle: text.bodyMedium?.copyWith(color: palette.muted),
                amountStyle: text.titleMedium?.copyWith(color: palette.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickCameraReceipt() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image != null) await _addFile(File(image.path));
  }

  Future<void> _pickImageReceipt() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image != null) await _addFile(File(image.path));
  }

  Future<void> _pickDocumentReceipt() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final picked in result.files) {
      final path = picked.path;
      if (path != null) await _addFile(File(path));
    }
  }

  Future<void> _pickBankStatement(String parentReceiptId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    if (result == null || result.files.first.path == null) return;
    await _addFile(
      File(result.files.first.path!),
      purpose: 'bank-statement',
      parentReceiptId: parentReceiptId,
    );
  }

  void _scheduleIntakeImportIfReady(UserModel? user) {
    final batchId = widget.intakeBatchId;
    if (batchId == null ||
        batchId.isEmpty ||
        user == null ||
        _isLoadingLookups ||
        _isImportingIntakeBatch ||
        _importedIntakeBatchIds.contains(batchId)) {
      return;
    }
    _importedIntakeBatchIds.add(batchId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _importIntakeBatch(batchId);
    });
  }

  Future<void> _importIntakeBatch(String batchId) async {
    setState(() {
      _isImportingIntakeBatch = true;
      _flowError = null;
    });
    try {
      final batch = await ExpenseIntakeService.instance.getBatch(batchId);
      if (batch == null || batch.files.isEmpty) {
        setState(() {
          _flowError =
              'Shared receipt batch was not found. Try sharing the files again.';
        });
        return;
      }

      var importedCount = 0;
      for (final intakeFile in batch.files) {
        if (!mounted) return;
        if (await intakeFile.file.exists()) {
          final added = await _addFile(intakeFile.file);
          if (added) importedCount += 1;
        }
      }

      // Files the intake had to leave out of the batch — the wrong type, or
      // too big. They were shared, so they have to be accounted for.
      if (batch.skippedFileNames.isNotEmpty && mounted) {
        setState(
          () => _flowError = ExpenseIntakeService.skippedFilesMessage(
            batch.skippedFileNames,
          ),
        );
      }

      if (importedCount == 0) {
        // `_addFile` already set a specific reason (unsupported type, too
        // large) for whichever file it rejected; only fall back to a
        // generic message when nothing more specific was set (for example,
        // every file in the batch was missing from disk).
        setState(
          () => _flowError ??= 'No shared receipt files could be imported.',
        );
      } else {
        _showSnack(
          importedCount == 1
              ? 'Imported 1 shared file'
              : 'Imported $importedCount shared files',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _flowError = 'Shared import failed: $e');
    } finally {
      if (mounted) setState(() => _isImportingIntakeBatch = false);
    }
  }

  /// Adds [file] as a receipt and returns whether it actually did — callers
  /// that count imports (for example `_importIntakeBatch`) must only count
  /// a `true` result, since this can reject the file without throwing.
  Future<bool> _addFile(
    File file, {
    String purpose = 'receipt',
    String? parentReceiptId,
  }) async {
    final mimeType = detectExpenseMimeType(file.path);
    if (!_isSupportedOcrMime(mimeType)) {
      setState(() {
        _flowError = 'Unsupported file type for OCR: $mimeType';
      });
      return false;
    }
    if (await file.length() > 10 * 1024 * 1024) {
      setState(() {
        _flowError = 'Files must be 10 MB or smaller.';
      });
      return false;
    }

    final receipt =
        ExpenseReceiptDraft.manual(
          localId: _newLocalId(),
          fileName: file.uri.pathSegments.last,
          localPath: file.path,
          mimeType: mimeType,
        ).copyWith(
          documentType: purpose == 'bank-statement'
              ? 'bank-statement'
              : 'receipt',
          parentReceiptId: parentReceiptId,
        );

    setState(() {
      _receipts = [..._receipts, receipt];
      _selectedReceiptId = receipt.localId;
      _mobileTabIndex = 1;
    });
    await _processReceipt(receipt.localId, purpose: purpose);
    return true;
  }

  Future<void> _processReceipt(String localId, {String? purpose}) async {
    final current = _receipts.firstWhere(
      (receipt) => receipt.localId == localId,
    );
    final path = current.localPath;
    if (path == null) return;

    try {
      _replaceReceipt(
        current.copyWith(status: ExpenseReceiptStatus.uploading, error: null),
      );
      final upload = await _apiClient.uploadExpenseAttachment(File(path));
      _replaceReceipt(
        current
            .withUpload(upload)
            .copyWith(status: ExpenseReceiptStatus.processing),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      final uploaded = _receipts.firstWhere(
        (receipt) => receipt.localId == localId,
      );
      _replaceReceipt(
        uploaded.copyWith(status: ExpenseReceiptStatus.analyzing),
      );
      final ocr = await _apiClient.runOcr(
        File(path),
        purpose: purpose ?? current.documentType,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final analyzed = _receipts.firstWhere(
        (receipt) => receipt.localId == localId,
      );
      var ready = analyzed.withOcr(ocr);
      if (current.parentReceiptId != null) {
        ready = ready.copyWith(
          documentType: 'bank-statement',
          parentReceiptId: current.parentReceiptId,
        );
      }
      _replaceReceipt(ready);
      _applyBankStatementIfNeeded(ready);
      await _maybeGenerateSummary();
    } catch (e) {
      final failed = _receipts.firstWhere(
        (receipt) => receipt.localId == localId,
        orElse: () => current,
      );
      _replaceReceipt(
        failed.copyWith(
          status: ExpenseReceiptStatus.error,
          error: e.toString(),
        ),
      );
    }
  }

  void _applyBankStatementIfNeeded(ExpenseReceiptDraft bankStatement) {
    final parentId = bankStatement.parentReceiptId;
    if (parentId == null || !bankStatement.isBankStatement) return;
    final exactAmount = bankStatement.amountInNok ?? bankStatement.amount;
    if (exactAmount == null || exactAmount <= 0) return;
    setState(() {
      _receipts = _receipts.map((receipt) {
        if (receipt.localId != parentId) return receipt;
        return receipt.copyWith(
          amountInNok: exactAmount,
          hasLinkedBankStatement: true,
        );
      }).toList();
    });
  }

  Future<void> _maybeGenerateSummary({bool force = false}) async {
    final assignment = _assignment;
    if (assignment == null ||
        !assignment.isComplete ||
        !_hasReadyExpenseReceipts) {
      return;
    }
    final snapshot = ExpensePayloadBuilder.summarySnapshot(
      assignment: assignment,
      receipts: _receipts,
    );
    if (!force && snapshot == _lastSummarySnapshot) return;

    setState(() {
      _isSummaryLoading = true;
      _lastSummarySnapshot = snapshot;
    });
    try {
      final summary = await _apiClient.summarize(
        assignment: assignment,
        receipts: _receipts,
      );
      if (mounted && summary.trim().isNotEmpty) {
        setState(() => _descriptionController.text = summary.trim());
      }
    } catch (e) {
      if (mounted) setState(() => _flowError = 'Summary failed: $e');
    } finally {
      if (mounted) setState(() => _isSummaryLoading = false);
    }
  }

  bool _canSaveDraft(UserModel? user) {
    return user != null &&
        _hasAssignment &&
        !_hasBusyReceipts &&
        !_isSavingDraft &&
        !_isSubmitting &&
        (user.bankAccount ?? '').trim().isNotEmpty;
  }

  bool _canSubmit(UserModel? user, ExpenseProfileReadiness profileReadiness) {
    return user != null &&
        profileReadiness.isReady &&
        _hasAssignment &&
        !_hasBusyReceipts &&
        _hasReadyExpenseReceipts &&
        _descriptionController.text.trim().isNotEmpty &&
        !_isSavingDraft &&
        !_isSubmitting;
  }

  Future<void> _saveDraft(UserModel? user) async {
    final assignment = _assignment;
    if (assignment == null || user == null) return;
    setState(() {
      _isSavingDraft = true;
      _flowError = null;
    });
    try {
      final payload = ExpensePayloadBuilder.buildBasePayload(
        expenseId: _draftExpenseId,
        assignment: assignment,
        bankAccount: user.bankAccount ?? '',
        description: _descriptionController.text.trim(),
        receipts: _receipts,
        eventName: _eventController.text.trim(),
      );
      final result = await _apiClient.saveDraft(payload);
      if (!result.success || result.draftId == null) {
        throw const ExpenseApiException(
          'Draft save did not return a draft ID.',
        );
      }
      setState(() => _draftExpenseId = result.draftId);
      ref.read(expensesStateProvider.notifier).refresh();
      _showSnack('Draft saved');
    } catch (e) {
      setState(() => _flowError = 'Failed to save draft: $e');
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _submit(UserModel? user) async {
    final assignment = _assignment;
    if (assignment == null || user == null) return;
    setState(() {
      _isSubmitting = true;
      _flowError = null;
    });
    try {
      final payload = ExpensePayloadBuilder.buildBasePayload(
        expenseId: _draftExpenseId,
        assignment: assignment,
        bankAccount: user.bankAccount ?? '',
        description: _descriptionController.text.trim(),
        receipts: _receipts,
        eventName: _eventController.text.trim(),
      );
      final result = await _apiClient.submit(payload);
      await ref.read(expensesStateProvider.notifier).refresh();
      if (!mounted) return;
      _showSnack('Expense submitted');
      final expense = result.expense;
      if (expense != null) {
        Navigator.of(context).pop(expense);
      } else {
        context.go('/explore/expenses');
      }
    } catch (e) {
      if (mounted) setState(() => _flowError = 'Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showProfileCompletionSheet(UserModel? user) async {
    if (user == null) return;
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone ?? '');
    final bankController = TextEditingController(
      text: formatNorwegianBankAccount(user.bankAccount ?? ''),
    );
    final addressController = TextEditingController(text: user.address ?? '');
    final zipController = TextEditingController(text: user.zipCode ?? '');
    final cityController = TextEditingController(text: user.city ?? '');

    await showBisoSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final palette = BisoPalette.of(sheetContext);
        // A bottom sheet route is not a descendant of this page's BisoPage,
        // so there are no page insets to clear here (matching the fallback
        // in sell_product_screen's _scrollPaddingFor).
        const scrollPadding = EdgeInsets.all(20);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom:
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                MediaQuery.paddingOf(sheetContext).bottom +
                20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Complete profile',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(color: palette.ink),
                ),
                const SizedBox(height: 16),
                BisoFormGroup(
                  children: [
                    BisoFormRow(
                      label: 'Name',
                      child: TextField(
                        controller: nameController,
                        scrollPadding: scrollPadding,
                        decoration: bisoInputDecoration(sheetContext),
                      ),
                    ),
                    BisoFormRow(
                      label: 'Phone',
                      child: TextField(
                        controller: phoneController,
                        scrollPadding: scrollPadding,
                        decoration: bisoInputDecoration(sheetContext),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    BisoFormRow(
                      label: 'Bank account',
                      child: TextField(
                        controller: bankController,
                        scrollPadding: scrollPadding,
                        decoration: bisoInputDecoration(sheetContext),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    BisoFormRow(
                      label: 'Address',
                      child: TextField(
                        controller: addressController,
                        scrollPadding: scrollPadding,
                        decoration: bisoInputDecoration(sheetContext),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: BisoFormRow(
                            label: 'Zip',
                            child: TextField(
                              controller: zipController,
                              scrollPadding: scrollPadding,
                              decoration: bisoInputDecoration(sheetContext),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: BisoFormRow(
                            label: 'City',
                            child: TextField(
                              controller: cityController,
                              scrollPadding: scrollPadding,
                              decoration: bisoInputDecoration(sheetContext),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    final bank = normalizeNorwegianBankAccount(
                      bankController.text,
                    );
                    final bankError = validateNorwegianBankAccount(bank);
                    if (bankError != null) {
                      ScaffoldMessenger.of(
                        sheetContext,
                      ).showSnackBar(SnackBar(content: Text(bankError)));
                      return;
                    }
                    await ref
                        .read(authServiceProvider)
                        .updateUserProfile(
                          name: nameController.text.trim(),
                          phone: phoneController.text.trim(),
                          bankAccount: bank,
                          address: addressController.text.trim(),
                          zipCode: zipController.text.trim(),
                          city: cityController.text.trim(),
                          campusId: _assignment?.campusId ?? user.campusId,
                        );
                    await ref.read(authStateProvider.notifier).refreshProfile();
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Save profile'),
                ),
              ],
            ),
          ),
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    bankController.dispose();
    addressController.dispose();
    zipController.dispose();
    cityController.dispose();
  }

  Future<bool> _confirmLeaveIfNeeded() async {
    if (_receipts.isEmpty && _draftExpenseId == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave reimbursement?'),
            content: const Text(
              'Save your draft before leaving if you want to continue later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _replaceReceipt(ExpenseReceiptDraft updated) {
    if (!mounted) return;
    setState(() {
      _receipts = _receipts
          .map(
            (receipt) => receipt.localId == updated.localId ? updated : receipt,
          )
          .toList();
    });
  }

  void _updateReceipt(ExpenseReceiptDraft updated) {
    _replaceReceipt(updated.copyWith(status: ExpenseReceiptStatus.ready));
    _maybeGenerateSummary(force: true);
  }

  void _removeReceipt(String localId) {
    setState(() {
      _receipts = _receipts
          .where(
            (receipt) =>
                receipt.localId != localId &&
                receipt.parentReceiptId != localId,
          )
          .toList();
      _selectedReceiptId = _receipts.isEmpty ? null : _receipts.first.localId;
    });
    _maybeGenerateSummary(force: true);
  }

  ExpenseReceiptDraft? _selectedReceipt() {
    if (_receipts.isEmpty) return null;
    if (_selectedReceiptId == null) return _receipts.first;
    for (final receipt in _receipts) {
      if (receipt.localId == _selectedReceiptId) return receipt;
    }
    return _receipts.first;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _newLocalId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
  }

  bool _isSupportedOcrMime(String mimeType) {
    return const {
      'image/jpeg',
      'image/png',
      'application/pdf',
    }.contains(mimeType);
  }

  String _normalizeAttachmentType(String type) {
    if (type.contains('/')) return type;
    switch (type.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return type.isEmpty ? 'application/octet-stream' : type;
    }
  }

  String? _extractAppwriteFileId(String value) {
    if (value.isEmpty) return null;
    if (!value.startsWith('http')) return value;
    final match = RegExp(r'/files/([^/]+)/').firstMatch(value);
    return match?.group(1);
  }
}

/// The campus/department picker sheet: a `DraggableScrollableSheet` (the
/// same drag-to-expand shape as `_EventDetailSheet` in events_screen.dart)
/// whose body is a lazy `SliverBisoListGroup` bound to the sheet's own
/// `scrollController`, rather than a fixed-height `BisoListGroup` — a
/// `showModalBottomSheet` without `isScrollControlled` caps at 9/16 of the
/// screen height, and a real department list can run well past what fits
/// there. The checkmark marks [selectedId]; tapping a row hands the picked
/// id/name back to the caller, which pops the sheet itself.
class _AssignmentPickerSheet extends StatelessWidget {
  const _AssignmentPickerSheet({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.scrollController,
    required this.onSelected,
  });

  final String title;
  final List<Map<String, String>> options;
  final String? selectedId;
  final ScrollController scrollController;
  final void Function(String id, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.headlineSmall?.copyWith(color: palette.ink),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverBisoListGroup(
                    itemCount: options.length,
                    margin: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option['id'] == selectedId;
                      return BisoListRow(
                        title: option['name']!,
                        trailing: selected
                            ? Icon(
                                CupertinoIcons.checkmark,
                                color: palette.link,
                              )
                            : null,
                        onTap: () => onSelected(option['id']!, option['name']!),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One receipt tile: a 44pt rounded thumbnail (or a coral document tile when
/// there is nothing to preview) as leading, the vendor or file name as
/// title, the amount or current OCR status as subtitle, and retry/remove as
/// trailing. [indent] draws the small connector used for a bank statement
/// nested under the receipt it verifies, mirroring the tree the original
/// screen drew with a `Card` and manual connector lines.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receipt,
    required this.isSelected,
    required this.onTap,
    required this.onRemove,
    this.onRetry,
    this.indent = false,
  });

  final ExpenseReceiptDraft receipt;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final color = _statusColor(receipt.status, palette);

    final row = Container(
      color: isSelected ? palette.link.withValues(alpha: 0.08) : null,
      child: BisoListRow(
        leading: _leading(receipt, palette),
        title: receipt.vendor?.isNotEmpty == true
            ? receipt.vendor!
            : receipt.fileName,
        subtitle: _statusLabel(receipt),
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (receipt.status == ExpenseReceiptStatus.error && onRetry != null)
              IconButton(
                tooltip: 'Retry',
                onPressed: onRetry,
                icon: const Icon(CupertinoIcons.arrow_clockwise),
              ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(CupertinoIcons.trash),
            ),
          ],
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (receipt.isBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: LinearProgressIndicator(color: color),
          ),
        if (receipt.hasEstimatedNok)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Estimated NOK amount. Add bank statement for exact verification.',
              style: text.bodySmall?.copyWith(color: palette.warning),
            ),
          ),
        if (receipt.hasLinkedBankStatement)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Bank statement attached',
              style: text.bodySmall?.copyWith(color: palette.success),
            ),
          ),
      ],
    );

    if (!indent) return content;

    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              children: [
                Container(width: 2, height: 20, color: palette.hairline),
                Container(width: 10, height: 2, color: palette.hairline),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: content),
        ],
      ),
    );
  }

  static Widget _leading(ExpenseReceiptDraft receipt, BisoPalette palette) {
    const size = 44.0;
    final isPdf = receipt.mimeType == 'application/pdf';
    final path = receipt.localPath;
    if (!isPdf && path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover),
      );
    }
    final url = receipt.viewUrl;
    if (!isPdf && url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => BisoIconTile(
            icon: _fileIcon(receipt),
            accent: BisoAccent.coral,
            size: size,
          ),
        ),
      );
    }
    return BisoIconTile(
      icon: _fileIcon(receipt),
      accent: BisoAccent.coral,
      size: size,
    );
  }

  static IconData _fileIcon(ExpenseReceiptDraft receipt) {
    if (receipt.isBankStatement) return CupertinoIcons.creditcard;
    return CupertinoIcons.doc_text;
  }

  static String _statusLabel(ExpenseReceiptDraft receipt) {
    if (receipt.error != null) return receipt.error!;
    switch (receipt.status) {
      case ExpenseReceiptStatus.uploading:
        return 'Uploading';
      case ExpenseReceiptStatus.processing:
        return 'Processing';
      case ExpenseReceiptStatus.analyzing:
        return 'Analyzing receipt';
      case ExpenseReceiptStatus.ready:
        return receipt.isBankStatement
            ? 'Bank statement'
            : 'NOK ${receipt.effectiveAmount.toStringAsFixed(2)}';
      case ExpenseReceiptStatus.error:
        return 'Could not process receipt';
      case ExpenseReceiptStatus.editing:
        return 'Editing';
    }
  }

  static Color _statusColor(ExpenseReceiptStatus status, BisoPalette palette) {
    switch (status) {
      case ExpenseReceiptStatus.ready:
        return palette.success;
      case ExpenseReceiptStatus.error:
        return palette.error;
      case ExpenseReceiptStatus.analyzing:
      case ExpenseReceiptStatus.processing:
      case ExpenseReceiptStatus.uploading:
      case ExpenseReceiptStatus.editing:
        return palette.link;
    }
  }
}

class _ReceiptDetailEditor extends StatefulWidget {
  final ExpenseReceiptDraft receipt;
  final EdgeInsets scrollPadding;
  final ValueChanged<ExpenseReceiptDraft> onChanged;
  final VoidCallback? onAddBankStatement;

  const _ReceiptDetailEditor({
    required this.receipt,
    required this.scrollPadding,
    required this.onChanged,
    this.onAddBankStatement,
  });

  @override
  State<_ReceiptDetailEditor> createState() => _ReceiptDetailEditorState();
}

class _ReceiptDetailEditorState extends State<_ReceiptDetailEditor> {
  late TextEditingController _vendorController;
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant _ReceiptDetailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.localId != widget.receipt.localId) {
      _disposeControllers();
      _initControllers();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _initControllers() {
    _vendorController = TextEditingController(
      text: widget.receipt.vendor ?? '',
    );
    _amountController = TextEditingController(
      text: widget.receipt.effectiveAmount == 0
          ? ''
          : widget.receipt.effectiveAmount.toStringAsFixed(2),
    );
    _descriptionController = TextEditingController(
      text: widget.receipt.description,
    );
    _date = widget.receipt.date;
  }

  void _disposeControllers() {
    _vendorController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    receipt.isBankStatement
                        ? 'Bank statement'
                        : 'Receipt detail',
                    style: text.titleLarge?.copyWith(color: palette.ink),
                  ),
                ),
                Chip(
                  avatar: const Icon(CupertinoIcons.sparkles, size: 16),
                  label: Text(
                    receipt.isBusy ? 'Analyzing receipt...' : 'AI Extracted',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPreview(receipt, palette),
            const SizedBox(height: 16),
            if (receipt.hasEstimatedNok)
              _WarningBanner(
                icon: CupertinoIcons.arrow_2_squarepath,
                color: palette.warning,
                title: 'Estimated exchange rate',
                message:
                    '${receipt.originalForeignAmount ?? receipt.currency} was converted using historical rates.',
                actionLabel: 'Add bank statement',
                onAction: widget.onAddBankStatement,
              ),
            if (receipt.hasLinkedBankStatement)
              _InfoBanner(
                icon: CupertinoIcons.checkmark_seal_fill,
                color: palette.success,
                title: 'Verified NOK amount',
                message: 'A bank statement is linked to this receipt.',
              ),
            BisoFormRow(
              label: 'Vendor',
              child: TextField(
                controller: _vendorController,
                scrollPadding: widget.scrollPadding,
                decoration: bisoInputDecoration(
                  context,
                  prefixIcon: const Icon(CupertinoIcons.bag),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: BisoFormRow(
                    label: 'Amount in NOK',
                    child: TextField(
                      controller: _amountController,
                      scrollPadding: widget.scrollPadding,
                      decoration: bisoInputDecoration(
                        context,
                        prefixIcon: const Icon(CupertinoIcons.money_dollar),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BisoFormRow(
                    label: 'Date',
                    child: InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date ?? now,
                          firstDate: now.subtract(const Duration(days: 365 * 5)),
                          lastDate: now.add(const Duration(days: 1)),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                          _emit();
                        }
                      },
                      child: InputDecorator(
                        decoration: bisoInputDecoration(
                          context,
                          prefixIcon: const Icon(CupertinoIcons.calendar),
                        ),
                        child: Text(
                          _date == null
                              ? 'Select'
                              : DateFormat.yMMMd().format(_date!),
                          style: text.bodyMedium?.copyWith(color: palette.ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            BisoFormRow(
              label: 'Description',
              child: TextField(
                controller: _descriptionController,
                scrollPadding: widget.scrollPadding,
                decoration: bisoInputDecoration(
                  context,
                  prefixIcon: const Icon(CupertinoIcons.text_alignleft),
                ),
                maxLines: 2,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ExpenseReceiptDraft receipt, BisoPalette palette) {
    if (receipt.mimeType == 'application/pdf') {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.doc_fill, size: 42, color: palette.muted),
            const SizedBox(height: 8),
            Text('No preview available', style: TextStyle(color: palette.muted)),
          ],
        ),
      );
    }
    final path = receipt.localPath;
    if (path != null) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(path), fit: BoxFit.cover),
        ),
      );
    }
    final viewUrl = receipt.viewUrl;
    if (viewUrl != null) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(viewUrl, fit: BoxFit.cover),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _emit() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    widget.onChanged(
      widget.receipt.copyWith(
        vendor: _vendorController.text.trim(),
        amountInNok: amount,
        date: _date,
        description: _descriptionController.text.trim(),
        status: ExpenseReceiptStatus.ready,
      ),
    );
  }
}

class _ReportReceiptRow extends StatelessWidget {
  const _ReportReceiptRow({required this.receipt});

  final ExpenseReceiptDraft receipt;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return _AmountRow(
      title: receipt.description.isNotEmpty
          ? receipt.description
          : receipt.fileName,
      amount: 'NOK ${receipt.effectiveAmount.toStringAsFixed(2)}',
      titleStyle: text.bodyMedium?.copyWith(color: palette.ink),
      amountStyle: text.bodyMedium?.copyWith(color: palette.muted),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _WarningBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(color: color)),
                // The title may keep the accent color, but the body text
                // needs real contrast against the 10%-tint background —
                // ink, not the (often lighter) accent color.
                Text(
                  message,
                  style: text.bodyMedium?.copyWith(color: palette.ink),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return _WarningBanner(
      icon: icon,
      color: color,
      title: title,
      message: message,
    );
  }
}

/// One "label — amount" row, sized so the amount is never scaled down or
/// silently clipped at any text scale (R11). Mirrors `_AmountRow` in
/// `checkout_screen.dart` and `expenses_screen.dart` — see either's doc
/// comment for the full layout rationale: side by side when the label can
/// keep a real share of the row, otherwise stacked; either way the amount
/// renders on one line if it fits, or, as a last resort, wraps only on the
/// single space between the currency code and the number.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.title,
    this.subtitle,
    required this.amount,
    this.titleStyle,
    this.subtitleStyle,
    this.amountStyle,
    this.allowWrapFallback = true,
  });

  final String title;
  final String? subtitle;
  final String amount;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? amountStyle;

  /// Tier 3 (split the amount on its single space, between the currency
  /// code and the number) assumes [amount] is exactly that pair — right
  /// for a money amount, wrong for a value with its own internal spaces
  /// (a formatted Norwegian bank account, "8601 11 17947": splitting it
  /// would fragment the account number itself, not just separate a label
  /// from a value). Set false for such values: the amount then always
  /// stays one `maxLines: 1, softWrap: false` `Text`, beside the label or
  /// stacked below it, never split into pieces.
  final bool allowWrapFallback;

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
                  !allowWrapFallback ||
                  sideBySide ||
                  !maxWidth.isFinite ||
                  painter.width <= maxWidth;

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

              final label = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: sideBySide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                ],
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
