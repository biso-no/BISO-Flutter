import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:printing/printing.dart';
import 'dart:ui' as ui;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/norwegian_bank_account.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../data/services/expense_service_v2.dart';
import '../../../core/utils/favorites_storage.dart';

class CreateExpenseScreen extends ConsumerStatefulWidget {
  final String? eventId;
  final String? eventName;

  const CreateExpenseScreen({super.key, this.eventId, this.eventName});

  @override
  ConsumerState<CreateExpenseScreen> createState() =>
      _CreateExpenseScreenState();
}

class _CreateExpenseScreenState extends ConsumerState<CreateExpenseScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form data
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _overallDescriptionController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _accountHolderController = TextEditingController();

  String? _selectedDepartmentId;
  String _selectedDepartmentName = '';
  final bool _isPrepayment = false;
  final DateTime _expenseDate = DateTime.now();
  final List<File> _attachedFiles = [];
  final List<_ReceiptDraft> _receiptDrafts = [];
  bool _useAi = false;
  bool _isAnalyzing = false;
  String? _selectedCampusId;
  String? _selectedCampusName;
  List<Map<String, String>> _campuses = [];
  List<Map<String, String>> _departments = [];
  final ExpenseServiceV2 _expenseService = ExpenseServiceV2();
  List<String> _favoriteDepartmentIds = [];

  // categories removed per new flow

  @override
  void initState() {
    super.initState();
    // No categories in the new flow
    // Prefill from profile if available
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = ref.read(currentUserProvider);
      // Load campuses (id + name)
      try {
        final rawCampuses = await _expenseService.listCampuses();
        _campuses = rawCampuses
            .map<Map<String, String>>((c) => {
                  'id': (c['\$id'] ?? c['id'] ?? '').toString(),
                  'name': (c['name'] ?? '').toString(),
                })
            .where((c) => c['id']!.isNotEmpty && c['name']!.isNotEmpty)
            .toList();
      } catch (_) {}
      _favoriteDepartmentIds =
          await FavoritesStorage.getFavoriteDepartmentIds();
      if (user != null) {
        _accountHolderController.text = user.name;
        _bankAccountController.text = formatNorwegianBankAccount(
          user.bankAccount ?? '',
        );
        _selectedCampusId = user.campusId;
        _selectedCampusName = _campuses.firstWhere(
          (c) => c['id'] == _selectedCampusId,
          orElse: () => {'id': '', 'name': ''},
        )['name'];
        await _loadDepartments();
      }
      _maybePromptForMissingProfile();
    });
  }

  Widget _buildDepartmentTile(Map<String, String> dept, bool isSelected) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? AppColors.subtleBlue : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedDepartmentId = dept['id'];
            _selectedDepartmentName = dept['name']!;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.defaultBlue : AppColors.gray200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.business,
                  color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  dept['name']!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.defaultBlue : null,
                  ),
                ),
              ),
              IconButton(
                onPressed: () async {
                  final favored =
                      await FavoritesStorage.toggleFavoriteDepartment(
                        dept['id']!,
                      );
                  final updated =
                      await FavoritesStorage.getFavoriteDepartmentIds();
                  setState(() => _favoriteDepartmentIds = updated);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          favored
                              ? 'Added to favorites'
                              : 'Removed from favorites',
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(
                  _favoriteDepartmentIds.contains(dept['id'])
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: _favoriteDepartmentIds.contains(dept['id'])
                      ? AppColors.orange9
                      : AppColors.onSurfaceVariant,
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.defaultBlue),
            ],
          ),
        ),
      ),
    );
  }

  void _maybePromptForMissingProfile() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final missing = <String>[];
    // Only soft prompt for missing bank account; campus can be overridden per expense
    if ((user.bankAccount ?? '').isEmpty) missing.add('Bank account');
    if (missing.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please complete your profile: ${missing.join(', ')}'),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _bankAccountController.dispose();
    _accountHolderController.dispose();
    // Payment/profile text controllers removed as we use profile directly
    _overallDescriptionController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 4) {
      if (_validateCurrentStep()) {
        setState(() => _currentStep++);
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0: // Campus & Department
        return _selectedCampusId != null && _selectedDepartmentId != null;
      case 1: // Attachments
        return _attachedFiles.isNotEmpty;
      case 2: // Details (event + description)
        return true;
      case 3: // Review
        return true;
      default:
        return true;
    }
  }

  Future<void> _submitExpense() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      setState(() {});
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      // Ensure profile exists and has bank account and campus
      await _ensureProfileExistsAndUpToDate();

      // Upload attachments and create attachment documents
      final List<String> attachmentDocIds = [];
      for (int i = 0; i < _attachedFiles.length; i++) {
        final file = _attachedFiles[i];
        final url = await _expenseService.uploadAttachmentFile(file);
        double amount = 0;
        String description = '';
        DateTime date = _expenseDate;
        String type = file.path.split('.').last.toLowerCase();
        if (i < _receiptDrafts.length) {
          final draft = _receiptDrafts[i];
          amount = draft.amount ?? 0;
          description = draft.description ?? '';
          date = draft.date ?? _expenseDate;
        }
        final doc = await _expenseService.createAttachmentDocument(
          date: date,
          url: url,
          amount: amount,
          description: description,
          type: type,
        );
        attachmentDocIds.add(doc['\$id'] as String);
      }

      // Determine total and description
      double total;
      String description;
      if (_receiptDrafts.isNotEmpty) {
        total = _receiptDrafts.fold(0, (p, e) => p + (e.amount ?? 0));
        if (_useAi) {
          final descs = _receiptDrafts
              .map((e) => e.description ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
          if (descs.isNotEmpty) {
            description = await _expenseService.summarizeExpenseDescriptions(
              descs,
            );
          } else {
            description = _descriptionController.text.trim();
          }
        } else {
          description = _descriptionController.text.trim();
        }
      } else {
        total = double.tryParse(_amountController.text) ?? 0;
        description = _descriptionController.text.trim();
      }

      final sanitizedBank = normalizeNorwegianBankAccount(
        _bankAccountController.text,
      );

      final data = <String, dynamic>{
        'campus': _selectedCampusId ?? '',
        'department': _selectedDepartmentName,
        'departmentRel': _selectedDepartmentId,
        'bank_account': sanitizedBank,
        'description': description,
        'expenseAttachments': attachmentDocIds,
        'total': _isPrepayment ? 0 : total,
        'prepayment_amount': _isPrepayment ? total : null,
        'status': 'pending',
        'user': user.id,
        'userId': user.id,
        'eventName': widget.eventName,
      };

      await _expenseService.createExpenseDocument(data: data);

      if (mounted) {
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Expense submitted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      // Minimal validation for draft: require campus & department selection
      if (_selectedCampusId == null || _selectedDepartmentId == null) {
        throw Exception('Select campus and department to save draft');
      }

      // No uploads for draft; attachments can be added later in edit flow
      final sanitizedBank = normalizeNorwegianBankAccount(
        _bankAccountController.text,
      );
      final description = (_useAi
              ? _overallDescriptionController.text
              : _descriptionController.text)
          .trim();

      final data = <String, dynamic>{
        'campus': _selectedCampusId ?? '',
        'department': _selectedDepartmentName,
        'departmentRel': _selectedDepartmentId,
        'bank_account': sanitizedBank,
        if (description.isNotEmpty) 'description': description,
        'expenseAttachments': <String>[],
        'total': 0,
        'status': 'draft',
        'user': user.id,
        'userId': user.id,
        'eventName': widget.eventName,
      };

      await _expenseService.createExpenseDocument(data: data);
      if (mounted) {
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Draft saved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to save draft: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Expense'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          if (_currentStep > 0)
            TextButton(onPressed: _previousStep, child: const Text('Back')),
        ],
      ),
      body: Column(
        children: [
          _PremiumHeader(
            step: _currentStep,
            totalSteps: 4,
            onBack: _currentStep > 0 ? _previousStep : null,
            onClose: () => Navigator.pop(context),
            title: _getStepTitle(),
          ),

          // Content
          Expanded(
            child: Form(
              key: _formKey,
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentStep = index),
                children: [
                  _buildDepartmentSelectionStep(),
                  _buildAttachmentsStep(),
                  _buildDetailsStep(),
                  _buildReviewStep(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Campus & Department';
      case 1:
        return 'Receipts';
      case 2:
        return 'Details & Summary';
      case 3:
        return 'Review & Submit';
      default:
        return '';
    }
  }

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add context (optional)',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: widget.eventName != null,
            onChanged: (_) {},
            title: const Text('Relates to an event'),
            subtitle: widget.eventName != null
                ? Text(widget.eventName!)
                : const Text('No event selected'),
            controlAffinity: ListTileControlAffinity.leading,
          ),

          const SizedBox(height: 16),
          if (_useAi)
            TextFormField(
              controller: _overallDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Overall description (AI-generated, editable)',
              ),
              maxLines: 4,
            )
          else
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Overall description',
                hintText: 'Describe briefly what the expense is for',
              ),
              maxLines: 4,
            ),

          const SizedBox(height: 24),
          PrimaryButton(enabled: true, label: 'Continue', onPressed: _nextStep),
        ],
      ),
    );
  }

  Widget _buildDepartmentSelectionStep() {
    final favoritesList = _departments
        .where((d) => _favoriteDepartmentIds.contains(d['id']))
        .toList();
    final othersList = _departments
        .where((d) => !_favoriteDepartmentIds.contains(d['id']))
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Campus and department',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your campus and the department responsible for this expense',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Campus selector (from database)
          DropdownButtonFormField<String>(
            value: _selectedCampusId,
            decoration: const InputDecoration(
              labelText: 'Campus',
              prefixIcon: Icon(Icons.location_city),
            ),
            items: _campuses
                .map(
                  (c) =>
                      DropdownMenuItem(value: c['id'], child: Text(c['name']!)),
                )
                .toList(),
            onChanged: (value) async {
              setState(() {
                _selectedCampusId = value;
                _selectedCampusName = _campuses.firstWhere(
                  (c) => c['id'] == value,
                )['name'];
                _selectedDepartmentId = null;
                _selectedDepartmentName = '';
              });
              await _loadDepartments();
            },
          ),
          const SizedBox(height: 16),

          if (favoritesList.isNotEmpty) ...[
            Text(
              'Favorites',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...favoritesList.map<Widget>((dept) {
              final isSelected = _selectedDepartmentId == dept['id'];
              return _buildDepartmentTile(dept, isSelected);
            }),
            const SizedBox(height: 16),
            Text(
              'All departments',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],

          ...(othersList.map<Widget>((dept) {
            final isSelected = _selectedDepartmentId == dept['id'];
            return _buildDepartmentTile(dept, isSelected);
          }).toList()),

          const SizedBox(height: 24),

          PrimaryButton(
            enabled: _selectedCampusId != null && _selectedDepartmentId != null,
            label: 'Continue',
            onPressed: _nextStep,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upload receipts and documents',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _isPrepayment
                ? 'For prepayments, you can upload quotes or estimates'
                : 'Upload photos or scans of your receipts',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // AI toggle
          SwitchListTile(
            title: const Text('Use AI to extract details'),
            subtitle: const Text(
              'Auto-fill date, amount and description from receipts',
            ),
            value: _useAi,
            onChanged: (value) async {
              setState(() => _useAi = value);
              if (value) {
                await _analyzeAllIfNeeded();
              }
            },
            contentPadding: EdgeInsets.zero,
          ),
          if (_isAnalyzing) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],

          // Upload Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImageFromCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImageFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('From Gallery'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _pickDocument,
            icon: const Icon(Icons.attach_file),
            label: const Text('Upload Document (PDF)'),
          ),

          const SizedBox(height: 24),

          // Attached Files List
          if (_attachedFiles.isNotEmpty) ...[
            Text(
              'Attached Files',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            ...(_attachedFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.gray200,
                            child: Icon(
                              _getFileIcon(file.path),
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              file.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _attachedFiles.removeAt(index);
                                if (index < _receiptDrafts.length) {
                                  _receiptDrafts.removeAt(index);
                                }
                              });
                            },
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      if (_useAi) ...[
                        const SizedBox(height: 8),
                        _AiFieldsEditor(
                          key: ValueKey('ai-editor-${file.path}-$index'),
                          draft: index < _receiptDrafts.length
                              ? _receiptDrafts[index]
                              : _ReceiptDraft(),
                          onChanged: (d) {
                            if (index >= _receiptDrafts.length) {
                              _receiptDrafts.add(d);
                            } else {
                              _receiptDrafts[index] = d;
                            }
                          },
                          onRetry: () => _analyzeSingle(index),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        _ManualFieldsEditor(
                          key: ValueKey('manual-editor-${file.path}-$index'),
                          initial: index < _receiptDrafts.length
                              ? _receiptDrafts[index]
                              : _ReceiptDraft(),
                          onChanged: (d) {
                            if (index >= _receiptDrafts.length) {
                              _receiptDrafts.add(d);
                            } else {
                              _receiptDrafts[index] = d;
                            }
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getFileSizeText(file),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            })),

            const SizedBox(height: 24),
          ],

          if (_attachedFiles.isEmpty && !_isPrepayment) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.outline,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 48,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No files uploaded yet',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Receipts are required for reimbursement',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          PrimaryButton(
            enabled: _attachedFiles.isNotEmpty,
            label: 'Continue',
            onPressed: _nextStep,
          ),
        ],
      ),
    );
  }

  // Legacy payment step removed (unused)

  Widget _buildReviewStep() {
    final amount = _receiptDrafts.isNotEmpty
        ? _receiptDrafts.fold(0.0, (p, e) => p + (e.amount ?? 0.0))
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Review your expense',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Please review all information before submitting',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Amount Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.subtleBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Total Amount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.defaultBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'NOK ${amount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.defaultBlue,
                  ),
                ),
                if (_isPrepayment) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.defaultBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Prepayment Request',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.defaultBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Details Cards
          _ReviewSection(
            title: 'Expense Details',
            children: [
              TextFormField(
                controller: _useAi
                    ? _overallDescriptionController
                    : _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Overall description',
                  hintText: 'What was this expense for? (you can edit)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              _ReviewItem(label: 'Campus', value: _selectedCampusName ?? ''),
              _ReviewItem(label: 'Department', value: _selectedDepartmentName),
              if (widget.eventName != null)
                _ReviewItem(label: 'Event', value: widget.eventName!),
            ],
          ),

          const SizedBox(height: 16),

          // Payment info is implicitly from profile; no manual entry step required
          const SizedBox(height: 16),

          _ReviewSection(
            title: 'Attachments',
            children: [
              _ReviewItem(
                label: 'Files',
                value: '${_attachedFiles.length} file(s) attached',
              ),
              if (_receiptDrafts.isNotEmpty)
                ..._receiptDrafts.asMap().entries.map(
                  (e) => _ReviewItem(
                    label:
                        '• ${e.value.date != null ? _formatDate(e.value.date!) : 'Date'}',
                    value:
                        'NOK ${(e.value.amount ?? 0).toStringAsFixed(2)} — ${e.value.description ?? ''}',
                  ),
                ),
            ],
          ),

          const SizedBox(height: 32),

          // Submit Button
          ElevatedButton.icon(
            onPressed: _submitExpense,
            icon: const Icon(Icons.send),
            label: Text(
              _isPrepayment ? 'Request Prepayment' : 'Submit for Approval',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save as Draft'),
          ),

          const SizedBox(height: 12),

          Text(
            'By submitting, you confirm that all information is accurate and you have appropriate receipts.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // _formatBankForInput removed (unused)

  IconData _getFileIcon(String path) {
    if (path.toLowerCase().endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else if (path.toLowerCase().contains('jpg') ||
        path.toLowerCase().contains('png') ||
        path.toLowerCase().contains('jpeg')) {
      return Icons.image;
    }
    return Icons.attach_file;
  }

  String _getFileSizeText(File file) {
    final bytes = file.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _attachedFiles.add(File(image.path));
      });
      if (_useAi) await _analyzeSingle(_attachedFiles.length - 1);
    }
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _attachedFiles.add(File(image.path));
      });
      if (_useAi) await _analyzeSingle(_attachedFiles.length - 1);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = File(result.files.first.path!);
      setState(() {
        _attachedFiles.add(file);
      });
      if (_useAi) await _analyzeSingle(_attachedFiles.length - 1);
    }
  }

  Future<void> _loadDepartments() async {
    if (_selectedCampusId == null) return;
    try {
      final list = await _expenseService.listDepartmentsForCampus(
        _selectedCampusId!,
      );
      setState(() {
        _departments = list
            .map(
              (e) => {
                'id': (e['Id'] ?? '').toString(),
                'name': (e['Name'] ?? '').toString(),
              },
            )
            .where((e) => e['id']!.isNotEmpty && e['name']!.isNotEmpty)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _analyzeAllIfNeeded() async {
    if (!_useAi) return;
    for (int i = 0; i < _attachedFiles.length; i++) {
      if (i >= _receiptDrafts.length || _receiptDrafts[i].isEmpty) {
        await _analyzeSingle(i);
      }
    }
    await _refreshOverallSummary();
  }

  Future<void> _analyzeSingle(int index) async {
    if (!_useAi) return;
    if (index < 0 || index >= _attachedFiles.length) return;
    try {
      setState(() => _isAnalyzing = true);
      final file = _attachedFiles[index];
      final text = await _extractText(file);
      if (text.trim().isEmpty) {
        setState(() => _isAnalyzing = false);
        return;
      }
      final result = await _expenseService.analyzeReceiptText(text);
      final parsed = _ReceiptDraft(
        amount: _safeDouble(result['amount']),
        description: (result['description'] ?? '').toString(),
        date: _safeDate(result['date']),
      );
      if (index >= _receiptDrafts.length) {
        _receiptDrafts.add(parsed);
      } else {
        _receiptDrafts[index] = parsed;
      }
      setState(() => _isAnalyzing = false);
      await _refreshOverallSummary();
    } catch (_) {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _refreshOverallSummary() async {
    if (!_useAi) return;
    final descs = _receiptDrafts
        .map((e) => e.description ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (descs.isEmpty) return;
    final summary = await _expenseService.summarizeExpenseDescriptions(descs);
    if (summary.trim().isNotEmpty) {
      setState(() {
        _overallDescriptionController.text = summary.trim();
      });
    }
  }

  Future<void> _ensureProfileExistsAndUpToDate() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final hasProfile = ref.read(hasProfileProvider);
    final name = _accountHolderController.text.trim().isEmpty
        ? user.name
        : _accountHolderController.text.trim();
    final phone = user.phone;
    final address = user.address;
    final city = user.city;
    final zip = user.zipCode;
    final campusId = _selectedCampusId ?? user.campusId;
    final bank = normalizeNorwegianBankAccount(_bankAccountController.text);
    final effectiveBank = bank.isEmpty
        ? normalizeNorwegianBankAccount(user.bankAccount ?? '')
        : bank;
    try {
      if (hasProfile) {
        await ref
            .read(authServiceProvider)
            .updateUserProfile(
              name: name,
              phone: phone,
              address: address,
              city: city,
              zipCode: zip,
              campusId: campusId,
              bankAccount: effectiveBank,
            );
      } else {
        await ref
            .read(authServiceProvider)
            .createUserProfile(
              name: name,
              phone: phone,
              address: address,
              city: city,
              zipCode: zip,
              campusId: campusId,
              departments: const [],
              bankAccount: effectiveBank,
            );
      }
      await ref.read(authStateProvider.notifier).refreshProfile();
    } catch (_) {}
  }

  Future<String> _extractText(File file) async {
    final lower = file.path.toLowerCase();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      if (lower.endsWith('.pdf')) {
        // 1) Try text layer first (fast, if selectable text exists)
        try {
          final bytes = await file.readAsBytes();
          final document = PdfDocument(inputBytes: bytes);
          final textExtractor = PdfTextExtractor(document);
          final extracted = textExtractor.extractText();
          document.dispose();
          if (extracted.trim().isNotEmpty) return extracted;
        } catch (_) {}
        // 2) Deep OCR fallback: rasterize first pages and run ML Kit
        try {
          final bytes = await file.readAsBytes();
          final buffer = StringBuffer();
          int processed = 0;
          await for (final page in Printing.raster(bytes, dpi: 170)) {
            if (processed >= 3) break; // safety cap
            final uiImage = await page.toImage();
            final byteData = await uiImage.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData != null) {
              final tmp = File('${file.path}.p$processed.png');
              await tmp.writeAsBytes(
                byteData.buffer.asUint8List(),
                flush: true,
              );
              try {
                final inputImage = InputImage.fromFile(tmp);
                final text = await recognizer.processImage(inputImage);
                if (text.text.isNotEmpty) buffer.writeln(text.text);
              } finally {
                if (await tmp.exists()) await tmp.delete();
              }
            }
            processed++;
          }
          return buffer.toString();
        } catch (_) {
          return '';
        }
      } else {
        final inputImage = InputImage.fromFile(file);
        final text = await recognizer.processImage(inputImage);
        return text.text;
      }
    } catch (_) {
      return '';
    } finally {
      await recognizer.close();
    }
  }

  double? _safeDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  DateTime? _safeDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ReviewSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// _BankAccountFormatter removed (unused)

class _ReceiptDraft {
  final double? amount;
  final String? description;
  final DateTime? date;

  _ReceiptDraft({this.amount, this.description, this.date});

  bool get isEmpty =>
      (amount == null || amount == 0) &&
      (description == null || description!.isEmpty) &&
      date == null;
}

class _ManualFieldsEditor extends StatefulWidget {
  final _ReceiptDraft initial;
  final void Function(_ReceiptDraft) onChanged;

  const _ManualFieldsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_ManualFieldsEditor> createState() => _ManualFieldsEditorState();
}

class _ManualFieldsEditorState extends State<_ManualFieldsEditor> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initial.amount?.toStringAsFixed(2) ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.initial.description ?? '',
    );
    _date = widget.initial.date;
  }

  @override
  void didUpdateWidget(covariant _ManualFieldsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newAmount = widget.initial.amount != null
        ? widget.initial.amount!.toStringAsFixed(2)
        : '';
    if (_amountController.text != newAmount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _amountController.value = TextEditingValue(
          text: newAmount,
          selection: TextSelection.collapsed(offset: newAmount.length),
        );
      });
    }
    final newDesc = widget.initial.description ?? '';
    if (_descriptionController.text != newDesc) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _descriptionController.value = TextEditingValue(
          text: newDesc,
          selection: TextSelection.collapsed(offset: newDesc.length),
        );
      });
    }
    _date = widget.initial.date ?? _date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _date != null
        ? '${_date!.day}/${_date!.month}/${_date!.year}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount (NOK)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textDirection: TextDirection.ltr,
                onChanged: (v) => widget.onChanged(
                  _ReceiptDraft(
                    amount: double.tryParse(v),
                    description: _descriptionController.text,
                    date: _date,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date ?? now,
                    firstDate: now.subtract(const Duration(days: 365 * 3)),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setState(() => _date = picked);
                    widget.onChanged(
                      _ReceiptDraft(
                        amount: double.tryParse(_amountController.text),
                        description: _descriptionController.text,
                        date: picked,
                      ),
                    );
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(dateText.isEmpty ? 'Select' : dateText),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          textDirection: TextDirection.ltr,
          onChanged: (v) => widget.onChanged(
            _ReceiptDraft(
              amount: double.tryParse(_amountController.text),
              description: v,
              date: _date,
            ),
          ),
        ),
      ],
    );
  }
}

