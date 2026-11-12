import 'dart:convert';

import '../../core/utils/expense_type_state.dart';
import '../../core/utils/norwegian_bank_account.dart';
import 'expense_cost_type_option.dart';
import 'expense_model.dart';
import 'user_model.dart';

enum ExpenseReceiptStatus {
  uploading,
  processing,
  analyzing,
  ready,
  error,
  editing,
}

class ExpenseAssignment {
  final String campusId;
  final String campusName;
  final String departmentId;
  final String departmentName;

  const ExpenseAssignment({
    required this.campusId,
    required this.campusName,
    required this.departmentId,
    required this.departmentName,
  });

  bool get isComplete =>
      campusId.isNotEmpty &&
      campusName.isNotEmpty &&
      departmentId.isNotEmpty &&
      departmentName.isNotEmpty;

  Map<String, dynamic> toSummaryMap() {
    return {
      'campusId': campusId,
      'campusName': campusName,
      'departmentId': departmentId,
      'departmentName': departmentName,
    };
  }
}

class ExpenseUploadedFile {
  final String fileId;
  final String viewUrl;
  final String mimeType;
  final String fileName;

  const ExpenseUploadedFile({
    required this.fileId,
    required this.viewUrl,
    required this.mimeType,
    required this.fileName,
  });
}

class ExpenseOcrResult {
  final String? address;
  final String? category;
  final String? city;
  final String? country;
  final String documentType;
  final String? description;
  final double? amount;
  final String currency;
  final DateTime? date;
  final String? purchaseContext;
  final String? vendor;
  final double? amountInNok;
  final double? exchangeRate;
  final String? method;

  /// The AI's expense type pick (a slug) and how sure it is, 0 to 1.
  final String? costType;
  final double costTypeConfidence;
  final List<String> receiptIssues;
  final double? ocrAmount;
  final bool possibleDuplicate;

  const ExpenseOcrResult({
    this.address,
    this.category,
    this.city,
    this.country,
    this.documentType = 'receipt',
    this.description,
    this.amount,
    this.currency = 'NOK',
    this.date,
    this.purchaseContext,
    this.vendor,
    this.amountInNok,
    this.exchangeRate,
    this.method,
    this.costType,
    this.costTypeConfidence = 0,
    this.receiptIssues = const [],
    this.ocrAmount,
    this.possibleDuplicate = false,
  });

  factory ExpenseOcrResult.fromMap(Map<String, dynamic> map) {
    final data = map['data'] is Map<String, dynamic>
        ? map['data'] as Map<String, dynamic>
        : map;
    return ExpenseOcrResult(
      address: _stringOrNull(data['address']),
      category: _stringOrNull(data['category']),
      city: _stringOrNull(data['city']),
      country: _stringOrNull(data['country']),
      documentType: _stringOrNull(data['documentType']) ?? 'receipt',
      description: _stringOrNull(data['description']),
      amount: _doubleOrNull(data['amount']),
      currency: (_stringOrNull(data['currency']) ?? 'NOK').toUpperCase(),
      date: _dateOrNull(data['date']),
      purchaseContext: _stringOrNull(data['purchaseContext']),
      vendor: _stringOrNull(data['vendor']),
      amountInNok: _doubleOrNull(data['amountInNok']),
      exchangeRate: _doubleOrNull(data['exchangeRate']),
      method: _stringOrNull(map['method'] ?? data['method']),
      costType: _stringOrNull(data['costType']),
      costTypeConfidence: _doubleOrNull(data['costTypeConfidence']) ?? 0,
      receiptIssues: data['receiptIssues'] is List
          ? (data['receiptIssues'] as List).map((e) => e.toString()).toList()
          : const [],
      ocrAmount: _doubleOrNull(data['ocrAmount']),
      possibleDuplicate: data['possibleDuplicate'] == true,
    );
  }
}

class ExpenseReceiptDraft {
  final String localId;
  final String fileName;
  final String? localPath;
  final String? fileId;
  final String? viewUrl;
  final String mimeType;
  final ExpenseReceiptStatus status;
  final String? error;
  final String documentType;
  final String? parentReceiptId;
  final String? vendor;
  final DateTime? date;
  final double? amount;
  final double? amountInNok;
  final String currency;
  final double? exchangeRate;
  final String? originalForeignAmount;
  final String? category;

  /// The expense type slug, from the AI's pick or the student's choice. Null
  /// until there is one; it never falls back to a default.
  final String? costType;

