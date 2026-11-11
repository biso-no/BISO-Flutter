import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/job_application.dart';
import '../../data/models/job_model.dart';
import '../../data/services/job_service.dart';
import '../../data/services/recruitment_api_client.dart';
import '../auth/auth_provider.dart';
import '../ui/locale_provider.dart';

/// Injectable seam for tests (offline fakes).
final jobServiceProvider = Provider<JobService>((ref) => JobService());

final recruitmentApiClientProvider = Provider<RecruitmentApiClient>(
  (ref) => RecruitmentApiClient(),
);

/// One open vacancy by slug or row id, in the app's language; null when it
/// does not exist or has closed.
final jobDetailProvider = FutureProvider.autoDispose.family<JobModel?, String>((
  ref,
  idOrSlug,
) {
  final locale = ref.watch(localeProvider).languageCode;
  return ref.watch(jobServiceProvider).getJob(idOrSlug, locale: locale);
});

/// The signed-in student's applications, newest first. Read again for
/// whoever is signed in.
final myApplicationsProvider = FutureProvider.autoDispose<List<MyApplication>>((
  ref,
) {
  ref.watch(authStateProvider.select((state) => state.signedInUserId));
  return ref.watch(recruitmentApiClientProvider).listMine();
});

/// Lets the student pick one file for an application; null when they cancel.
typedef ApplicationDocumentPicker = Future<ApplicationDocument?> Function();

final applicationDocumentPickerProvider = Provider<ApplicationDocumentPicker>(
  (ref) => _pickPdf,
);

Future<ApplicationDocument?> _pickPdf() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file == null) return null;
  final path = file.path;
  // Mobile pickers copy the document to a local file. Anything without one
  // (the web) is read now, while the picker's handle is still valid.
  final bytes = path == null ? await file.readAsBytes() : null;
  final size = file.lengthSync() ?? await file.length() ?? bytes?.length;
  if (size == null) return null;
  return ApplicationDocument(
    name: file.name,
    size: size,
    path: path,
    bytes: bytes,
  );
}
