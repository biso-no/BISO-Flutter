import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMemberPassApi api;
  late int now;

  setUp(() {
    api = FakeMemberPassApi();
    now = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;
  });

  ProviderContainer container({String? userId = 'u1'}) {
    final c = ProviderContainer(
      overrides: [
        memberPassApiProvider.overrideWithValue(api),
        memberPassClockProvider.overrideWithValue(() => now),
        membershipUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const access = ScannerAccess(campusId: '1', dayColor: testDayColor);

  test('a 200 grants access', () async {
    api.onFetchScannerAccess = () => access;
    final c = container();
    expect(
      await c.read(scannerAccessProvider.future),
      const ScannerGranted(access),
    );
  });

  test('maps each refusal', () async {
    for (final (status, expected) in [
      (401, const ScannerSignedOut()),
      (403, const ScannerDenied()),
      (404, const ScannerDenied()),
      (503, const ScannerNotConfigured()),
      (500, const ScannerCheckFailed()),
      (null, const ScannerCheckFailed()),
    ]) {
      api.onFetchScannerAccess = () =>
          throw MemberPassApiException('x', statusCode: status);
      final c = container();
      expect(
        await c.read(scannerAccessProvider.future),
        expected,
        reason: '$status',
      );
    }
  });

  test('without a user it is signed out and asks nobody', () async {
    final c = container(userId: null);
    expect(
      await c.read(scannerAccessProvider.future),
      const ScannerSignedOut(),
    );
    expect(api.scannerAccessCalls, 0);
  });

  test('a recent answer is reused for five minutes', () async {
    api.onFetchScannerAccess = () => access;
    final c = container();
    await c.read(scannerAccessProvider.future);

    now += const Duration(minutes: 4, seconds: 59).inMilliseconds;
    await c.read(scannerAccessProvider.notifier).ensureFresh();
    expect(api.scannerAccessCalls, 1);

    now += const Duration(seconds: 1).inMilliseconds;
    await c.read(scannerAccessProvider.notifier).ensureFresh();
    expect(api.scannerAccessCalls, 2);
  });

  test('force always asks and keeps the old answer while it does', () async {
    api.onFetchScannerAccess = () => access;
    final c = container();
    await c.read(scannerAccessProvider.future);

    api.onFetchScannerAccess = () =>
        throw const MemberPassApiException('not_scanner', statusCode: 403);
    final refresh = c
        .read(scannerAccessProvider.notifier)
        .ensureFresh(force: true);
    expect(
      c.read(scannerAccessProvider).valueOrNull,
      const ScannerGranted(access),
    );
    await refresh;
    expect(api.scannerAccessCalls, 2);
    expect(c.read(scannerAccessProvider).valueOrNull, const ScannerDenied());
  });

  test('a failed check is retried at once', () async {
    api.onFetchScannerAccess = () =>
        throw const MemberPassApiException(MemberPassApiException.network);
    final c = container();
    await c.read(scannerAccessProvider.future);

    api.onFetchScannerAccess = () => access;
    await c.read(scannerAccessProvider.notifier).ensureFresh();
    expect(api.scannerAccessCalls, 2);
    expect(
      c.read(scannerAccessProvider).valueOrNull,
      const ScannerGranted(access),
    );
  });
}
