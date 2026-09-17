import 'dart:async';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/member_pass/scanner_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  const alice = 'v1.alice.1.sig';
  const bob = 'g1.bob.123456';

  late FakeMemberPassApi api;
  late List<ScanTone> haptics;
  late FixedScannerAccess access;

  setUp(() {
    api = FakeMemberPassApi()
      ..onScan = (_) =>
          const ScanOutcome(result: ScanResult.valid, name: 'Alice');
    haptics = [];
    access = FixedScannerAccess(grantedAccess);
  });

  ProviderContainer container(FakeAsync async) {
    final c = ProviderContainer(
      overrides: [
        memberPassApiProvider.overrideWithValue(api),
        memberPassClockProvider.overrideWithValue(
          () => async.elapsed.inMilliseconds,
        ),
        scanHapticsProvider.overrideWithValue(haptics.add),
        scannerAccessProvider.overrideWith(() => access),
      ],
    );
    addTearDown(c.dispose);
    c.listen(scannerControllerProvider, (_, _) {});
    return c;
  }

  ScannerController controller(ProviderContainer c) =>
      c.read(scannerControllerProvider.notifier);

  test('shows the result with haptics, then clears after 3 s', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected(alice);
      expect(c.read(scannerControllerProvider), const ScannerChecking());
      async.flushMicrotasks();

      expect(
        c.read(scannerControllerProvider),
        const ScannerResult(
          tone: ScanTone.green,
          message: ScanMessage.valid,
          name: 'Alice',
        ),
      );
      expect(haptics, [ScanTone.green]);
      expect(api.scanned, [alice]);

      async.elapse(const Duration(milliseconds: 2999));
      expect(c.read(scannerControllerProvider), isA<ScannerResult>());
      async.elapse(const Duration(milliseconds: 1));
      expect(c.read(scannerControllerProvider), const ScannerIdle());
    });
  });

  test('a tap clears the result early and the next person can scan', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected(alice);
      async.flushMicrotasks();
      controller(c).dismiss();
      expect(c.read(scannerControllerProvider), const ScannerIdle());

      controller(c).onDetected(bob);
      async.flushMicrotasks();
      expect(api.scanned, [alice, bob]);
    });
  });

  test('ignores the same member for 20 s after the result clears', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected(alice);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      controller(c).onDetected('v1.alice.2.sig');
      async.flushMicrotasks();
      expect(api.scanned, [alice]);

      async.elapse(const Duration(seconds: 21));
      controller(c).onDetected('v1.alice.3.sig');
      async.flushMicrotasks();
      expect(api.scanned, hasLength(2));
    });
  });

  test('ignores reads while a scan is in flight', () {
    fakeAsync((async) {
      final pending = Completer<ScanOutcome>();
      api.onScan = (_) => pending.future;
      final c = container(async);
      controller(c).onDetected(alice);
      controller(c).onDetected(bob);
      async.flushMicrotasks();
      expect(api.scanned, [alice]);
      pending.complete(const ScanOutcome(result: ScanResult.valid));
      async.flushMicrotasks();
    });
  });

  test('an overlong read is denied without asking the server', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected('x' * 257);
      async.flushMicrotasks();
      expect(api.scanned, isEmpty);
      expect(c.read(scannerControllerProvider), overlongCodeResult);
      expect(haptics, [ScanTone.red]);
    });
  });

  test('a padded code is sent trimmed', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected('  $alice  ');
      async.flushMicrotasks();
      expect(api.scanned, [alice]);
    });
  });

  test(
    'a code whose raw length is over 256 but trimmed length is not is sent',
    () {
      fakeAsync((async) {
        final code = 'x' * 256;
        final c = container(async);
        controller(c).onDetected('  $code  ');
        async.flushMicrotasks();
        expect(api.scanned, [code]);
      });
    },
  );

  test('an exactly-256-character trimmed code is sent', () {
    fakeAsync((async) {
      final code = 'x' * 256;
      final c = container(async);
      controller(c).onDetected(code);
      async.flushMicrotasks();
      expect(api.scanned, [code]);
    });
  });

  test('a whitespace-only read does nothing: no gate, no request', () {
    fakeAsync((async) {
      final c = container(async);
      controller(c).onDetected('   \n\t  ');
      async.flushMicrotasks();
      expect(api.scanned, isEmpty);
      expect(c.read(scannerControllerProvider), const ScannerIdle());
      expect(haptics, isEmpty);
    });
  });

  test('a 403 closes the scanner and re-checks access', () {
    fakeAsync((async) {
      api.onScan = (_) =>
          throw const MemberPassApiException('not_scanner', statusCode: 403);
      final c = container(async);
      c.listen(scannerAccessProvider, (_, _) {});
      async.flushMicrotasks();
      final buildsBefore = access.builds;

      controller(c).onDetected(alice);
      async.flushMicrotasks();
      // The invalidation's rebuild runs on a zero-length timer.
      async.elapse(Duration.zero);

      expect(
        c.read(scannerControllerProvider),
        const ScannerClosed(ScannerCloseReason.noAccess),
      );
      expect(haptics, isEmpty);
      // Riverpod 2.6 keeps the notifier instance across an invalidation and
      // only re-runs build().
      expect(access.builds, greaterThan(buildsBefore));
    });
  });

  test('a 401 closes the scanner as signed out', () {
    fakeAsync((async) {
      api.onScan = (_) => throw const MemberPassApiException(
        'not_authenticated',
        statusCode: 401,
      );
      final c = container(async);
      controller(c).onDetected(alice);
      async.flushMicrotasks();
      expect(
        c.read(scannerControllerProvider),
        const ScannerClosed(ScannerCloseReason.signedOut),
      );
    });
  });

  test('a network error shows the grey result', () {
    fakeAsync((async) {
      api.onScan = (_) =>
          throw const MemberPassApiException(MemberPassApiException.network);
      final c = container(async);
      controller(c).onDetected(alice);
      async.flushMicrotasks();
      expect(
        (c.read(scannerControllerProvider) as ScannerResult).tone,
        ScanTone.grey,
      );
    });
  });
}
