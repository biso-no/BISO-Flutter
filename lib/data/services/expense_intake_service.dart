import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/print_migration.dart';
import '../models/expense_intake_models.dart';
import 'deep_link_service.dart';
import 'expense_api_client.dart';

class ExpenseIntakeException implements Exception {
  final String message;

  const ExpenseIntakeException(this.message);

  @override
  String toString() => message;
}

class ExpenseIntakeService {
  ExpenseIntakeService({Directory? rootDirectory})
    : _rootDirectoryOverride = rootDirectory;

  static final ExpenseIntakeService instance = ExpenseIntakeService();
  static const MethodChannel _channel = MethodChannel('biso/expense_intake');
  static const int maxFileSizeBytes = 10 * 1024 * 1024;
  static const String _manifestName = 'batch.json';

  static const Set<String> supportedMimeTypes = {
    'application/pdf',
    'image/heic',
    'image/heif',
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  static const Set<String> supportedExtensions = {
    'heic',
    'heif',
    'jpeg',
    'jpg',
    'pdf',
    'png',
    'webp',
  };

  final Directory? _rootDirectoryOverride;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'expenseIntakeReceived' ||
          call.method == 'nativeEntrypointReceived') {
        await handlePendingNativeEntrypoints();
      }
    });
  }

  Future<void> handlePendingNativeEntrypoints() async {
    final batches = await importNativeBatches(openLatest: true);
    if (batches.isEmpty) {
      await _openPendingNativeShortcut();
    }
  }

  Future<List<ExpenseIntakeBatch>> importNativeBatches({
    bool openLatest = false,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'takePendingExpenseIntakeBatches',
      );
      if (raw == null || raw.isEmpty) return const [];

      final imported = <ExpenseIntakeBatch>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final source = (item['source'] ?? 'native-share').toString();
        final paths = _pathsFromNativeItem(item);
        if (paths.isEmpty) continue;
        imported.add(await createBatchFromPaths(paths, source: source));
      }

      if (openLatest && imported.isNotEmpty) {
        _openBatch(imported.last);
      }
      return imported;
    } on MissingPluginException {
      return const [];
    } catch (e) {
      logPrint('Expense intake native import failed: $e');
      return const [];
    }
  }

  Future<ExpenseIntakeBatch> createBatchFromPaths(
    List<String> paths, {
    required String source,
  }) async {
    final files = paths
        .where((path) => path.trim().isNotEmpty)
        .map((path) => File(path))
        .toList();
    return createBatchFromFiles(files, source: source);
  }

  Future<ExpenseIntakeBatch> createBatchFromFiles(
    List<File> files, {
    required String source,
  }) async {
    if (files.isEmpty) {
      throw const ExpenseIntakeException('No files were shared with BISO.');
    }

    final batchId = _newBatchId();
    final batchDirectory = Directory(
      '${(await _rootDirectory()).path}/$batchId',
    );
    await batchDirectory.create(recursive: true);

    final intakeFiles = <ExpenseIntakeFile>[];
    for (final file in files) {
      if (!await file.exists()) continue;
      final size = await file.length();
      final mimeType = normalizeMimeType(file.path);
      if (!isSupportedMimeType(mimeType) || !isSupportedExtension(file.path)) {
        continue;
      }
      if (size > maxFileSizeBytes) continue;

      final destinationName = _uniqueFileName(
        batchDirectory,
        _safeFileName(file.uri.pathSegments.last),
      );
      final copied = await file.copy('${batchDirectory.path}/$destinationName');
      intakeFiles.add(
        ExpenseIntakeFile(
          fileName: destinationName,
          filePath: copied.path,
          mimeType: mimeType,
          sizeBytes: size,
        ),
      );
    }

    if (intakeFiles.isEmpty) {
      await batchDirectory.delete(recursive: true);
      throw const ExpenseIntakeException(
        'No supported receipt files were shared with BISO.',
      );
    }

    final batch = ExpenseIntakeBatch(
      batchId: batchId,
      source: source,
      createdAt: DateTime.now(),
      files: intakeFiles,
    );
    await _writeManifest(batchDirectory, batch);
    return batch;
  }

  Future<ExpenseIntakeBatch?> getBatch(String batchId) async {
    if (batchId.trim().isEmpty) return null;
    final manifest = File(
      '${(await _rootDirectory()).path}/$batchId/$_manifestName',
    );
    if (!await manifest.exists()) return null;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    final batch = ExpenseIntakeBatch.fromMap(decoded);
    final existingFiles = <ExpenseIntakeFile>[];
    for (final file in batch.files) {
      if (await file.file.exists()) existingFiles.add(file);
    }
    return ExpenseIntakeBatch(
      batchId: batch.batchId,
      source: batch.source,
      createdAt: batch.createdAt,
      files: existingFiles,
    );
  }

  Future<List<ExpenseIntakeBatch>> pendingBatches() async {
    final root = await _rootDirectory();
    if (!await root.exists()) return const [];
    final batches = <ExpenseIntakeBatch>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final batch = await getBatch(entity.uri.pathSegments.last);
      if (batch != null && !batch.isEmpty) batches.add(batch);
    }
    batches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return batches;
  }

  Future<void> deleteBatch(String batchId) async {
    if (batchId.trim().isEmpty) return;
    final directory = Directory('${(await _rootDirectory()).path}/$batchId');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static bool isSupportedMimeType(String mimeType) {
    return supportedMimeTypes.contains(mimeType.toLowerCase());
  }

  static bool isSupportedExtension(String path) {
    final segments = path.split('.');
    if (segments.length < 2) return false;
    return supportedExtensions.contains(segments.last.toLowerCase());
  }

  static String normalizeMimeType(String path) {
    final mimeType = detectExpenseMimeType(path).toLowerCase();
    return mimeType == 'image/jpg' ? 'image/jpeg' : mimeType;
  }

  Future<Directory> _rootDirectory() async {
    if (_rootDirectoryOverride != null) {
      await _rootDirectoryOverride.create(recursive: true);
      return _rootDirectoryOverride;
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/expense_intake/batches');
    await root.create(recursive: true);
    return root;
  }

  Future<void> _writeManifest(
    Directory batchDirectory,
    ExpenseIntakeBatch batch,
  ) async {
    final manifest = File('${batchDirectory.path}/$_manifestName');
    await manifest.writeAsString(jsonEncode(batch.toMap()));
  }

  List<String> _pathsFromNativeItem(Map<dynamic, dynamic> item) {
    final files = item['files'];
    if (files is List) {
      return files
          .map((file) {
            if (file is String) return file;
            if (file is Map) {
              return (file['filePath'] ?? file['path']).toString();
            }
            return '';
          })
          .where((path) => path.isNotEmpty)
          .toList();
    }
    final paths = item['paths'];
    if (paths is List) {
      return paths
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
    }
    return const [];
  }

  void _openBatch(ExpenseIntakeBatch batch) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    context.go(
      '/explore/expenses/new?batch=${Uri.encodeComponent(batch.batchId)}',
    );
  }

  Future<void> _openPendingNativeShortcut() async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'takePendingShortcutDeepLink',
      );
      if (raw == null || raw.isEmpty) return;
      final uri = Uri.tryParse(raw);
      if (uri == null) return;
      DeepLinkService().handleDeepLink(uri);
    } on MissingPluginException {
      return;
    } catch (e) {
      logPrint('Native shortcut routing failed: $e');
    }
  }

  String _newBatchId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'expense_intake_${now}_$random';
  }

  String _safeFileName(String input) {
    final fallback = 'receipt';
    final cleaned = input
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
    return cleaned;
  }

  String _uniqueFileName(Directory directory, String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var candidate = fileName;
    var index = 1;
    while (File('${directory.path}/$candidate').existsSync()) {
      candidate = '${base}_$index$extension';
      index += 1;
    }
    return candidate;
  }
}
