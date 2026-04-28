import 'dart:convert';

import '../../core/utils/norwegian_bank_account.dart';
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

  Map<String, dynamic> toAttachmentMap() {
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
      'expenseAttachments': readyReceipts
          .map((receipt) => receipt.toAttachmentMap())
          .toList(),
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