class _AiFieldsEditor extends StatefulWidget {
  final _ReceiptDraft draft;
  final void Function(_ReceiptDraft) onChanged;
  final Future<void> Function() onRetry;

  const _AiFieldsEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  State<_AiFieldsEditor> createState() => _AiFieldsEditorState();
}

class _AiFieldsEditorState extends State<_AiFieldsEditor> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.draft.amount?.toStringAsFixed(2) ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.draft.description ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _AiFieldsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newAmountText = widget.draft.amount != null
        ? widget.draft.amount!.toStringAsFixed(2)
        : '';
    if (_amountController.text != newAmountText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _amountController.value = TextEditingValue(
          text: newAmountText,
          selection: TextSelection.collapsed(offset: newAmountText.length),
        );
      });
    }
    final newDescText = widget.draft.description ?? '';
    if (_descriptionController.text != newDescText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _descriptionController.value = TextEditingValue(
          text: newDescText,
          selection: TextSelection.collapsed(offset: newDescText.length),
        );
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateText = widget.draft.date != null
        ? '${widget.draft.date!.day}/${widget.draft.date!.month}/${widget.draft.date!.year}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount (NOK)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textDirection: TextDirection.ltr,
                onChanged: (v) => widget.onChanged(
                  _ReceiptDraft(
                    amount: double.tryParse(v),
                    description: _descriptionController.text,
                    date: widget.draft.date,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: widget.draft.date ?? now,
                    firstDate: now.subtract(const Duration(days: 365 * 3)),
                    lastDate: now,
                  );
                  if (picked != null) {
                    widget.onChanged(
                      _ReceiptDraft(
                        amount: double.tryParse(_amountController.text),
                        description: _descriptionController.text,
                        date: picked,
                      ),
                    );
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(dateText.isEmpty ? 'Select' : dateText),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          textDirection: TextDirection.ltr,
          onChanged: (v) => widget.onChanged(
            _ReceiptDraft(
              amount: double.tryParse(_amountController.text),
              description: v,
              date: widget.draft.date,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Re-run AI'),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButtonPainter extends CustomPainter {
  final Color color;
  _PrimaryButtonPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r.outerRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(r, paint);
  }

  @override
  bool shouldRepaint(covariant _PrimaryButtonPainter oldDelegate) =>
      oldDelegate.color != color;
}

class PrimaryButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const PrimaryButton({
    super.key,
    this.enabled = true,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final Color base = enabled ? AppColors.defaultBlue : AppColors.gray200;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.6,
        child: CustomPaint(
          painter: _PrimaryButtonPainter(base),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  final String title;
  const _PremiumHeader({
    required this.step,
    required this.totalSteps,
    required this.onBack,
    required this.onClose,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / totalSteps;
    return Container(
      padding: const EdgeInsets.only(top: 48, left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.subtleBlue, Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: onBack,
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.gray200,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.defaultBlue),
            ),
          ),
        ],
      ),
    );
  }
}
