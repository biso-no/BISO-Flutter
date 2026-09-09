import '../constants/app_constants.dart';

/// Normalizes an Appwrite image value into a usable URL.
///
/// Live data stores either a bare file id or an already-complete view URL in
/// the same column, so both forms must be accepted.
String? appwriteImageUrl(Object? value, {String bucketId = 'media'}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

  return '${AppConstants.appwriteEndpoint}/storage/buckets/$bucketId'
      '/files/$raw/view?project=${AppConstants.appwriteProjectId}';
}

/// Normalizes a list column such as `images`, dropping unusable entries.
List<String> appwriteImageUrls(Object? value, {String bucketId = 'media'}) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => appwriteImageUrl(e, bucketId: bucketId))
      .whereType<String>()
      .toList(growable: false);
}
