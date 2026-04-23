import 'package:equatable/equatable.dart';
import '../../core/utils/norwegian_bank_account.dart';
import 'expense_attachment_model.dart';

/// ExpenseModel that matches the database schema exactly
class ExpenseModel extends Equatable {
  final String id;
  final String userId; // Required - matches userId field
  final String campus; // Required - matches campus field
  final String department; // Required - matches department field
  final String
  bankAccount; // Required - matches bank_account field (Norwegian 11-digit format)
  final String? description; // Optional - matches description field
  final double total; // Required - matches total field
  final double? prepaymentAmount; // Optional - matches prepayment_amount field
  final String
  status; // Enum - matches status field (draft, pending, submitted, success, rejected)
  final int? invoiceId; // Optional - matches invoice_id field
  final String? eventName; // Optional - matches eventName field
  final List<ExpenseAttachmentModel>
  expenseAttachments; // Relationship - matches expenseAttachments relationship
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Additional fields for UI/display purposes
  final String? userName;
  final String? userEmail;
  final String? departmentName;
  final String? rejectionReason;
  final String? approverUserId;
  final String? approverName;
  final DateTime? approvedAt;
  final DateTime? paidAt;

  const ExpenseModel({
    required this.id,
    required this.userId,
    required this.campus,
    required this.department,
    required this.bankAccount,
    this.description,
    required this.total,
    this.prepaymentAmount,
    this.status = 'pending',
    this.invoiceId,
    this.eventName,
    this.expenseAttachments = const [],
    this.createdAt,
    this.updatedAt,
    // UI/display fields
    this.userName,
    this.userEmail,
    this.departmentName,
    this.rejectionReason,
    this.approverUserId,
    this.approverName,
    this.approvedAt,
    this.paidAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    // Handle expense attachments relationship
    List<ExpenseAttachmentModel> attachments = [];
    if (map['expenseAttachments'] != null) {
      if (map['expenseAttachments'] is List) {
        attachments = (map['expenseAttachments'] as List)
            .map(
              (attachment) => ExpenseAttachmentModel.fromMap(
                attachment is Map<String, dynamic> ? attachment : {},
              ),
            )
            .toList();
      }
    }

    return ExpenseModel(
      id: map['\$id'] ?? '',
      userId: map['userId'] ?? '',
      campus: map['campus'] ?? '',
      department: map['department'] ?? '',
      bankAccount: map['bank_account'] ?? '',
      description: map['description'],
      total: (map['total'] ?? 0).toDouble(),
      prepaymentAmount: map['prepayment_amount'] != null
          ? (map['prepayment_amount']).toDouble()
          : null,
      status: map['status'] ?? 'pending',
      invoiceId: map['invoice_id'],
      eventName: map['eventName'],
      expenseAttachments: attachments,
      createdAt: map['\$createdAt'] != null
          ? DateTime.parse(map['\$createdAt'])
          : null,
      updatedAt: map['\$updatedAt'] != null
          ? DateTime.parse(map['\$updatedAt'])
          : null,
      // UI/display fields (might come from relationships or be populated separately)
      userName: map['user_name'],
      userEmail: map['user_email'],
      departmentName: map['department_name'],
      rejectionReason: map['rejection_reason'],
      approverUserId: map['approver_user_id'],
      approverName: map['approver_name'],
      approvedAt: map['approved_at'] != null
          ? DateTime.parse(map['approved_at'])
          : null,
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'campus': campus,
      'department': department,
      'bank_account': bankAccount,
      if (description != null) 'description': description,
      'total': total,
      if (prepaymentAmount != null) 'prepayment_amount': prepaymentAmount,
      'status': status,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (eventName != null) 'eventName': eventName,
      // Note: expenseAttachments relationship is handled separately

      // Additional UI fields (not part of core schema)
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (approverUserId != null) 'approver_user_id': approverUserId,
      if (approverName != null) 'approver_name': approverName,
      if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
    };
  }

  ExpenseModel copyWith({
    String? id,
    String? userId,
    String? campus,
    String? department,
    String? bankAccount,
    String? description,
    double? total,
    double? prepaymentAmount,
    String? status,
    int? invoiceId,
    String? eventName,
    List<ExpenseAttachmentModel>? expenseAttachments,
    DateTime? createdAt,
    DateTime? updatedAt,
    // UI/display fields
    String? userName,
    String? userEmail,
    String? departmentName,
    String? rejectionReason,
    String? approverUserId,
    String? approverName,
    DateTime? approvedAt,
    DateTime? paidAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      campus: campus ?? this.campus,
      department: department ?? this.department,
      bankAccount: bankAccount ?? this.bankAccount,
      description: description ?? this.description,
      total: total ?? this.total,
      prepaymentAmount: prepaymentAmount ?? this.prepaymentAmount,
      status: status ?? this.status,
      invoiceId: invoiceId ?? this.invoiceId,
      eventName: eventName ?? this.eventName,
      expenseAttachments: expenseAttachments ?? this.expenseAttachments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // UI/display fields
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      departmentName: departmentName ?? this.departmentName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approverUserId: approverUserId ?? this.approverUserId,
      approverName: approverName ?? this.approverName,
      approvedAt: approvedAt ?? this.approvedAt,
      paidAt: paidAt ?? this.paidAt,
    );
  }

  // Status helpers based on enum values
  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending';
  bool get isSubmitted => status == 'submitted';
  bool get isSuccess => status == 'success';
  bool get isRejected => status == 'rejected';

  // UI helpers
  // Only draft expenses can be edited; submitted/pending/success/rejected are locked
  bool get canEdit => isDraft;
  // Draft can be submitted when it has at least one attachment
  bool get canSubmit => isDraft && expenseAttachments.isNotEmpty;
  bool get hasPrepayment => prepaymentAmount != null && prepaymentAmount! > 0;

  String get formattedTotal => 'NOK ${total.toStringAsFixed(2)}';
  String get formattedAmount => formattedTotal; // Backwards compatibility

  String get displayStatus {
    switch (status) {
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
        return status.toUpperCase();
    }
  }

  // Get display name for department
  String get displayDepartment => departmentName ?? department;

  // Get attachment count
  int get attachmentCount => expenseAttachments.length;

  // Get attachment file names for backward compatibility
  List<String> get attachments => expenseAttachments
      .where((attachment) => attachment.url != null)
      .map((attachment) => attachment.url!.split('/').last)
      .toList();

  // Category-like display based on description or department
  String get displayCategory {
    if (description != null) {
      final desc = description!.toLowerCase();
      if (desc.contains('travel') ||
          desc.contains('taxi') ||
          desc.contains('transport')) {
        return 'Travel';
      } else if (desc.contains('food') ||
          desc.contains('catering') ||
          desc.contains('meal')) {
        return 'Food & Beverages';
      } else if (desc.contains('supplies') ||
          desc.contains('office') ||
          desc.contains('equipment')) {
        return 'Supplies';
      } else if (desc.contains('event')) {
        return 'Event Expenses';
      }
    }
    return 'Other';
  }

  // Get category for icon/color matching (backwards compatibility)
  String get category {
    final desc = description?.toLowerCase() ?? '';
    if (desc.contains('travel') ||
        desc.contains('taxi') ||
        desc.contains('transport')) {
      return 'travel';
    } else if (desc.contains('food') ||
        desc.contains('catering') ||
        desc.contains('meal')) {
      return 'food';
    } else if (desc.contains('supplies') ||
        desc.contains('office') ||
        desc.contains('equipment')) {
      return 'supplies';
    } else if (desc.contains('event')) {
      return 'event';
    }
    return 'other';
  }

  // Expense date (for now use createdAt, can be enhanced later)
  DateTime get expenseDate => createdAt ?? DateTime.now();

  // Prepayment flag for backward compatibility
  bool get isPrepayment => hasPrepayment;

  // Validate Norwegian bank account number (11 digits with MOD11 checksum)
  bool get isValidBankAccount {
    return isValidNorwegianBankAccount(bankAccount);
  }

  // Format bank account for display (XXXX XX XXXXX)
  String get formattedBankAccount {
    return formatNorwegianBankAccount(bankAccount);
  }

  @override
  List<Object?> get props => [
    id, userId, campus, department, bankAccount, description,
    total, prepaymentAmount, status, invoiceId, eventName,
    expenseAttachments, createdAt, updatedAt,
    // UI/display fields
    userName, userEmail, departmentName, rejectionReason,
    approverUserId, approverName, approvedAt, paidAt,
  ];
}
