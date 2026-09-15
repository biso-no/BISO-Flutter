/// Department names are synced from 24SevenOffice, where they carry a campus
/// code (`OSL`, `BRG`, `TRD`, `STV`). Students already filter by campus, so
/// the code is noise in the app.
final _campusCodePrefix = RegExp(r'^(?:OSL|BRG|TRD|STV)\s+(?=\S)');

String displayDepartmentName(String name) =>
    name.replaceFirst(_campusCodePrefix, '');
