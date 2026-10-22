import 'package:biso/core/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses major.minor.patch only', () {
    expect(AppVersion.tryParse('2.4.0'), isNotNull);
    for (final v in ['2.4', '2.4.0+93', '2.2.9-beta', '', null, 'v2.4.0']) {
      expect(AppVersion.tryParse(v), isNull, reason: '$v');
    }
  });

  test('compares numerically', () {
    expect(
      AppVersion.tryParse('2.9.0')! < AppVersion.tryParse('2.10.0')!,
      isTrue,
    );
  });
}
