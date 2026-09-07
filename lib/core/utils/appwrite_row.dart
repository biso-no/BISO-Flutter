import 'package:appwrite/models.dart';

/// Flattens an Appwrite [Row] into the map shape our `fromMap`/
/// `fromAppwriteRow` model factories expect: the row's `data` merged with
/// its `$id`, `$createdAt` and `$updatedAt` system fields.
///
/// The system fields are merged in *after* `row.data` so they always win —
/// `data` should never contain these keys, but this keeps the mapping
/// unambiguous if it ever does.
Map<String, dynamic> rowData(Row row) => {
  ...row.data,
  r'$id': row.$id,
  r'$createdAt': row.$createdAt,
  r'$updatedAt': row.$updatedAt,
};
