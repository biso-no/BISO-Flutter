import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/norwegian_bank_account.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/expense_v2_models.dart';
import '../../../data/services/expense_api_client.dart';
import '../../../data/services/expense_service_v2.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/expense/expense_provider.dart';

class CreateExpenseScreen extends ConsumerStatefulWidget {
  final String? eventId;
  final String? eventName;
  final ExpenseModel? draftExpense;

  const CreateExpenseScreen({
    super.key,
    this.eventId,
    this.eventName,
    this.draftExpense,
  });

  @override
  ConsumerState<CreateExpenseScreen> createState() =>
      _CreateExpenseScreenState();
}

class _CreateExpenseScreenState extends ConsumerState<CreateExpenseScreen> {
  final ExpenseServiceV2 _expenseService = ExpenseServiceV2();
  final ExpenseApiClient _apiClient = ExpenseApiClient();
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
  String? _flowError;
  int _mobileTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _draftExpenseId = widget.draftExpense?.id;
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
    final user = ref.watch(currentUserProvider);
    final profileReadiness = ExpenseProfileReadiness.fromUser(user);

    if (_isLoadingLookups) {
      return Scaffold(
        appBar: AppBar(title: const Text('New reimbursement')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _draftExpenseId == null
                ? 'New reimbursement'
                : 'Draft reimbursement',
          ),
          leading: IconButton(
            onPressed: () async {
              final shouldLeave = await _confirmLeaveIfNeeded();
              if (shouldLeave && context.mounted) {
                NavigationUtils.safeGoBack(
                  context,
                  fallbackRoute: '/explore/expenses',
                );
              }
            },
            icon: const Icon(Icons.close),
          ),
          actions: [
            TextButton.icon(
              onPressed: _canSaveDraft(user) ? () => _saveDraft(user!) : null,
              icon: _isSavingDraft
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save draft'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _hasAssignment
            ? _buildSplitFlow(user, profileReadiness)
            : _buildAssignmentGate(user),
      ),
    );
  }

  Widget _buildAssignmentGate(dynamic user) {
    return Container(
      width: double.infinity,
      color: AppColors.gray50,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.subtleBlue,
                  child: Icon(Icons.apartment, color: AppColors.defaultBlue),
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose cost allocation',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Select the campus and department responsible for this reimbursement before uploading receipts.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _assignment?.campusId.isNotEmpty == true
                      ? _assignment!.campusId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Campus',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  items: _campuses
                      .map(
                        (campus) => DropdownMenuItem(
                          value: campus['id'],
                          child: Text(campus['name']!),
                        ),
                      )
                      .toList(),
                  onChanged: (campusId) async {
                    if (campusId == null) return;
                    final campus = _campuses.firstWhere(
                      (item) => item['id'] == campusId,
                    );
                    setState(() {
                      _assignment = ExpenseAssignment(
                        campusId: campus['id']!,
                        campusName: campus['name']!,
                        departmentId: '',
                        departmentName: '',
                      );
                      _departments = [];
                    });
                    await _loadDepartments(campusId);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _assignment?.departmentId.isNotEmpty == true
                      ? _assignment!.departmentId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    prefixIcon: Icon(Icons.business),
                  ),
                  items: _departments
                      .map(
                        (department) => DropdownMenuItem(
                          value: department['id'],
                          child: Text(department['name']!),
                        ),
                      )
                      .toList(),
                  onChanged: _assignment == null
                      ? null
                      : (departmentId) {
                          if (departmentId == null) return;
                          final department = _departments.firstWhere(
                            (item) => item['id'] == departmentId,
                          );
                          final current = _assignment!;
                          setState(() {
                            _assignment = ExpenseAssignment(
                              campusId: current.campusId,
                              campusName: current.campusName,
                              departmentId: department['id']!,
                              departmentName: department['name']!,
                            );
                          });
                          _maybeGenerateSummary();
                        },
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _hasAssignment ? () => setState(() {}) : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue'),
                ),
                if (_flowError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _flowError!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitFlow(
    dynamic user,
    ExpenseProfileReadiness profileReadiness,
  ) {
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    if (isWide) {
      return Row(
        children: [
          SizedBox(width: 390, child: _buildReceiptWallet()),
          const VerticalDivider(width: 1),
          Expanded(child: _buildReportPane(user, profileReadiness)),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Receipts'),
                icon: Icon(Icons.receipt_long),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Report'),
                icon: Icon(Icons.description_outlined),
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
  }

  Widget _buildReceiptWallet() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Receipt wallet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload images or PDFs. OCR runs after upload.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickCameraReceipt(),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImageReceipt(),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Photo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pickDocumentReceipt(),
                icon: const Icon(Icons.attach_file),
                label: const Text('PDF receipt'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _receipts.isEmpty
              ? _buildEmptyWallet()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildGroupedReceiptTiles(),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildGroupedReceiptTiles() {
    final topLevel =
        _receipts.where((r) => r.parentReceiptId == null).toList();
    final widgets = <Widget>[];
    for (final receipt in topLevel) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
      widgets.add(
        _ReceiptTile(
          receipt: receipt,
          isSelected: receipt.localId == _selectedReceiptId,
          onTap: () => setState(() {
            _selectedReceiptId = receipt.localId;
            _mobileTabIndex = 1;
          }),
          onRemove: () => _removeReceipt(receipt.localId),
          onRetry: receipt.localPath != null
              ? () => _processReceipt(receipt.localId)
              : null,
        ),
      );
      final children = _receipts
          .where((r) => r.parentReceiptId == receipt.localId)
          .toList();
      for (final child in children) {
        widgets.add(const SizedBox(height: 6));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 2,
                      height: 20,
                      color: AppColors.outlineVariant,
                    ),
                    Container(
                      width: 10,
                      height: 2,
                      color: AppColors.outlineVariant,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ReceiptTile(
                    receipt: child,
                    isSelected: child.localId == _selectedReceiptId,
                    onTap: () => setState(() {
                      _selectedReceiptId = child.localId;
                      _mobileTabIndex = 1;
                    }),
                    onRemove: () => _removeReceipt(child.localId),
                    onRetry: child.localPath != null
                        ? () => _processReceipt(child.localId)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildEmptyWallet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No receipts yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Receipts are required before this can be submitted.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportPane(
    dynamic user,
    ExpenseProfileReadiness profileReadiness,
  ) {
    final selected = _selectedReceipt();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!profileReadiness.isReady)
                _WarningBanner(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.orange9,
                  title: 'Complete your profile',
                  message:
                      'Missing: ${profileReadiness.missingFields.join(', ')}',
                  actionLabel: 'Update',
                  onAction: () => _showProfileCompletionSheet(user),
                ),
              if (_hasBusyReceipts)
                const _InfoBanner(
                  icon: Icons.hourglass_top,
                  color: AppColors.accentBlue,
                  title: 'Processing receipts',
                  message:
                      'Drafts and submissions wait until upload and OCR finish.',
                ),
              if (_flowError != null)
                _WarningBanner(
                  icon: Icons.error_outline,
                  color: AppColors.error,
                  title: 'Expense error',
                  message: _flowError!,
                  actionLabel: 'Dismiss',
                  onAction: () => setState(() => _flowError = null),
                ),
              _buildReportDocument(user),
              const SizedBox(height: 20),
              if (selected != null)
                _ReceiptDetailEditor(
                  receipt: selected,
                  onChanged: _updateReceipt,
                  onAddBankStatement:
                      selected.isForeignCurrency && !selected.isBankStatement
                      ? () => _pickBankStatement(selected.localId)
                      : null,
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canSaveDraft(user)
                        ? () => _saveDraft(user!)
                        : null,
                    icon: _isSavingDraft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _draftExpenseId == null ? 'Save draft' : 'Update draft',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _canSubmit(user, profileReadiness)
                        ? () => _submit(user!)
                        : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportDocument(dynamic user) {
    final assignment = _assignment!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reimbursement report',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _draftExpenseId == null
                          ? DateFormat.yMMMd().format(DateTime.now())
                          : 'Draft $_draftExpenseId',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'NOK ${_totalAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.defaultBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ReportInfoChip(
                icon: Icons.person_outline,
                label: user?.name ?? 'Unknown user',
                value: user?.email ?? '',
              ),
              _ReportInfoChip(
                icon: Icons.account_balance,
                label: 'Bank account',
                value: user?.bankAccount == null
                    ? 'Missing'
                    : formatNorwegianBankAccount(user!.bankAccount!),
              ),
              _ReportInfoChip(
                icon: Icons.apartment,
                label: assignment.campusName,
                value: assignment.departmentName,
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _isSummaryLoading
                  ? 'Generating summary...'
                  : 'Accounting summary',
              hintText: 'What was this expense for?',
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
                      icon: const Icon(Icons.auto_awesome),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Receipts',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_readyReceipts.isEmpty)
            const Text('No ready receipts yet.')
          else
            ..._readyReceipts.map(
              (receipt) => _ReportReceiptRow(receipt: receipt),
            ),
          const Divider(height: 28),
          Row(
            children: [
              Text('${_readyReceipts.length} file(s)'),
              const Spacer(),
              Text(
                'Total NOK ${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickCameraReceipt() async {
    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null) await _addFile(File(image.path));
  }

  Future<void> _pickImageReceipt() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) await _addFile(File(image.path));
  }

  Future<void> _pickDocumentReceipt() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
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
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    if (result == null || result.files.first.path == null) return;
    await _addFile(
      File(result.files.first.path!),
      purpose: 'bank-statement',
      parentReceiptId: parentReceiptId,
    );
  }

  Future<void> _addFile(
    File file, {
    String purpose = 'receipt',
    String? parentReceiptId,
  }) async {
    final mimeType = detectExpenseMimeType(file.path);
    if (!_isSupportedOcrMime(mimeType)) {
      setState(() {
        _flowError = 'Unsupported file type for OCR: $mimeType';
      });
      return;
    }
    if (await file.length() > 10 * 1024 * 1024) {
      setState(() {
        _flowError = 'Files must be 10 MB or smaller.';
      });
      return;
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

  bool _canSaveDraft(dynamic user) {
    return user != null &&
        _hasAssignment &&
        !_hasBusyReceipts &&
        !_isSavingDraft &&
        !_isSubmitting &&
        (user.bankAccount ?? '').trim().isNotEmpty;
  }

  bool _canSubmit(dynamic user, ExpenseProfileReadiness profileReadiness) {
    return user != null &&
        profileReadiness.isReady &&
        _hasAssignment &&
        !_hasBusyReceipts &&
        _hasReadyExpenseReceipts &&
        _descriptionController.text.trim().isNotEmpty &&
        !_isSavingDraft &&
        !_isSubmitting;
  }

  Future<void> _saveDraft(dynamic user) async {
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

  Future<void> _submit(dynamic user) async {
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

  Future<void> _showProfileCompletionSheet(dynamic user) async {
    if (user == null) return;
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone ?? '');
    final bankController = TextEditingController(
      text: formatNorwegianBankAccount(user.bankAccount ?? ''),
    );
    final addressController = TextEditingController(text: user.address ?? '');
    final zipController = TextEditingController(text: user.zipCode ?? '');
    final cityController = TextEditingController(text: user.city ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Complete profile',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankController,
                  decoration: const InputDecoration(labelText: 'Bank account'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: zipController,
                        decoration: const InputDecoration(labelText: 'Zip'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: cityController,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () async {
                    final bank = normalizeNorwegianBankAccount(
                      bankController.text,
                    );
                    final bankError = validateNorwegianBankAccount(bank);
                    if (bankError != null) {
                      ScaffoldMessenger.of(
                        context,
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
                    if (context.mounted) Navigator.of(context).pop();
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
      'image/webp',
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

class _ReceiptTile extends StatelessWidget {
  final ExpenseReceiptDraft receipt;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;

  const _ReceiptTile({
    required this.receipt,
    required this.isSelected,
    required this.onTap,
    required this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(receipt.status);
    return Card(
      color: isSelected ? AppColors.subtleBlue : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildReceiptLeading(receipt, color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          receipt.vendor?.isNotEmpty == true
                              ? receipt.vendor!
                              : receipt.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _statusLabel(receipt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (receipt.status == ExpenseReceiptStatus.error &&
                      onRetry != null)
                    IconButton(
                      tooltip: 'Retry',
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (receipt.isBusy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(color: color),
              ],
              if (receipt.hasEstimatedNok) ...[
                const SizedBox(height: 8),
                const Text(
                  'Estimated NOK amount. Add bank statement for exact verification.',
                  style: TextStyle(color: AppColors.orange9, fontSize: 12),
                ),
              ],
              if (receipt.hasLinkedBankStatement) ...[
                const SizedBox(height: 8),
                const Text(
                  'Bank statement attached',
                  style: TextStyle(color: AppColors.success, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildReceiptLeading(ExpenseReceiptDraft receipt, Color color) {
    final isPdf = receipt.mimeType == 'application/pdf';
    final path = receipt.localPath;
    if (!isPdf && path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(
          File(path),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }
    final url = receipt.viewUrl;
    if (!isPdf && url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(_fileIcon(receipt), color: color, size: 20),
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(_fileIcon(receipt), color: color, size: 20),
    );
  }

  static IconData _fileIcon(ExpenseReceiptDraft receipt) {
    if (receipt.mimeType == 'application/pdf') return Icons.picture_as_pdf;
    if (receipt.isBankStatement) return Icons.account_balance_wallet_outlined;
    return Icons.image_outlined;
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

  static Color _statusColor(ExpenseReceiptStatus status) {
    switch (status) {
      case ExpenseReceiptStatus.ready:
        return AppColors.success;
      case ExpenseReceiptStatus.error:
        return AppColors.error;
      case ExpenseReceiptStatus.analyzing:
      case ExpenseReceiptStatus.processing:
      case ExpenseReceiptStatus.uploading:
      case ExpenseReceiptStatus.editing:
        return AppColors.accentBlue;
    }
  }
}

class _ReceiptDetailEditor extends StatefulWidget {
  final ExpenseReceiptDraft receipt;
  final ValueChanged<ExpenseReceiptDraft> onChanged;
  final VoidCallback? onAddBankStatement;

  const _ReceiptDetailEditor({
    required this.receipt,
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
    return Card(
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(
                    receipt.isBusy ? 'Analyzing receipt...' : 'AI Extracted',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPreview(receipt),
            const SizedBox(height: 16),
            if (receipt.hasEstimatedNok)
              _WarningBanner(
                icon: Icons.currency_exchange,
                color: AppColors.orange9,
                title: 'Estimated exchange rate',
                message:
                    '${receipt.originalForeignAmount ?? receipt.currency} was converted using historical rates.',
                actionLabel: 'Add bank statement',
                onAction: widget.onAddBankStatement,
              ),
            if (receipt.hasLinkedBankStatement)
              const _InfoBanner(
                icon: Icons.verified_outlined,
                color: AppColors.success,
                title: 'Verified NOK amount',
                message: 'A bank statement is linked to this receipt.',
              ),
            TextField(
              controller: _vendorController,
              decoration: const InputDecoration(
                labelText: 'Vendor',
                prefixIcon: Icon(Icons.storefront),
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount in NOK',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _date == null
                            ? 'Select'
                            : DateFormat.yMMMd().format(_date!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
              onChanged: (_) => _emit(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ExpenseReceiptDraft receipt) {
    if (receipt.mimeType == 'application/pdf') {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.gray100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf, size: 42),
            SizedBox(height: 8),
            Text('No preview available'),
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

class _ReportInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReportInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.defaultBlue),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (value.isNotEmpty)
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _ReportReceiptRow extends StatelessWidget {
  final ExpenseReceiptDraft receipt;

  const _ReportReceiptRow({required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            receipt.isBankStatement
                ? Icons.account_balance_wallet_outlined
                : Icons.receipt_long,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              receipt.description.isNotEmpty
                  ? receipt.description
                  : receipt.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('NOK ${receipt.effectiveAmount.toStringAsFixed(2)}'),
        ],
      ),
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
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(message),
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
