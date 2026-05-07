import 'dart:io';

class ExpenseIntakeFile {
  final String fileName;
  final String filePath;
  final String mimeType;
  final int sizeBytes;

  const ExpenseIntakeFile({
    required this.fileName,
    required this.filePath,
    required this.mimeType,
    required this.sizeBytes,
  });

  File get file => File(filePath);

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    };
  }

  factory ExpenseIntakeFile.fromMap(Map<String, dynamic> map) {
    return ExpenseIntakeFile(
      fileName: (map['fileName'] ?? '').toString(),
      filePath: (map['filePath'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'application/octet-stream').toString(),
      sizeBytes: _intFrom(map['sizeBytes']),
    );
  }
}

class ExpenseIntakeBatch {
  final String batchId;
  final String source;
  final DateTime createdAt;
  final List<ExpenseIntakeFile> files;

  const ExpenseIntakeBatch({
    required this.batchId,
    required this.source,
    required this.createdAt,
    required this.files,
  });

  bool get isEmpty => files.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'batchId': batchId,
      'source': source,
      'createdAt': createdAt.toIso8601String(),
      'files': files.map((file) => file.toMap()).toList(),
    };
  }

  factory ExpenseIntakeBatch.fromMap(Map<String, dynamic> map) {
    final files = map['files'] is List
        ? (map['files'] as List)
              .whereType<Map>()
              .map((file) => ExpenseIntakeFile.fromMap(file.cast()))
              .where((file) => file.filePath.isNotEmpty)
              .toList()
        : <ExpenseIntakeFile>[];
    return ExpenseIntakeBatch(
      batchId: (map['batchId'] ?? '').toString(),
      source: (map['source'] ?? 'unknown').toString(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      files: files,
    );
  }
}

int _intFrom(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
