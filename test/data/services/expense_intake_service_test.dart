import 'dart:io';

import 'package:biso/data/services/expense_intake_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseIntakeService', () {
    late Directory tempDir;
    late ExpenseIntakeService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('expense_intake_test_');
      service = ExpenseIntakeService(rootDirectory: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('accepts supported receipt file extensions and MIME types', () {
      expect(ExpenseIntakeService.isSupportedExtension('receipt.pdf'), isTrue);
      expect(ExpenseIntakeService.isSupportedExtension('receipt.heic'), isTrue);
      expect(ExpenseIntakeService.isSupportedMimeType('image/png'), isTrue);
      expect(
        ExpenseIntakeService.isSupportedMimeType('application/pdf'),
        isTrue,
      );
    });

    test('rejects unsupported file extensions and MIME types', () {
      expect(ExpenseIntakeService.isSupportedExtension('notes.txt'), isFalse);
      expect(ExpenseIntakeService.isSupportedMimeType('text/plain'), isFalse);
    });

    test('creates and reads a batch manifest for supported files', () async {
      final receipt = File('${tempDir.path}/receipt.pdf');
      await receipt.writeAsBytes([1, 2, 3]);

      final batch = await service.createBatchFromFiles([
        receipt,
      ], source: 'test');
      final loaded = await service.getBatch(batch.batchId);

      expect(loaded, isNotNull);
      expect(loaded!.source, 'test');
      expect(loaded.files, hasLength(1));
      expect(loaded.files.first.fileName, 'receipt.pdf');
      expect(await loaded.files.first.file.exists(), isTrue);
    });

    test('deletes batch files and manifest', () async {
      final receipt = File('${tempDir.path}/receipt.png');
      await receipt.writeAsBytes([1, 2, 3]);
      final batch = await service.createBatchFromFiles([
        receipt,
      ], source: 'test');

      await service.deleteBatch(batch.batchId);

      expect(await service.getBatch(batch.batchId), isNull);
    });
  });
}
