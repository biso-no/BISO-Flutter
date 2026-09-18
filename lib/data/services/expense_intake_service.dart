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
  ExpenseIntakeService({
    Directory? rootDirectory,
    void Function(String route)? openRoute,
  }) : _rootDirectoryOverride = rootDirectory,
       _openRoute = openRoute;

  /// `CreateExpenseScreen` reads this singleton directly rather than through
  /// Riverpod, and the default instance resolves its storage root through
  /// `path_provider`, which has no test double.
  static final ExpenseIntakeService instance = ExpenseIntakeService();
  static const MethodChannel _channel = MethodChannel('biso/expense_intake');
  static const int maxFileSizeBytes = 10 * 1024 * 1024;
  static const String _manifestName = 'batch.json';

  static const Set<String> supportedMimeTypes = {
    'application/pdf',
    'image/jpeg',
    'image/jpg',
    'image/png',
  };

  static const Set<String> supportedExtensions = {'jpeg', 'jpg', 'pdf', 'png'};

  /// What the app can take, in the words the student reads. The API refuses
  /// anything else, and the in-app camera and gallery picker re-encode to
  /// JPEG — so an iPhone's HEIC photo still gets in, just through the app
  /// rather than through the share sheet.
  static const String unsupportedFilesMessage =
      'BISO could not add those files. Receipts must be PDF, PNG or JPEG '
      'files of 10 MB or less. Add the photo from inside the app and BISO '
      'converts it for you.';

  /// The same, for a share where only some of the files had to be left out.
  static String skippedFilesMessage(List<String> fileNames) =>
      'Not added: ${fileNames.join(', ')}. Receipts must be PDF, PNG or '
      'JPEG files of 10 MB or less. Add the photo from inside the app and '
      'BISO converts it for you.';

  final Directory? _rootDirectoryOverride;

  /// Where this service sends the student. The default goes through the
  /// app's navigator; a test passes its own to watch where a share ends up.
  final void Function(String route)? _openRoute;

  /// Refusals routed so far, which makes each one's id unique.
  int _refusals = 0;
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
    final result = await _importNativeBatches();
    if (result.batches.isNotEmpty) {
      _openBatch(result.batches.last);
      return;
    }
    final refusal = result.refusal;
    if (refusal != null) {
      _openIntakeError(refusal);
      return;
    }
    await _openPendingNativeShortcut();
  }

  Future<List<ExpenseIntakeBatch>> importNativeBatches({
    bool openLatest = false,
  }) async {
    final result = await _importNativeBatches();
    if (!openLatest) return result.batches;
    if (result.batches.isNotEmpty) {
      _openBatch(result.batches.last);
    } else if (result.refusal != null) {
      _openIntakeError(result.refusal!);
    }
    return result.batches;
  }

  /// Imports whatever the native share sheet left for us, and reports a
  /// share it had to refuse outright rather than only logging one.
  ///
  /// The native side has already told the student the receipt was added by
  /// this point, so a file dropped silently here is a receipt that
  /// disappears: they see a share sheet say yes, then an empty
  /// reimbursement. The refusal travels back up so a screen can show it.
  Future<({List<ExpenseIntakeBatch> batches, String? refusal})>
  _importNativeBatches() async {
    final imported = <ExpenseIntakeBatch>[];
    String? refusal;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'takePendingExpenseIntakeBatches',
      );
      if (raw == null || raw.isEmpty) return (batches: imported, refusal: null);

      for (final item in raw) {
        if (item is! Map) continue;
        final source = (item['source'] ?? 'native-share').toString();
        final paths = _pathsFromNativeItem(item);
        if (paths.isEmpty) continue;
        try {
          imported.add(await createBatchFromPaths(paths, source: source));
        } on ExpenseIntakeException catch (e) {
          refusal = e.message;
        }
      }
      return (batches: imported, refusal: refusal);
    } on MissingPluginException {
      return (batches: imported, refusal: null);
    } catch (e) {
      logPrint('Expense intake native import failed: $e');
      return (batches: imported, refusal: refusal);
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
    final skipped = <String>[];
    for (final file in files) {
      final sharedName = file.uri.pathSegments.last;
      if (!await file.exists()) continue;
      final size = await file.length();
      final mimeType = normalizeMimeType(file.path);
      if (!isSupportedMimeType(mimeType) || !isSupportedExtension(file.path)) {
        skipped.add(sharedName);
        continue;
      }
      if (size > maxFileSizeBytes) {
        skipped.add(sharedName);
        continue;
      }

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
      throw const ExpenseIntakeException(unsupportedFilesMessage);
    }

    final batch = ExpenseIntakeBatch(
      batchId: batchId,
      source: source,
      createdAt: DateTime.now(),
      files: intakeFiles,
      skippedFileNames: skipped,
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
      skippedFileNames: batch.skippedFileNames,
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
    _go('/explore/expenses/new?batch=${Uri.encodeComponent(batch.batchId)}');
  }

  /// Opens the reimbursement screen carrying the reason a share was refused,
  /// so the student reads it where they expected their receipt to be.
  ///
  /// Each refusal carries its own id: the screen may already be open, and a
  /// second share refused for the same reason must not look like the first.
  void _openIntakeError(String message) {
    _refusals++;
    _go(
      '/explore/expenses/new'
      '?intakeError=${Uri.encodeComponent(message)}&intakeErrorId=$_refusals',
    );
  }

  void _go(String route) {
    final openRoute = _openRoute;
    if (openRoute != null) {
      openRoute(route);
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) {
      logPrint('Expense intake had nowhere to open $route');
      return;
    }
    context.go(route);
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