  /// The student's own words, in place of a listed type.
  final String? costTypeText;
  final ExpenseTypeState typeState;
  final double? aiConfidence;
  final List<String> receiptIssues;
  final bool possibleDuplicate;
  final double? ocrAmount;
  final String? city;
  final String? country;
  final String? purchaseContext;
  final String description;
  final bool hasLinkedBankStatement;

  const ExpenseReceiptDraft({
    required this.localId,
    required this.fileName,
    this.localPath,
    this.fileId,
    this.viewUrl,
    required this.mimeType,
    this.status = ExpenseReceiptStatus.uploading,
    this.error,
    this.documentType = 'receipt',
    this.parentReceiptId,
    this.vendor,
    this.date,
    this.amount,
    this.amountInNok,
    this.currency = 'NOK',
    this.exchangeRate,
    this.originalForeignAmount,
    this.category,
    this.costType,
    this.costTypeText,
    this.typeState = ExpenseTypeState.needsChoice,
    this.aiConfidence,
    this.receiptIssues = const [],
    this.possibleDuplicate = false,
    this.ocrAmount,
    this.city,
    this.country,
    this.purchaseContext,
    this.description = '',
    this.hasLinkedBankStatement = false,
  });

  factory ExpenseReceiptDraft.manual({
    required String localId,
    required String fileName,
    required String localPath,
    required String mimeType,
  }) {
    return ExpenseReceiptDraft(
      localId: localId,
      fileName: fileName,
      localPath: localPath,
      mimeType: mimeType,
    );
  }

  bool get isReady => status == ExpenseReceiptStatus.ready;
  bool get isBusy =>
      status == ExpenseReceiptStatus.uploading ||
      status == ExpenseReceiptStatus.processing ||
      status == ExpenseReceiptStatus.analyzing;
  bool get isBankStatement => documentType == 'bank-statement';
  bool get isForeignCurrency => currency.toUpperCase() != 'NOK';
  bool get hasEstimatedNok =>
      isForeignCurrency && amountInNok != null && !hasLinkedBankStatement;
  double get effectiveAmount => amountInNok ?? amount ?? 0;

  ExpenseReceiptDraft copyWith({
    String? fileName,
    String? localPath,
    String? fileId,
    String? viewUrl,
    String? mimeType,
    ExpenseReceiptStatus? status,
    String? error,
    String? documentType,
    String? parentReceiptId,
    String? vendor,
    DateTime? date,
    double? amount,
    double? amountInNok,
    String? currency,
    double? exchangeRate,
    String? originalForeignAmount,
    String? category,
    String? costType,
    String? costTypeText,
    ExpenseTypeState? typeState,
    double? aiConfidence,
    List<String>? receiptIssues,
    bool? possibleDuplicate,
    double? ocrAmount,
    bool clearCostType = false,
    bool clearCostTypeText = false,
    bool clearOcrAmount = false,
    String? city,
    String? country,
    String? purchaseContext,
    String? description,
    bool? hasLinkedBankStatement,
  }) {
    return ExpenseReceiptDraft(
      localId: localId,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      fileId: fileId ?? this.fileId,
      viewUrl: viewUrl ?? this.viewUrl,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      error: error,
      documentType: documentType ?? this.documentType,
      parentReceiptId: parentReceiptId ?? this.parentReceiptId,
      vendor: vendor ?? this.vendor,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      amountInNok: amountInNok ?? this.amountInNok,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      originalForeignAmount:
          originalForeignAmount ?? this.originalForeignAmount,
      category: category ?? this.category,
      costType: clearCostType ? null : (costType ?? this.costType),
      costTypeText: clearCostTypeText
          ? null
          : (costTypeText ?? this.costTypeText),
      typeState: typeState ?? this.typeState,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      receiptIssues: receiptIssues ?? this.receiptIssues,
      possibleDuplicate: possibleDuplicate ?? this.possibleDuplicate,
      ocrAmount: clearOcrAmount ? null : (ocrAmount ?? this.ocrAmount),
      city: city ?? this.city,
      country: country ?? this.country,
      purchaseContext: purchaseContext ?? this.purchaseContext,
      description: description ?? this.description,
      hasLinkedBankStatement:
          hasLinkedBankStatement ?? this.hasLinkedBankStatement,
    );
  }

  ExpenseReceiptDraft withUpload(ExpenseUploadedFile upload) {
    return copyWith(
      fileId: upload.fileId,
      viewUrl: upload.viewUrl,
      mimeType: upload.mimeType,
      fileName: upload.fileName,
      status: ExpenseReceiptStatus.processing,
    );
  }

