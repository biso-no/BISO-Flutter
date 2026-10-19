import 'package:equatable/equatable.dart';

/// ExpenseAttachmentModel that matches the expenseAttachments collection schema
class ExpenseAttachmentModel extends Equatable {
  final String? id;
  final DateTime? date;
  final String? url;
  final double? amount;
  final String? description;
  final String type; // Required field
  final String? costType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExpenseAttachmentModel({
    this.id,
    this.date,
    this.url,
    this.amount,
    this.description,
    required this.type,
    this.costType,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseAttachmentModel.fromMap(Map<String, dynamic> map) {
    return ExpenseAttachmentModel(
      id: map['\$id'],
      date: map['date'] != null ? DateTime.parse(map['date']) : null,
      url: map['url'],
      amount: map['amount'] != null ? (map['amount']).toDouble() : null,
      description: map['description'],
      type: map['type'] ?? '',
      costType: map['cost_type'],
      createdAt: map['\$createdAt'] != null
          ? DateTime.parse(map['\$createdAt'])
          : null,
      updatedAt: map['\$updatedAt'] != null
          ? DateTime.parse(map['\$updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (date != null) 'date': date!.toIso8601String(),
      if (url != null) 'url': url,
      if (amount != null) 'amount': amount,
      if (description != null) 'description': description,
      'type': type,
    };
  }

  ExpenseAttachmentModel copyWith({
    String? id,
    DateTime? date,
    String? url,
    double? amount,
    String? description,
    String? type,
    String? costType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseAttachmentModel(
      id: id ?? this.id,
      date: date ?? this.date,
      url: url ?? this.url,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Getters for UI display
  String get fileName {
    if (url != null) {
      return url!.split('/').last;
    }
    return description ?? 'Unknown file';
  }

  String get displayType {
    switch (type.toLowerCase()) {
      case 'receipt':
        return 'Receipt';
      case 'invoice':
        return 'Invoice';
      case 'ticket':
        return 'Ticket';
      case 'photo':
        return 'Photo';
      case 'document':
        return 'Document';
      default:
        return type;
    }
  }

  bool get isImage {
    if (url == null) return false;
    final extension = url!.toLowerCase();
    return extension.endsWith('.jpg') ||
        extension.endsWith('.jpeg') ||
        extension.endsWith('.png') ||
        extension.endsWith('.gif') ||
        extension.endsWith('.webp') ||
        extension.endsWith('.heic');
  }

  bool get isPdf {
    if (url == null) return false;
    return url!.toLowerCase().endsWith('.pdf');
  }

  String get formattedAmount {
    if (amount == null) return '';
    return 'NOK ${amount!.toStringAsFixed(2)}';
  }

  @override
  List<Object?> get props => [
    id,
    date,
    url,
    amount,
    description,
    type,
    costType,
    createdAt,
    updatedAt,
  ];
}
