import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/update_decision.dart';
import 'package:biso/data/models/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 12);

  UpdatePrompt decide(
    String installed,
    UpdatePolicy policy, {
    AppConfigSource source = AppConfigSource.network,
    UpdateSnooze? snooze,
  }) => decideUpdate(
    installedVersion: installed,
    policy: policy,
    source: source,
    snooze: snooze,
    now: now,
  );

  test('below the minimum is required', () {
    expect(
      decide('2.3.2', const UpdatePolicy(minimum: '2.4.0')),
      UpdatePrompt.required,
    );
  });

  test('at the minimum is fine', () {
    expect(
      decide('2.4.0', const UpdatePolicy(minimum: '2.4.0')),
      UpdatePrompt.none,
    );
  });

  test('required wins over a snooze', () {
    expect(
      decide(
        '2.3.2',
        const UpdatePolicy(minimum: '2.4.0', recommended: '2.4.0'),
        snooze: UpdateSnooze(version: '2.4.0', dismissedAt: now),
      ),
      UpdatePrompt.required,
    );
  });

  test('below the recommended version is recommended', () {
    expect(
      decide('2.4.0', const UpdatePolicy(recommended: '2.4.1')),
      UpdatePrompt.recommended,
    );
  });

  test('a snooze hides the same version for 3 days, then expires', () {
    const policy = UpdatePolicy(recommended: '2.4.1');
    expect(
      decide(
        '2.4.0',
        policy,
        snooze: UpdateSnooze(
          version: '2.4.1',
          dismissedAt: now.subtract(const Duration(days: 2)),
        ),
      ),
      UpdatePrompt.none,
    );
    expect(
      decide(
        '2.4.0',
        policy,
        snooze: UpdateSnooze(
          version: '2.4.1',
          dismissedAt: now.subtract(const Duration(days: 3, minutes: 1)),
        ),
      ),
      UpdatePrompt.recommended,
    );
  });

  test('a snooze for an older recommendation does not hide a newer one', () {
    expect(
      decide(
        '2.4.0',
        const UpdatePolicy(recommended: '2.4.2'),
        snooze: UpdateSnooze(version: '2.4.1', dismissedAt: now),
      ),
      UpdatePrompt.recommended,
    );
  });

  test('a cached answer never prompts', () {
    expect(
      decide(
        '1.0.0',
        const UpdatePolicy(minimum: '2.4.0'),
        source: AppConfigSource.cache,
      ),
      UpdatePrompt.none,
    );
  });

  test('an unparseable installed or server version never prompts', () {
    expect(
      decide('2.2.9-beta', const UpdatePolicy(minimum: '9.0.0')),
      UpdatePrompt.none,
    );
    expect(decide('', const UpdatePolicy(minimum: '9.0.0')), UpdatePrompt.none);
    expect(
      decide('2.2.9', const UpdatePolicy(minimum: 'soon')),
      UpdatePrompt.none,
    );
  });
}