  ExpenseReceiptDraft withOcr(ExpenseOcrResult result) {
    final parsedDescription = [
      result.vendor,
      result.description,
    ].where((value) => value != null && value.trim().isNotEmpty).join(' - ');

    return copyWith(
      status: ExpenseReceiptStatus.ready,
      documentType: result.documentType,
      vendor: result.vendor,
      date: result.date,
      amount: result.amount,
      amountInNok: result.amountInNok,
      currency: result.currency,
      exchangeRate: result.exchangeRate,
      originalForeignAmount: result.amount != null && result.currency != 'NOK'
          ? '${result.amount!.toStringAsFixed(2)} ${result.currency}'
          : originalForeignAmount,
      category: result.category,
      city: result.city,
      country: result.country,
      purchaseContext: result.purchaseContext,
      description: parsedDescription.isNotEmpty
          ? parsedDescription
          : description,
    );
  }

  /// Applies the AI's type pick from [ocr]: it counts at 0.8 confidence or
  /// more with a slug among the active [types]; anything else needs a choice.
  /// Also copies the receipt issues, duplicate flag and OCR amount. The screen
  /// calls this after [withOcr], which leaves the type alone. A receipt whose
  /// type the student already chose keeps it on a re-scan, and a bank
  /// statement takes no type at all.
  ExpenseReceiptDraft withAiPick(
    ExpenseOcrResult ocr,
    List<ExpenseCostTypeOption> types,
  ) {
    if (isBankStatement || parentReceiptId != null) return this;
    if (typeState == ExpenseTypeState.chosen) {
      return copyWith(
        aiConfidence: ocr.costTypeConfidence,
        receiptIssues: ocr.receiptIssues,
        possibleDuplicate: ocr.possibleDuplicate,
        ocrAmount: ocr.ocrAmount,
        clearOcrAmount: ocr.ocrAmount == null,
      );
    }
    final slug = ocr.costType;
    final picked =
        slug != null &&
        ocr.costTypeConfidence >= aiTypeConfidenceThreshold &&
        types.any((type) => type.slug == slug);
    return copyWith(
      typeState: picked
          ? ExpenseTypeState.aiPicked
          : ExpenseTypeState.needsChoice,
      costType: picked ? slug : null,
      clearCostType: !picked,
      clearCostTypeText: true,
      aiConfidence: ocr.costTypeConfidence,
      receiptIssues: ocr.receiptIssues,
      possibleDuplicate: ocr.possibleDuplicate,
      ocrAmount: ocr.ocrAmount,
      clearOcrAmount: ocr.ocrAmount == null,
    );
  }

  /// The student chose a listed type.
  ExpenseReceiptDraft chooseType(String slug) => copyWith(
    costType: slug,
    clearCostTypeText: true,
    typeState: ExpenseTypeState.chosen,
  );

  /// The student wrote their own type. Blank text is refused and the receipt
  /// stays as it is.
  ExpenseReceiptDraft useOwnText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return this;
    final capped = trimmed.length > maxOwnTypeTextLength
        ? trimmed.substring(0, maxOwnTypeTextLength).trimRight()
        : trimmed;
    return copyWith(
      costTypeText: capped,
      clearCostType: true,
      typeState: ExpenseTypeState.chosen,
    );
  }

  /// Restores the type of a saved draft attachment. Own text and an active
  /// slug count as chosen; a slug finance has since deactivated asks again,
  /// but only against [types] that actually loaded. With null [types] a stored
  /// slug stays chosen, so saving the draft sends it back unchanged.
  ExpenseReceiptDraft hydrateType({
    String? slug,
    String? text,
    required List<ExpenseCostTypeOption>? types,
  }) {
    if (text != null && text.trim().isNotEmpty) return useOwnText(text);
    if (slug != null &&
        slug.isNotEmpty &&
        (types == null || types.any((type) => type.slug == slug))) {
      return chooseType(slug);
    }
    return copyWith(
      clearCostType: true,
      clearCostTypeText: true,
      typeState: ExpenseTypeState.needsChoice,
    );
  }

  Map<String, dynamic> toSummaryMap() {
    return {
      'amount': effectiveAmount,
      'category': category ?? 'other',
      'city': city,
      'country': country,
      'currency': currency,
      'date': _formatDate(date),
      'description': description,
      'documentType': documentType,
      'purchaseContext': purchaseContext,
      'vendor': vendor,
    };
  }

  Map<String, dynamic> toAttachmentMap({int sortOrder = 0}) {
    return {
      'date': _formatDate(date),
      'url': fileId,
      'amount': isBankStatement ? 0 : effectiveAmount,
      'description': description.isNotEmpty
          ? description
          : isBankStatement
          ? 'Bank statement'
          : fileName,
      'type': mimeType,
      ...attachmentTypeFields(this),
      'sort_order': sortOrder,
    };
  }
}

