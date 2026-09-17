import 'package:biso/providers/member_pass/scan_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('memberKey', () {
    test('v1 and a1 drop the prefix and the last two parts', () {
      expect(memberKey('v1.user1.59654564.sig'), 'user1');
      expect(memberKey('a1.user1.20260917.sig'), 'user1');
      expect(memberKey('v1.user.with.dots.1.sig'), 'user.with.dots');
    });

    test('g1 drops the prefix and the last part', () {
      expect(memberKey('g1.user1.123456'), 'user1');
      expect(memberKey('g1.a.b.123456'), 'a.b');
    });

    test('the same member has one key across pass kinds', () {
      expect(memberKey('v1.u.1.s'), memberKey('g1.u.123456'));
      expect(memberKey('a1.u.20260917.s'), memberKey('g1.u.123456'));
    });

    test('anything else keys on the whole string', () {
      expect(memberKey('https://example.com'), 'https://example.com');
      expect(memberKey('v1.too.short'), 'v1.too.short');
      expect(memberKey('g1.short'), 'g1.short');
      expect(memberKey(''), '');
    });
  });

  group('ScanGate', () {
    const a1 = 'v1.alice.1.s';
    const a2 = 'v1.alice.2.s';
    const b = 'g1.bob.123456';

    test('admits a new member and then holds until finished', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      expect(gate.busy, isTrue);
      expect(gate.admit(b, 100), isFalse);
      gate.finish();
      expect(gate.busy, isFalse);
    });

    test('ignores the same member for 20 s, even with a new code', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      gate.finish();
      expect(gate.admit(a2, 19999), isFalse);
    });

    test('each read restarts the window', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      gate.finish();
      expect(gate.admit(a1, 15000), isFalse);
      expect(gate.admit(a1, 30000), isFalse);
      expect(gate.admit(a1, 49999), isFalse);
      expect(gate.admit(a1, 70000), isTrue);
    });

    test('reads of the member being checked keep their window alive', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      expect(gate.admit(a1, 15000), isFalse); // still busy
      gate.finish();
      expect(gate.admit(a1, 30000), isFalse); // 15 s since the last read
    });

    test('someone glimpsed while busy can be checked right after', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      expect(gate.admit(b, 500), isFalse);
      gate.finish();
      expect(gate.admit(b, 3000), isTrue);
    });

    test('forgets members after the window', () {
      final gate = ScanGate();
      expect(gate.admit(a1, 0), isTrue);
      gate.finish();
      expect(gate.admit(a1, 20000), isTrue);
    });
  });
}
