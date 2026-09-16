import 'dart:io';

import 'package:biso/data/services/expense_intake_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseIntakeService', () {
    late Directory tempDir;
    late ExpenseIntakeService service;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
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
      expect(ExpenseIntakeService.isSupportedExtension('receipt.jpg'), isTrue);
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

    // The server (and CreateExpenseScreen's own OCR gate) only ever accepts
    // PDF, PNG and JPEG; a HEIC/WebP photo shared straight from iOS Photos
    // must be refused here, at the door, rather than admitted into a batch
    // that CreateExpenseScreen then has to reject file-by-file.
    test('refuses HEIC, HEIF and WebP — the server does not accept them', () {
      expect(
        ExpenseIntakeService.isSupportedExtension('receipt.heic'),
        isFalse,
      );
      expect(
        ExpenseIntakeService.isSupportedExtension('receipt.heif'),
        isFalse,
      );
      expect(
        ExpenseIntakeService.isSupportedExtension('receipt.webp'),
        isFalse,
      );
      expect(ExpenseIntakeService.isSupportedMimeType('image/heic'), isFalse);
      expect(ExpenseIntakeService.isSupportedMimeType('image/heif'), isFalse);
      expect(ExpenseIntakeService.isSupportedMimeType('image/webp'), isFalse);
    });

    // The share extensions rename files to these exact extensions before
    // handing them over — a JPEG iOS calls `.jpe` arrives as `.jpg` — because
    // this is the list the app checks, and a file it refuses here would be
    // one the extension had already told the student it added.
    test('accepts exactly jpg, jpeg, png and pdf as extensions', () {
      expect(ExpenseIntakeService.supportedExtensions, {
        'jpeg',
        'jpg',
        'pdf',
        'png',
      });
      expect(ExpenseIntakeService.isSupportedExtension('scan.jpe'), isFalse);
      expect(ExpenseIntakeService.isSupportedExtension('scan.JPG'), isTrue);
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

    // The whole point of the finding this pins: a HEIC receipt used to be
    // copied in by the share extension, dropped here, and logged. The
    // student saw "Receipt added" and then nothing at all.
    test('refuses a HEIC share out loud instead of dropping it', () async {
      final photo = File('${tempDir.path}/IMG_0001.heic');
      await photo.writeAsBytes([1, 2, 3]);

      await expectLater(
        service.createBatchFromFiles([photo], source: 'ios-share-extension'),
        throwsA(
          isA<ExpenseIntakeException>().having(
            (error) => error.message,
            'message',
            allOf(contains('PDF'), contains('PNG'), contains('JPEG')),
          ),
        ),
      );
    });

    test(
      'a mixed share keeps what it can and names what it could not',
      () async {
        final receipt = File('${tempDir.path}/receipt.pdf');
        await receipt.writeAsBytes([1, 2, 3]);
        final photo = File('${tempDir.path}/IMG_0001.heic');
        await photo.writeAsBytes([1, 2, 3]);

        final batch = await service.createBatchFromFiles([
          receipt,
          photo,
        ], source: 'test');

        expect(batch.files, hasLength(1));
        expect(batch.skippedFileNames, ['IMG_0001.heic']);
        // And it survives the manifest, so the screen importing the batch
        // later can still tell the student what was left behind.
        final loaded = await service.getBatch(batch.batchId);
        expect(loaded!.skippedFileNames, ['IMG_0001.heic']);
      },
    );

    test(
      'a file over the size limit is named too, not just discarded',
      () async {
        final huge = File('${tempDir.path}/receipt.pdf');
        await huge.writeAsBytes(
          List<int>.filled(ExpenseIntakeService.maxFileSizeBytes + 1, 0),
        );
        final small = File('${tempDir.path}/small.png');
        await small.writeAsBytes([1, 2, 3]);

        final batch = await service.createBatchFromFiles([
          huge,
          small,
        ], source: 'test');

        expect(batch.files.single.fileName, 'small.png');
        expect(batch.skippedFileNames, ['receipt.pdf']);
      },
    );
    // End to end over the Dart half of the share path: the native side has
    // already copied the file in and told the student "Receipt added", so
    // the app either says why it cannot take it or the receipt is simply
    // gone. It used to be gone.
    test('a share it cannot take opens the screen with the reason', () async {
      final routes = <String>[];
      final photo = File('${tempDir.path}/IMG_0001.heic');
      await photo.writeAsBytes([1, 2, 3]);
      _mockNativeShare([photo.path]);
      addTearDown(_clearNativeShare);

      await ExpenseIntakeService(
        rootDirectory: tempDir,
        openRoute: routes.add,
      ).handlePendingNativeEntrypoints();

      expect(routes, hasLength(1));
      final query = Uri.parse(routes.single).queryParameters;
      expect(query['batch'], isNull);
      expect(
        query['intakeError'],
        ExpenseIntakeService.unsupportedFilesMessage,
      );
      expect(query['intakeErrorId'], isNotNull);
    });

    test('a second refusal for the same reason is a new refusal', () async {
      // The form may still be open from the first one, showing the same
      // words; only the id tells the screen there is something new to show.
      final routes = <String>[];
      final service = ExpenseIntakeService(
        rootDirectory: tempDir,
        openRoute: routes.add,
      );
      final photo = File('${tempDir.path}/IMG_0001.heic');
      await photo.writeAsBytes([1, 2, 3]);
      addTearDown(_clearNativeShare);

      _mockNativeShare([photo.path]);
      await service.handlePendingNativeEntrypoints();
      _mockNativeShare([photo.path]);
      await service.handlePendingNativeEntrypoints();

      final queries = [
        for (final route in routes) Uri.parse(route).queryParameters,
      ];
      expect(queries, hasLength(2));
      expect(queries[0]['intakeError'], queries[1]['intakeError']);
      expect(queries[0]['intakeErrorId'], isNot(queries[1]['intakeErrorId']));
    });

    test('a share it can take opens that batch', () async {
      final receipt = File('${tempDir.path}/receipt.pdf');
      await receipt.writeAsBytes([1, 2, 3]);
      final routes = <String>[];
      _mockNativeShare([receipt.path]);
      addTearDown(_clearNativeShare);

      await ExpenseIntakeService(
        rootDirectory: tempDir,
        openRoute: routes.add,
      ).handlePendingNativeEntrypoints();

      final query = Uri.parse(routes.single).queryParameters;
      expect(query['batch'], isNotNull);
      expect(query['intakeError'], isNull);
    });
  });
}

const _channel = MethodChannel('biso/expense_intake');

/// Stands in for the share extension having left files in the app group.
void _mockNativeShare(List<String> paths) {
  var taken = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'takePendingExpenseIntakeBatches':
            if (taken) return <dynamic>[];
            taken = true;
            return <dynamic>[
              {
                'source': 'ios-share-extension',
                'files': [
                  for (final path in paths) {'filePath': path},
                ],
              },
            ];
          case 'takePendingShortcutDeepLink':
            return null;
          default:
            return null;
        }
      });
}

void _clearNativeShare() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}
