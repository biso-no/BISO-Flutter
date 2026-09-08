import 'package:biso/data/models/campus_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CampusStats', () {
    test('defaults every counter to zero', () {
      const s = CampusStats();
      expect(s.activeEvents, 0);
      expect(s.availableJobs, 0);
    });

    test('carries real counts when supplied', () {
      const s = CampusStats(activeEvents: 3, availableJobs: 16);
      expect(s.activeEvents, 3);
      expect(s.availableJobs, 16);
    });

    test('two stats differing only in availableJobs are not equal', () {
      expect(
        const CampusStats(activeEvents: 1, availableJobs: 2),
        isNot(equals(const CampusStats(activeEvents: 1, availableJobs: 3))),
      );
    });
  });
}