class ExpensePayloadBuilder {
  static Map<String, dynamic> buildBasePayload({
    String? expenseId,
    required ExpenseAssignment assignment,
    required String bankAccount,
    required String description,
    required List<ExpenseReceiptDraft> receipts,
    double prepaymentAmount = 0,
    String? eventName,
    bool submitterIsFinancialManager = false,
    bool submitterIsController = false,
  }) {
    final normalizedBank = normalizeNorwegianBankAccount(bankAccount);
    final readyReceipts = receipts
        .where((receipt) => receipt.isReady && receipt.fileId != null)
        .toList();
    final total = readyReceipts
        .where((receipt) => !receipt.isBankStatement)
        .fold<double>(0, (sum, receipt) => sum + receipt.effectiveAmount);

    return {
      if (expenseId != null && expenseId.isNotEmpty) 'expenseId': expenseId,
      'campus': assignment.campusId,
      'department': assignment.departmentId,
      'bank_account': normalizedBank,
      'description': description,
      'total': total,
      'prepayment_amount': prepaymentAmount,
      'eventName': eventName ?? '',
      'submitter_is_financial_manager': submitterIsFinancialManager,
      'submitter_is_controller': submitterIsController,
      'expenseAttachments': [
        for (final (index, receipt) in readyReceipts.indexed)
          receipt.toAttachmentMap(sortOrder: index),
      ],
    };
  }

  static Map<String, dynamic> buildSummaryPayload({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) {
    return {
      'assignment': assignment.toSummaryMap(),
      'receipts': receipts
          .where((receipt) => receipt.isReady && !receipt.isBankStatement)
          .map((receipt) => receipt.toSummaryMap())
          .toList(),
    };
  }

  static String summarySnapshot({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) {
    return jsonEncode(
      buildSummaryPayload(assignment: assignment, receipts: receipts),
    );
  }
}

class ExpenseProfileReadiness {
  final List<String> missingFields;

  const ExpenseProfileReadiness(this.missingFields);

  bool get isReady => missingFields.isEmpty;

  factory ExpenseProfileReadiness.fromUser(UserModel? user) {
    if (user == null) return const ExpenseProfileReadiness(['profile']);
    final missing = <String>[];
    if (user.name.trim().isEmpty) missing.add('name');
    if (user.email.trim().isEmpty) missing.add('email');
    if ((user.phone ?? '').trim().isEmpty) missing.add('phone');
    if ((user.bankAccount ?? '').trim().isEmpty) {
      missing.add('bank account');
    } else if (!isValidNorwegianBankAccount(user.bankAccount!)) {
      missing.add('valid bank account');
    }
    if ((user.address ?? '').trim().isEmpty) missing.add('address');
    if ((user.zipCode ?? '').trim().isEmpty) missing.add('zip');
    if ((user.city ?? '').trim().isEmpty) missing.add('city');
    return ExpenseProfileReadiness(missing);
  }
}

class ExpenseSubmitResult {
  final bool success;
  final ExpenseModel? expense;
  final String? expenseId;
  final int? reimbursementNumber;

  const ExpenseSubmitResult({
    required this.success,
    this.expense,
    this.expenseId,
    this.reimbursementNumber,
  });

  factory ExpenseSubmitResult.fromMap(Map<String, dynamic> map) {
    final fetched = map['fetchedExpense'];
    final expenseMap = fetched is Map<String, dynamic> ? fetched : null;
    final expense = expenseMap != null
        ? ExpenseModel.fromMap(expenseMap)
        : null;
    return ExpenseSubmitResult(
      success: map['success'] == true,
      expense: expense,
      expenseId: expense?.id ?? _stringOrNull(expenseMap?['\$id']),
      reimbursementNumber: _intOrNull(map['reimbursementNumber']),
    );
  }
}

class ExpenseDraftResult {
  final bool success;
  final String? draftId;
  final Map<String, dynamic>? draft;

  const ExpenseDraftResult({required this.success, this.draftId, this.draft});

  factory ExpenseDraftResult.fromMap(Map<String, dynamic> map) {
    final draftMap = map['draft'] is Map<String, dynamic>
        ? map['draft'] as Map<String, dynamic>
        : null;
    return ExpenseDraftResult(
      success: map['success'] == true,
      draftId: _stringOrNull(draftMap?['\$id']),
      draft: draftMap,
    );
  }
}

String? _stringOrNull(dynamic value) {
  if (value == null) return null;
  final string = value.toString();
  return string.isEmpty ? null : string;
}

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.'));
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _dateOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String? _formatDate(DateTime? date) {
  if (date == null) return null;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
