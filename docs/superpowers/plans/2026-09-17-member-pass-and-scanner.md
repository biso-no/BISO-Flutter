# Member Pass and Membership Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Members show a live, server-signed, rotating pass from Profile, and can add it to Apple or
Google Wallet. People with a scanner grant check passes from Explore. The old token pass and
controller mode are removed.

**Architecture:**
- **Pure rule classes:** `MemberPassSession` (slot, drift, refetch and retry rules), `ScanGate`
  (repeat filter) and `mapScanOutcome` (result display). They take `now` as an argument and are
  unit-tested without Flutter.
- **Riverpod notifiers:** thin notifiers own timers, app lifecycle, connectivity and I/O through a
  `MemberPassApi` interface. `MemberPassApiClient` is the real HTTP implementation; tests use
  `FakeMemberPassApi`.
- **iOS Wallet:** a `biso/wallet` method channel in `AppDelegate.swift`.

**Tech Stack:**
- Flutter 3.47 / Dart 3, Riverpod 2.6, go_router 16, `http`.
- Existing packages: `qr_flutter`, `mobile_scanner` 7, `flutter_svg`, `url_launcher`.
- New: `connectivity_plus`, `wakelock_plus`, `screen_brightness`, and `fake_async` (dev).

**Spec:** `docs/superpowers/specs/2026-09-17-member-pass-and-scanner-design.md`. Read it first.

## Global Constraints

- **Server decides everything:** no signing, secrets or membership logic on the device.
- **No client writes:** the client never writes `student_id` or membership data.
- **Nothing sensitive leaves memory:** codes, JWTs and scanned strings are never persisted and never
  passed to `AppLogger`, `logPrint`, `debugPrint` or `print`. Exception `toString()` values carry only
  a status and a server `error` token that matches `^[a-z_]{1,40}$`.
- **Backend:** base URL `AppConstants.apiBaseUrl` (`https://api.biso.no`). Every call sends
  `Authorization: Bearer <Appwrite JWT>` through `ApiJwtProvider` / `appwriteJwt`
  (`lib/data/services/api_auth.dart`).
- **Pass timing:** slot length 30 000 ms; refetch when fewer than 4 codes remain at or after the
  current slot; retry every 15 000 ms while offline or low.
- **Scanner:** repeat window 20 s; results auto-dismiss after 3 s; codes longer than 256 characters
  are denied locally.
- **Oslo time:** EU daylight-saving rule. Summer time runs from 01:00 UTC on the last Sunday of March
  to 01:00 UTC on the last Sunday of October.
- **Deploy-time 404s:** only `GET /api/member-pass` (→ `NoPass(unavailable)`) and
  `GET /api/member-pass/scanner` (→ not a scanner) treat 404 as "not deployed". On the wallet
  routes, 404 means `not_configured`.
- **Design system:**
  - Screens import `lib/presentation/widgets/biso/biso.dart` and use `BisoPalette`, `BisoAccent`
    and CupertinoIcons (no `Icons.`).
  - Museo styles (`display*`, `headlineLarge`, `headlineMedium`) use only `FontWeight.w300`.
  - Fixed pass and scanner colors live only in `lib/presentation/widgets/member_pass/pass_colors.dart`.
  - Every new widget or screen file is added to `migratedFiles` in
    `test/presentation/design_rules_test.dart`.
- **Localization:** English and Norwegian (`en`, `no`) through `AppLocalizations`
  (`lib/generated/l10n`). Regenerate with `flutter gen-l10n`; the generated files are committed.
- **Tests:** `flutter_test` with hand-rolled fakes, no mockito. Widget tests use
  `pumpBisoScreen` / `expectBuildsCleanly` from `test/helpers/biso_screen_harness.dart`.
  - **Never `pumpAndSettle`** on a screen that shows `PassCard`: the holographic band animates
    forever. Use `tester.pump(duration)`.
- **Baseline before this plan:** 828 tests pass, and `flutter analyze` reports 4 pre-existing infos
  (`app_logger.dart:224`, `validator_service.dart:20`, `settings_screen.dart:873` and `:874`).
  - Analyzer acceptance: no new issues. Task 17 deletes `validator_service.dart`, which removes one.
  - Run `flutter analyze` and `flutter test` as separate commands; the pre-existing infos make
    `flutter analyze` exit non-zero.
- **Formatting:** `dart format` every file you create or change. Check with
  `dart format --output=none --set-exit-if-changed <paths>`. If formatting an existing file
  rewrites lines you did not touch, keep only your own hunks (`git add -p`).
- **Commits:** end every message with these two lines:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f`.
  Commit subjects are plain sentences, in the style of recent history ("Add …", "Show …").

## File Map

| File | Responsibility |
|---|---|
| `lib/core/utils/oslo_time.dart` | Oslo wall-clock time and the HH:MM:SS formatter |
| `lib/data/models/member_pass.dart` | Pass, term, day color, wallet flags, scanner access and scan outcome models, with parsing |
| `lib/data/services/member_pass_api_client.dart` | `MemberPassApi` interface, `MemberPassApiException`, HTTP client |
| `lib/data/services/wallet_channel.dart` | Dart side of the `biso/wallet` channel |
| `lib/data/services/screen_presentation.dart` | Wakelock and brightness behind an interface |
| `lib/data/services/scanner_camera.dart` | `mobile_scanner` behind an interface |
| `lib/providers/member_pass/member_pass_session.dart` | Pure pass rules and `MemberPassView` |
| `lib/providers/member_pass/member_pass_provider.dart` | API, clock and connectivity providers; `MemberPassNotifier`; presentation and wallet providers |
| `lib/providers/member_pass/scan_gate.dart` | Pure repeat filter and `memberKey` |
| `lib/providers/member_pass/scan_display.dart` | `ScannerDisplay` and `mapScanOutcome` / `mapScanError` |
| `lib/providers/member_pass/scanner_access_provider.dart` | Access states and the cached access notifier |
| `lib/providers/member_pass/scanner_controller.dart` | Scan I/O, haptics and auto-dismiss |
| `lib/presentation/widgets/member_pass/pass_colors.dart` | Fixed semantic colors; localized day-color and scan-message text |
| `lib/presentation/widgets/member_pass/pass_card.dart` | `PassCard`, `HolographicBand`, `LiveClock`, `DayStripe`, `PassQr`, `CountdownRing` |
| `lib/presentation/widgets/member_pass/wallet_buttons.dart` | Platform-aware Add to Wallet badges |
| `lib/presentation/widgets/member_pass/member_pass_row.dart` | Profile row that opens the pass |
| `lib/presentation/screens/profile/member_pass_screen.dart` | Pass screen and its states |
| `lib/presentation/screens/profile/member_pass_presentation.dart` | Full-screen presentation route |
| `lib/presentation/screens/scanner/scanner_route.dart` | `/explore/scan` route |
| `lib/presentation/screens/scanner/scanner_gate.dart` | Access gate |
| `lib/presentation/screens/scanner/membership_scanner_screen.dart` | Camera, top bar, result overlay |
| `ios/Runner/AppDelegate.swift` | `biso/wallet` handler |
| `test/helpers/fake_member_pass_api.dart` | Shared fakes and builders |

Deleted: `lib/data/services/validator_service.dart`,
`lib/presentation/screens/validator/controller_mode_screen.dart` and
`test/presentation/screens/validator/controller_mode_design_test.dart`.

---

### Task 1: Oslo time

**Files:**
- Create: `lib/core/utils/oslo_time.dart`
- Test: `test/core/utils/oslo_time_test.dart`

**Interfaces:**
- Produces:
  - `DateTime osloWallClock(DateTime instant)` returns a UTC-flagged `DateTime` whose fields read as
    Oslo wall-clock time. Format it; never convert it again.
  - `bool isOsloSummerTime(DateTime instant)`
  - `String formatOsloClock(DateTime instant)` returns `HH:MM:SS`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/utils/oslo_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  group('summer time switches at 01:00 UTC on the last Sunday', () {
    final cases = {
      // year: (march switch, october switch)
      2026: (DateTime.utc(2026, 3, 29, 1), DateTime.utc(2026, 10, 25, 1)),
      2027: (DateTime.utc(2027, 3, 28, 1), DateTime.utc(2027, 10, 31, 1)),
    };
    cases.forEach((year, switches) {
      final (spring, autumn) = switches;
      test('$year spring forward', () {
        expect(isOsloSummerTime(spring.subtract(ms)), isFalse);
        expect(isOsloSummerTime(spring), isTrue);
        expect(formatOsloClock(spring.subtract(ms)), '01:59:59');
        expect(formatOsloClock(spring), '03:00:00');
      });
      test('$year fall back', () {
        expect(isOsloSummerTime(autumn.subtract(ms)), isTrue);
        expect(isOsloSummerTime(autumn), isFalse);
        expect(formatOsloClock(autumn.subtract(ms)), '02:59:59');
        expect(formatOsloClock(autumn), '02:00:00');
      });
    });
  });

  test('an ordinary summer time is UTC+2', () {
    expect(formatOsloClock(DateTime.utc(2026, 7, 15, 12, 5, 9)), '14:05:09');
  });

  test('an ordinary winter time is UTC+1', () {
    expect(formatOsloClock(DateTime.utc(2026, 1, 15, 23, 30)), '00:30:00');
    expect(osloWallClock(DateTime.utc(2026, 1, 15, 23, 30)).day, 16);
  });

  test('a local DateTime gives the same answer as its UTC instant', () {
    final utc = DateTime.utc(2026, 9, 17, 10);
    expect(formatOsloClock(utc.toLocal()), formatOsloClock(utc));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/utils/oslo_time_test.dart`
Expected: FAIL, because `oslo_time.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// Oslo wall-clock time without the full time zone database.
///
/// Norway follows the EU rule: summer time (UTC+2) from 01:00 UTC on the last
/// Sunday of March until 01:00 UTC on the last Sunday of October, UTC+1
/// otherwise.
library;

/// [instant] as Oslo wall-clock time. The result is flagged UTC but its
/// fields are Oslo's: format it, never convert it again.
DateTime osloWallClock(DateTime instant) {
  final utc = instant.toUtc();
  return utc.add(Duration(hours: isOsloSummerTime(utc) ? 2 : 1));
}

bool isOsloSummerTime(DateTime instant) {
  final utc = instant.toUtc();
  final start = _lastSundayAtOneUtc(utc.year, DateTime.march);
  final end = _lastSundayAtOneUtc(utc.year, DateTime.october);
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// `HH:MM:SS` in Oslo.
String formatOsloClock(DateTime instant) {
  final t = osloWallClock(instant);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % 7, 1);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/utils/oslo_time_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/core/utils/oslo_time.dart test/core/utils/oslo_time_test.dart
git add lib/core/utils/oslo_time.dart test/core/utils/oslo_time_test.dart
git commit -m "Tell Oslo time without a time zone database

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 2: Member pass models

**Files:**
- Create: `lib/data/models/member_pass.dart`
- Test: `test/data/models/member_pass_test.dart`

**Interfaces:**
- Produces (all `Equatable`; the classes that can hold a code override `stringify` to `false`):
  - `enum NoPassState { noBiIdentity, notMember, expired, unavailable }`, with
    `static NoPassState fromValue(String?)`. Unknown values map to `unavailable`.
  - `enum TermDuration { semester, year, threeYears }` and `enum TermSeason { spring, fall }`
  - `PassTerm({required TermDuration duration, TermSeason? season, required int fromYear, required int toYear})`
    - `static PassTerm? tryParse(Object? json)`
    - `String label({required String spring, required String fall})`
  - `PassHolder({required String name, required String membershipName, DateTime? startDate, DateTime? expiryDate, PassTerm? term})`
    and `PassHolder.fromJson(Map<String, dynamic>)`
  - `PassCode({required int slot, required String code})`, `static PassCode? tryParse(Map)`, and a
    `toString()` without the code.
  - `DayColor({required String name, required String hex})`, `DayColor.fromJson(Object?)`,
    `Color get color` (grey `0xFF8E8E93` when the hex is invalid) and `static const names` (the 12
    names).
  - `WalletAvailability({required bool apple, required bool google})` and
    `WalletAvailability.fromJson(Object?)`
  - `sealed class MemberPassResponse` with `factory MemberPassResponse.fromJson(Map<String, dynamic>)`
    - `ActivePass({required PassHolder holder, required List<PassCode> codes, required DayColor dayColor, required int serverNow, required WalletAvailability wallets})`.
      Codes are sorted by slot.
    - `NoPass(NoPassState state)`
  - `ScannerAccess({String? campusId, DateTime? expiresAt, required DayColor dayColor})` and
    `ScannerAccess.fromJson(Map<String, dynamic>)`
  - `enum ScanResult { valid, duplicate, checkId, denied, unavailable }`
  - `enum DenyReason { badCode, stale, expired, notMember, notLinked, other }`
  - `ScanOutcome({required ScanResult result, DenyReason? reason, String? name, String? membershipName, DateTime? expiryDate, int? secondsSincePrevious})`
    and `ScanOutcome.fromJson(Map<String, dynamic>)`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:ui' show Color;

import 'package:biso/data/models/member_pass.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> activeJson() => {
  'state': 'active',
  'holder': {
    'name': 'Markus Heien',
    'membershipName': 'Semester',
    'startDate': '2026-07-01',
    'expiryDate': '2026-12-31',
    'term': {
      'duration': 'semester',
      'season': 'fall',
      'fromYear': 2026,
      'toYear': 2026,
    },
  },
  'codes': [
    {'slot': 59654565, 'code': 'v1.u.59654565.b'},
    {'slot': 59654564, 'code': 'v1.u.59654564.a'},
  ],
  'dayColor': {'name': 'teal', 'hex': '#12A594'},
  'serverNow': 1789636920000,
  'wallets': {'apple': true, 'google': false},
};

void main() {
  test('parses an active pass with codes in slot order', () {
    final pass = MemberPassResponse.fromJson(activeJson()) as ActivePass;
    expect(pass.holder.name, 'Markus Heien');
    expect(pass.holder.membershipName, 'Semester');
    expect(pass.holder.expiryDate, DateTime(2026, 12, 31));
    expect(pass.codes.map((c) => c.slot), [59654564, 59654565]);
    expect(pass.serverNow, 1789636920000);
    expect(pass.dayColor.color, const Color(0xFF12A594));
    expect(pass.wallets, const WalletAvailability(apple: true, google: false));
  });

  test('an active body with no usable codes is unavailable', () {
    final json = activeJson()..['codes'] = [{'slot': 'x', 'code': ''}];
    expect(
      MemberPassResponse.fromJson(json),
      const NoPass(NoPassState.unavailable),
    );
  });

  test('parses each no-pass state and treats unknown ones as unavailable', () {
    for (final (value, state) in [
      ('no_bi_identity', NoPassState.noBiIdentity),
      ('not_member', NoPassState.notMember),
      ('expired', NoPassState.expired),
      ('unavailable', NoPassState.unavailable),
      ('something_new', NoPassState.unavailable),
    ]) {
      expect(MemberPassResponse.fromJson({'state': value}), NoPass(state));
    }
  });

  test('term labels', () {
    const fall = PassTerm(
      duration: TermDuration.semester,
      season: TermSeason.fall,
      fromYear: 2026,
      toYear: 2026,
    );
    const spring = PassTerm(
      duration: TermDuration.semester,
      season: TermSeason.spring,
      fromYear: 2027,
      toYear: 2027,
    );
    const year = PassTerm(
      duration: TermDuration.year,
      fromYear: 2026,
      toYear: 2027,
    );
    const three = PassTerm(
      duration: TermDuration.threeYears,
      fromYear: 2026,
      toYear: 2029,
    );
    expect(fall.label(spring: 'Vår', fall: 'Høst'), 'Høst 2026');
    expect(spring.label(spring: 'Spring', fall: 'Fall'), 'Spring 2027');
    expect(year.label(spring: 'Spring', fall: 'Fall'), '2026–2027');
    expect(three.label(spring: 'Spring', fall: 'Fall'), '2026–2029');
    expect(PassTerm.tryParse(null), isNull);
    expect(
      PassTerm.tryParse({'duration': 'three_years', 'fromYear': 2026, 'toYear': 2029}),
      three,
    );
  });

  test('a code never appears in toString', () {
    const code = PassCode(slot: 1, code: 'v1.secret-user.1.sig');
    expect(code.toString(), isNot(contains('secret')));
    final pass = MemberPassResponse.fromJson(activeJson());
    expect(pass.toString(), isNot(contains('v1.')));
  });

  test('an invalid day color hex falls back to grey', () {
    expect(
      DayColor.fromJson({'name': 'teal', 'hex': 'nope'}).color,
      const Color(0xFF8E8E93),
    );
    expect(DayColor.names, hasLength(12));
  });

  test('parses scanner access', () {
    final access = ScannerAccess.fromJson({
      'campusId': null,
      'expiresAt': '2026-09-20T22:00:00.000Z',
      'dayColor': {'name': 'blue', 'hex': '#0090FF'},
    });
    expect(access.campusId, isNull);
    expect(access.expiresAt, DateTime.utc(2026, 9, 20, 22));
    expect(access.dayColor.name, 'blue');
  });

  test('parses every scan result and reason', () {
    expect(
      ScanOutcome.fromJson({
        'result': 'valid',
        'name': 'Kari',
        'membershipName': 'Year',
        'expiryDate': '2027-06-30',
      }),
      ScanOutcome(
        result: ScanResult.valid,
        name: 'Kari',
        membershipName: 'Year',
        expiryDate: DateTime(2027, 6, 30),
      ),
    );
    expect(
      ScanOutcome.fromJson({'result': 'duplicate', 'secondsSincePrevious': 42})
          .secondsSincePrevious,
      42,
    );
    expect(ScanOutcome.fromJson({'result': 'check_id'}).result, ScanResult.checkId);
    for (final (value, reason) in [
      ('bad_code', DenyReason.badCode),
      ('stale', DenyReason.stale),
      ('expired', DenyReason.expired),
      ('not_member', DenyReason.notMember),
      ('not_linked', DenyReason.notLinked),
      ('new_reason', DenyReason.other),
    ]) {
      final outcome = ScanOutcome.fromJson({'result': 'denied', 'reason': value});
      expect(outcome.result, ScanResult.denied);
      expect(outcome.reason, reason);
    }
    expect(ScanOutcome.fromJson({'result': 'what'}).result, ScanResult.unavailable);
    expect(ScanOutcome.fromJson({'result': 'valid', 'reason': 'stale'}).reason, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/models/member_pass_test.dart`
Expected: FAIL, because `member_pass.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

/// Why there is no pass to show. The server decides it.
enum NoPassState {
  noBiIdentity('no_bi_identity'),
  notMember('not_member'),
  expired('expired'),
  unavailable('unavailable');

  const NoPassState(this.value);

  final String value;

  /// An unknown state reads as "cannot tell right now".
  static NoPassState fromValue(String? value) {
    for (final state in values) {
      if (state.value == value) return state;
    }
    return unavailable;
  }
}

enum TermDuration { semester, year, threeYears }

enum TermSeason { spring, fall }

/// The period a membership covers, for the pass label.
class PassTerm extends Equatable {
  const PassTerm({
    required this.duration,
    this.season,
    required this.fromYear,
    required this.toYear,
  });

  final TermDuration duration;
  final TermSeason? season;
  final int fromYear;
  final int toYear;

  static PassTerm? tryParse(Object? json) {
    if (json is! Map) return null;
    final duration = switch (json['duration']) {
      'semester' => TermDuration.semester,
      'year' => TermDuration.year,
      'three_years' => TermDuration.threeYears,
      _ => null,
    };
    final from = _int(json['fromYear']);
    final to = _int(json['toYear']);
    if (duration == null || from == null || to == null) return null;
    final season = switch (json['season']) {
      'spring' => TermSeason.spring,
      'fall' => TermSeason.fall,
      _ => null,
    };
    return PassTerm(
      duration: duration,
      season: season,
      fromYear: from,
      toYear: to,
    );
  }

  /// "Fall 2026" for a semester, otherwise "2026–2027" (or "2026").
  String label({required String spring, required String fall}) {
    final season = this.season;
    if (duration == TermDuration.semester && season != null) {
      return '${season == TermSeason.spring ? spring : fall} $fromYear';
    }
    return fromYear == toYear ? '$fromYear' : '$fromYear–$toYear';
  }

  @override
  List<Object?> get props => [duration, season, fromYear, toYear];
}

class PassHolder extends Equatable {
  const PassHolder({
    required this.name,
    required this.membershipName,
    this.startDate,
    this.expiryDate,
    this.term,
  });

  factory PassHolder.fromJson(Map<String, dynamic> json) => PassHolder(
    name: '${json['name'] ?? ''}',
    membershipName: '${json['membershipName'] ?? ''}',
    startDate: _date(json['startDate']),
    expiryDate: _date(json['expiryDate']),
    term: PassTerm.tryParse(json['term']),
  );

  final String name;
  final String membershipName;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final PassTerm? term;

  @override
  List<Object?> get props => [
    name,
    membershipName,
    startDate,
    expiryDate,
    term,
  ];
}

/// One signed pass code for one 30-second slot. Kept in memory only.
class PassCode extends Equatable {
  const PassCode({required this.slot, required this.code});

  final int slot;
  final String code;

  static PassCode? tryParse(Map<dynamic, dynamic> json) {
    final slot = _int(json['slot']);
    final code = _text(json['code']);
    if (slot == null || code == null) return null;
    return PassCode(slot: slot, code: code);
  }

  @override
  List<Object?> get props => [slot, code];

  @override
  bool? get stringify => false;

  @override
  String toString() => 'PassCode(slot: $slot)';
}

/// Today's shared color, compared at a glance by door staff.
class DayColor extends Equatable {
  const DayColor({required this.name, required this.hex});

  factory DayColor.fromJson(Object? json) {
    final map = _map(json);
    return DayColor(name: '${map['name'] ?? ''}', hex: '${map['hex'] ?? ''}');
  }

  static const names = [
    'red',
    'orange',
    'yellow',
    'lime',
    'green',
    'teal',
    'cyan',
    'blue',
    'indigo',
    'purple',
    'pink',
    'brown',
  ];

  final String name;
  final String hex;

  Color get color {
    final digits = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
    return Color(0xFF000000 | (value ?? 0x8E8E93));
  }

  @override
  List<Object?> get props => [name, hex];
}

class WalletAvailability extends Equatable {
  const WalletAvailability({required this.apple, required this.google});

  factory WalletAvailability.fromJson(Object? json) {
    final map = _map(json);
    return WalletAvailability(
      apple: map['apple'] == true,
      google: map['google'] == true,
    );
  }

  final bool apple;
  final bool google;

  @override
  List<Object?> get props => [apple, google];
}

/// What `GET /api/member-pass` answered.
sealed class MemberPassResponse extends Equatable {
  const MemberPassResponse();

  factory MemberPassResponse.fromJson(Map<String, dynamic> json) {
    if (json['state'] != 'active') {
      return NoPass(NoPassState.fromValue(json['state']?.toString()));
    }
    final rawCodes = json['codes'];
    final codes =
        (rawCodes is List ? rawCodes : const [])
            .whereType<Map>()
            .map(PassCode.tryParse)
            .whereType<PassCode>()
            .toList()
          ..sort((a, b) => a.slot.compareTo(b.slot));
    final serverNow = _int(json['serverNow']);
    final holder = json['holder'];
    if (codes.isEmpty || serverNow == null || holder is! Map) {
      return const NoPass(NoPassState.unavailable);
    }
    return ActivePass(
      holder: PassHolder.fromJson(Map<String, dynamic>.from(holder)),
      codes: List.unmodifiable(codes),
      dayColor: DayColor.fromJson(json['dayColor']),
      serverNow: serverNow,
      wallets: WalletAvailability.fromJson(json['wallets']),
    );
  }

  @override
  bool? get stringify => false;
}

class ActivePass extends MemberPassResponse {
  const ActivePass({
    required this.holder,
    required this.codes,
    required this.dayColor,
    required this.serverNow,
    required this.wallets,
  });

  final PassHolder holder;
  final List<PassCode> codes;
  final DayColor dayColor;

  /// Server clock in Unix milliseconds when the body was made.
  final int serverNow;
  final WalletAvailability wallets;

  @override
  List<Object?> get props => [holder, codes, dayColor, serverNow, wallets];

  @override
  String toString() => 'ActivePass(${codes.length} codes)';
}

class NoPass extends MemberPassResponse {
  const NoPass(this.state);

  final NoPassState state;

  @override
  List<Object?> get props => [state];

  @override
  String toString() => 'NoPass(${state.value})';
}

/// The signed-in user's scanner grant.
class ScannerAccess extends Equatable {
  const ScannerAccess({this.campusId, this.expiresAt, required this.dayColor});

  factory ScannerAccess.fromJson(Map<String, dynamic> json) => ScannerAccess(
    campusId: _text(json['campusId']),
    expiresAt: _date(json['expiresAt']),
    dayColor: DayColor.fromJson(json['dayColor']),
  );

  final String? campusId;
  final DateTime? expiresAt;
  final DayColor dayColor;

  @override
  List<Object?> get props => [campusId, expiresAt, dayColor];
}

enum ScanResult { valid, duplicate, checkId, denied, unavailable }

enum DenyReason { badCode, stale, expired, notMember, notLinked, other }

/// What `POST /api/member-pass/scan` answered.
class ScanOutcome extends Equatable {
  const ScanOutcome({
    required this.result,
    this.reason,
    this.name,
    this.membershipName,
    this.expiryDate,
    this.secondsSincePrevious,
  });

  factory ScanOutcome.fromJson(Map<String, dynamic> json) {
    final result = switch (json['result']) {
      'valid' => ScanResult.valid,
      'duplicate' => ScanResult.duplicate,
      'check_id' => ScanResult.checkId,
      'denied' => ScanResult.denied,
      _ => ScanResult.unavailable,
    };
    final reason = result != ScanResult.denied
        ? null
        : switch (json['reason']) {
            'bad_code' => DenyReason.badCode,
            'stale' => DenyReason.stale,
            'expired' => DenyReason.expired,
            'not_member' => DenyReason.notMember,
            'not_linked' => DenyReason.notLinked,
            _ => DenyReason.other,
          };
    return ScanOutcome(
      result: result,
      reason: reason,
      name: _text(json['name']),
      membershipName: _text(json['membershipName']),
      expiryDate: _date(json['expiryDate']),
      secondsSincePrevious: _int(json['secondsSincePrevious']),
    );
  }

  final ScanResult result;
  final DenyReason? reason;
  final String? name;
  final String? membershipName;
  final DateTime? expiryDate;
  final int? secondsSincePrevious;

  @override
  List<Object?> get props => [
    result,
    reason,
    name,
    membershipName,
    expiryDate,
    secondsSincePrevious,
  ];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/models/member_pass_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/data/models/member_pass.dart test/data/models/member_pass_test.dart
git add lib/data/models/member_pass.dart test/data/models/member_pass_test.dart
git commit -m "Add the member pass and scan models

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 3: Member pass API client and shared test fakes

**Files:**
- Create: `lib/data/services/member_pass_api_client.dart`
- Create: `test/helpers/fake_member_pass_api.dart`
- Test: `test/data/services/member_pass_api_client_test.dart`

**Interfaces:**
- Consumes: the Task 2 models; `ApiJwtProvider`, `appwriteJwt` and `apiUri` from
  `lib/data/services/api_auth.dart`.
- Produces:
  - `abstract interface class MemberPassApi` with five methods:
    - `Future<MemberPassResponse> fetchPass()`
    - `Future<Uint8List> fetchApplePass()`
    - `Future<Uri> fetchGoogleSaveUrl()`
    - `Future<ScannerAccess> fetchScannerAccess()`
    - `Future<ScanOutcome> scan(String code)`
  - `class MemberPassApiException implements Exception`, constructed as
    `const MemberPassApiException(String error, {int? statusCode})`.
    - Constant `static const network = 'network'`.
    - Getters `isUnauthorized` (401), `isForbidden` (403), `isNotFound` (404), `isBadRequest` (400),
      `isRateLimited` (429) and `isNotConfigured` (503).
    - `isTransient` is true when there is no status or it is 500 or higher.
  - `class MemberPassApiClient implements MemberPassApi`, constructed as
    `({http.Client? httpClient, ApiJwtProvider? jwtProvider})`.
  - Test helpers:
    - `FakeMemberPassApi`, with settable handlers and call counters.
    - `const testDayColor`.
    - `ActivePass activePassAt(int serverNowMs, {int count = 20, int firstSlotOffset = 0, WalletAvailability wallets, PassTerm? term})`.
      Code `i` is `'v1.user-1.<slot>.sig'`.

- [ ] **Step 1: Write the shared fake**

`test/helpers/fake_member_pass_api.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';

const testDayColor = DayColor(name: 'teal', hex: '#12A594');

const testTerm = PassTerm(
  duration: TermDuration.semester,
  season: TermSeason.fall,
  fromYear: 2026,
  toYear: 2026,
);

/// An active pass whose first code is for the slot containing
/// [serverNowMs] (shifted by [firstSlotOffset]).
ActivePass activePassAt(
  int serverNowMs, {
  int count = 20,
  int firstSlotOffset = 0,
  WalletAvailability wallets = const WalletAvailability(
    apple: true,
    google: true,
  ),
  PassTerm? term = testTerm,
}) {
  final first = serverNowMs ~/ 30000 + firstSlotOffset;
  return ActivePass(
    holder: PassHolder(
      name: 'Kari Nordmann',
      membershipName: 'Semester',
      startDate: DateTime(2026, 7, 1),
      expiryDate: DateTime(2026, 12, 31),
      term: term,
    ),
    codes: [
      for (var i = 0; i < count; i++)
        PassCode(slot: first + i, code: 'v1.user-1.${first + i}.sig'),
    ],
    dayColor: testDayColor,
    serverNow: serverNowMs,
    wallets: wallets,
  );
}

Never _unset(String name) =>
    throw StateError('FakeMemberPassApi.$name was not set');

/// A [MemberPassApi] whose answers each test sets.
class FakeMemberPassApi implements MemberPassApi {
  FutureOr<MemberPassResponse> Function() onFetchPass = () =>
      _unset('onFetchPass');
  FutureOr<Uint8List> Function() onFetchApplePass = () =>
      _unset('onFetchApplePass');
  FutureOr<Uri> Function() onFetchGoogleSaveUrl = () =>
      _unset('onFetchGoogleSaveUrl');
  FutureOr<ScannerAccess> Function() onFetchScannerAccess = () =>
      _unset('onFetchScannerAccess');
  FutureOr<ScanOutcome> Function(String code) onScan = (_) =>
      _unset('onScan');

  int fetchPassCalls = 0;
  int applePassCalls = 0;
  int googleSaveUrlCalls = 0;
  int scannerAccessCalls = 0;
  final scanned = <String>[];

  @override
  Future<MemberPassResponse> fetchPass() async {
    fetchPassCalls++;
    return onFetchPass();
  }

  @override
  Future<Uint8List> fetchApplePass() async {
    applePassCalls++;
    return onFetchApplePass();
  }

  @override
  Future<Uri> fetchGoogleSaveUrl() async {
    googleSaveUrlCalls++;
    return onFetchGoogleSaveUrl();
  }

  @override
  Future<ScannerAccess> fetchScannerAccess() async {
    scannerAccessCalls++;
    return onFetchScannerAccess();
  }

  @override
  Future<ScanOutcome> scan(String code) async {
    scanned.add(code);
    return onScan(code);
  }
}
```

- [ ] **Step 2: Write the failing client test**

`test/data/services/member_pass_api_client_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  MemberPassApiClient clientReturning(http.Response response) {
    return MemberPassApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-secret-1',
    );
  }

  http.Response json(Object body, int status) =>
      http.Response(jsonEncode(body), status);

  Matcher failsWith(int? status, String error) => throwsA(
    isA<MemberPassApiException>()
        .having((e) => e.statusCode, 'statusCode', status)
        .having((e) => e.error, 'error', error),
  );

  group('fetchPass', () {
    test('sends the token and parses a no-pass state', () async {
      final client = clientReturning(json({'state': 'not_member'}, 200));
      final result = await client.fetchPass();
      expect(sent.method, 'GET');
      expect(sent.url.toString(), 'https://api.biso.no/api/member-pass');
      expect(sent.headers['Authorization'], 'Bearer jwt-secret-1');
      expect(result, const NoPass(NoPassState.notMember));
    });

    test('a 404 (route not deployed) reads as unavailable', () async {
      final client = clientReturning(http.Response('Not found', 404));
      expect(await client.fetchPass(), const NoPass(NoPassState.unavailable));
    });

    test('a 401 is unauthorized', () async {
      final client = clientReturning(json({'error': 'not_authenticated'}, 401));
      await expectLater(client.fetchPass(), failsWith(401, 'not_authenticated'));
    });

    test('a 5xx is transient', () async {
      final client = clientReturning(http.Response('<html>', 502));
      await expectLater(
        client.fetchPass(),
        throwsA(
          isA<MemberPassApiException>().having(
            (e) => e.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });

    test('a network failure is transient with no status', () async {
      final client = MemberPassApiClient(
        httpClient: MockClient((_) async => throw http.ClientException('x')),
        jwtProvider: () async => 'jwt',
      );
      await expectLater(client.fetchPass(), failsWith(null, 'network'));
    });

    test('a timeout is a network failure', () async {
      final client = MemberPassApiClient(
        httpClient: MockClient((_) async => throw TimeoutException('slow')),
        jwtProvider: () async => 'jwt',
      );
      await expectLater(client.fetchPass(), failsWith(null, 'network'));
    });
  });

  group('wallets', () {
    test('returns the pkpass bytes', () async {
      final client = clientReturning(
        http.Response.bytes([1, 2, 3], 200, headers: {
          'content-type': 'application/vnd.apple.pkpass',
        }),
      );
      expect(await client.fetchApplePass(), [1, 2, 3]);
      expect(sent.url.path, '/api/member-pass/apple');
    });

    test('apple 403, 404 and 500 keep their meaning', () async {
      await expectLater(
        clientReturning(json({'error': 'not_member'}, 403)).fetchApplePass(),
        failsWith(403, 'not_member'),
      );
      await expectLater(
        clientReturning(json({'error': 'not_configured'}, 404)).fetchApplePass(),
        failsWith(404, 'not_configured'),
      );
      await expectLater(
        clientReturning(json({'error': 'failed'}, 500)).fetchApplePass(),
        failsWith(500, 'failed'),
      );
    });

    test('returns the Google save URL', () async {
      final client = clientReturning(
        json({'saveUrl': 'https://pay.google.com/gp/v/save/abc'}, 200),
      );
      expect(
        await client.fetchGoogleSaveUrl(),
        Uri.parse('https://pay.google.com/gp/v/save/abc'),
      );
      expect(sent.url.path, '/api/member-pass/google');
    });

    test('refuses a save URL that is not https', () async {
      final client = clientReturning(json({'saveUrl': 'javascript:x'}, 200));
      await expectLater(
        client.fetchGoogleSaveUrl(),
        failsWith(502, 'invalid_response'),
      );
    });

    test('google 404 and 502 keep their meaning', () async {
      await expectLater(
        clientReturning(json({'error': 'not_configured'}, 404))
            .fetchGoogleSaveUrl(),
        failsWith(404, 'not_configured'),
      );
      await expectLater(
        clientReturning(json({'error': 'wallet_unavailable'}, 502))
            .fetchGoogleSaveUrl(),
        failsWith(502, 'wallet_unavailable'),
      );
    });
  });

  group('scanner', () {
    test('parses access', () async {
      final client = clientReturning(
        json({
          'campusId': '1',
          'expiresAt': null,
          'dayColor': {'name': 'teal', 'hex': '#12A594'},
        }, 200),
      );
      final access = await client.fetchScannerAccess();
      expect(sent.url.path, '/api/member-pass/scanner');
      expect(access.campusId, '1');
    });

    test('a 404 (route not deployed) reads as not a scanner', () async {
      final client = clientReturning(http.Response('', 404));
      await expectLater(
        client.fetchScannerAccess(),
        failsWith(403, 'not_scanner'),
      );
    });

    test('503 is not configured', () async {
      final client = clientReturning(json({'error': 'not_configured'}, 503));
      await expectLater(
        client.fetchScannerAccess(),
        throwsA(
          isA<MemberPassApiException>().having(
            (e) => e.isNotConfigured,
            'isNotConfigured',
            isTrue,
          ),
        ),
      );
    });

    test('posts the scanned code as JSON', () async {
      final client = clientReturning(json({'result': 'valid'}, 200));
      final outcome = await client.scan('v1.u.1.sig');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/member-pass/scan');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {'code': 'v1.u.1.sig'});
      expect(outcome.result, ScanResult.valid);
    });

    test('scan errors keep their status', () async {
      for (final (status, error) in [
        (400, 'invalid_body'),
        (401, 'not_authenticated'),
        (403, 'not_scanner'),
        (429, 'rate_limited'),
        (503, 'not_configured'),
      ]) {
        await expectLater(
          clientReturning(json({'error': error}, status)).scan('x'),
          failsWith(status, error),
        );
      }
    });
  });

  test('exceptions never carry a code, token or body', () async {
    final client = clientReturning(
      json({'error': 'v1.user.1.SIG jwt-secret-1'}, 400),
    );
    try {
      await client.scan('v1.user.1.SIG');
      fail('expected an exception');
    } on MemberPassApiException catch (e) {
      expect(e.error, 'error');
      expect(e.toString(), isNot(contains('v1.')));
      expect(e.toString(), isNot(contains('jwt')));
    }
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/data/services/member_pass_api_client_test.dart`
Expected: FAIL, because `member_pass_api_client.dart` does not exist.

- [ ] **Step 4: Write the implementation**

`lib/data/services/member_pass_api_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/member_pass.dart';
import 'api_auth.dart';

/// The member pass endpoints on `apps/api`. The server signs every code and
/// decides every answer; the app only asks.
abstract interface class MemberPassApi {
  Future<MemberPassResponse> fetchPass();
  Future<Uint8List> fetchApplePass();
  Future<Uri> fetchGoogleSaveUrl();
  Future<ScannerAccess> fetchScannerAccess();
  Future<ScanOutcome> scan(String code);
}

/// A member pass request that failed.
///
/// [error] is the server's `error` token, [network] when no answer came, or
/// `error` when the body held anything else. It never carries a body, a
/// header or a code, so it is safe to log.
class MemberPassApiException implements Exception {
  const MemberPassApiException(this.error, {this.statusCode});

  static const network = 'network';

  final String error;
  final int? statusCode;

  bool get isBadRequest => statusCode == 400;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isNotConfigured => statusCode == 503;

  /// No answer, or a server-side failure worth trying again.
  bool get isTransient {
    final status = statusCode;
    return status == null || status >= 500;
  }

  @override
  String toString() => 'MemberPassApiException(${statusCode ?? '-'}, $error)';
}

class MemberPassApiClient implements MemberPassApi {
  MemberPassApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);
  static final RegExp _safeError = RegExp(r'^[a-z_]{1,40}$');

  @override
  Future<MemberPassResponse> fetchPass() async {
    final response = await _send('GET', '/api/member-pass');
    // Until apps/api deploys the route there is simply no pass to show.
    if (response.statusCode == 404) {
      return const NoPass(NoPassState.unavailable);
    }
    return MemberPassResponse.fromJson(_json(_ok(response)));
  }

  @override
  Future<Uint8List> fetchApplePass() async {
    final response = _ok(await _send('GET', '/api/member-pass/apple'));
    return response.bodyBytes;
  }

  @override
  Future<Uri> fetchGoogleSaveUrl() async {
    final response = _ok(await _send('GET', '/api/member-pass/google'));
    final url = Uri.tryParse('${_json(response)['saveUrl'] ?? ''}');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const MemberPassApiException('invalid_response', statusCode: 502);
    }
    return url;
  }

  @override
  Future<ScannerAccess> fetchScannerAccess() async {
    final response = await _send('GET', '/api/member-pass/scanner');
    // Until apps/api deploys the route nobody is a scanner.
    if (response.statusCode == 404) {
      throw const MemberPassApiException('not_scanner', statusCode: 403);
    }
    return ScannerAccess.fromJson(_json(_ok(response)));
  }

  @override
  Future<ScanOutcome> scan(String code) async {
    final response = await _send(
      'POST',
      '/api/member-pass/scan',
      body: {'code': code},
    );
    return ScanOutcome.fromJson(_json(_ok(response)));
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final request = http.Request(method, apiUri(path))
        ..headers.addAll({
          'accept': 'application/json',
          if (body != null) 'content-type': 'application/json',
          if (jwt != null) 'Authorization': 'Bearer $jwt',
        });
      if (body != null) request.body = jsonEncode(body);
      return await http.Response.fromStream(
        await client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } on http.ClientException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } on IOException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } finally {
      if (shouldClose) client.close();
    }
  }

  http.Response _ok(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var error = 'error';
    try {
      final decoded = jsonDecode(response.body);
      final value = decoded is Map ? decoded['error'] : null;
      if (value is String && _safeError.hasMatch(value)) error = value;
    } catch (_) {
      // Not JSON: keep the generic token.
    }
    throw MemberPassApiException(error, statusCode: response.statusCode);
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw const MemberPassApiException('invalid_response', statusCode: 502);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/data/services/member_pass_api_client_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
dart format lib/data/services/member_pass_api_client.dart test/helpers/fake_member_pass_api.dart test/data/services/member_pass_api_client_test.dart
git add lib/data/services/member_pass_api_client.dart test/helpers/fake_member_pass_api.dart test/data/services/member_pass_api_client_test.dart
git commit -m "Add the member pass API client

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 4: Pass session rules

**Files:**
- Create: `lib/providers/member_pass/member_pass_session.dart`
- Test: `test/providers/member_pass/member_pass_session_test.dart`

**Interfaces:**
- Consumes: the Task 2 models.
- Produces:
  - `const passSlotMs = 30000`, `const passRefetchBelow = 4`, `const passRetryEveryMs = 15000`
  - `enum PassStatus { loading, active, noPass, reconnect, signedOut }`
  - `class MemberPassView` (Equatable, `stringify` false), with fields:
    - `PassStatus status`
    - `NoPassState? noPassState`
    - `ActivePass? pass`
    - `String? code`
    - `int msUntilNextSlot`
    - `bool offline`
    - `bool fetching`
    - `DateTime? serverTime` (UTC)
  - `class MemberPassSession` with:
    - Getters `status`, `noPassState`, `offline`, `pass` and `drift`.
    - Updates `apply(MemberPassResponse, int localNowMs)`, `applyUnauthorized()` and
      `applyTransientFailure(int nowMs)`.
    - Queries `slotAt(int)`, `current(int)` (returns `PassCode?`), `msUntilNextSlot(int)`,
      `remainingCodes(int)`, `needsRefetch(int)` and
      `shouldRetry(int nowMs, {required int? lastAttemptMs, required bool inFlight})`.
    - `MemberPassView view(int nowMs, {bool fetching = false})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  // A slot boundary, so slot arithmetic is easy to read.
  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

  MemberPassSession activeSession({
    int localNow = 0,
    int serverNow = 0,
    int count = 20,
  }) {
    return MemberPassSession()
      ..apply(activePassAt(serverNow, count: count), localNow);
  }

  test('starts loading with nothing to show', () {
    final session = MemberPassSession();
    expect(session.status, PassStatus.loading);
    expect(session.view(t0).code, isNull);
  });

  test('shows the code for the current slot', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    final slot = t0 ~/ passSlotMs;
    expect(session.current(t0)!.slot, slot);
    expect(session.current(t0 + 29999)!.slot, slot);
    expect(session.current(t0 + 30000)!.slot, slot + 1);
    expect(session.msUntilNextSlot(t0), 30000);
    expect(session.msUntilNextSlot(t0 + 29999), 1);
  });

  test('applies positive drift when the phone is behind', () {
    // Phone reads 45 s earlier than the server.
    final session = activeSession(localNow: t0 - 45000, serverNow: t0);
    expect(session.drift, 45000);
    expect(session.current(t0 - 45000)!.slot, t0 ~/ passSlotMs);
    expect(session.msUntilNextSlot(t0 - 45000), 30000);
  });

  test('applies negative drift when the phone is ahead', () {
    final session = activeSession(localNow: t0 + 70000, serverNow: t0);
    expect(session.drift, -70000);
    expect(session.current(t0 + 70000)!.slot, t0 ~/ passSlotMs);
    expect(session.view(t0 + 70000).serverTime, DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true));
  });

  test('needs a refetch when fewer than 4 codes remain', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 5);
    expect(session.remainingCodes(t0), 5);
    expect(session.needsRefetch(t0), isFalse);
    expect(session.needsRefetch(t0 + passSlotMs), isFalse); // 4 left
    expect(session.needsRefetch(t0 + 2 * passSlotMs), isTrue); // 3 left
  });

  test('a clock before the first code has no code and needs a refetch', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    final before = t0 - 5 * passSlotMs;
    expect(session.current(before), isNull);
    expect(session.needsRefetch(before), isTrue);
    expect(session.view(before).status, PassStatus.active);
    expect(session.view(before).code, isNull);
  });

  test('retries at most every 15 s, never while a fetch is in flight', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 3);
    expect(
      session.shouldRetry(t0, lastAttemptMs: null, inFlight: false),
      isTrue,
    );
    expect(
      session.shouldRetry(t0, lastAttemptMs: null, inFlight: true),
      isFalse,
    );
    expect(
      session.shouldRetry(t0 + 14999, lastAttemptMs: t0, inFlight: false),
      isFalse,
    );
    expect(
      session.shouldRetry(t0 + 15000, lastAttemptMs: t0, inFlight: false),
      isTrue,
    );
  });

  test('does not retry a healthy pass', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    expect(
      session.shouldRetry(t0 + 60000, lastAttemptMs: t0, inFlight: false),
      isFalse,
    );
  });

  test('a transient failure keeps a usable pass and marks it offline', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    session.applyTransientFailure(t0 + 1000);
    expect(session.status, PassStatus.active);
    expect(session.offline, isTrue);
    expect(session.view(t0 + 1000).code, isNotNull);
    expect(
      session.shouldRetry(t0 + 16000, lastAttemptMs: t0 + 1000, inFlight: false),
      isTrue,
    );
  });

  test('a transient failure without a usable code asks to reconnect', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 2);
    session.applyTransientFailure(t0 + 3 * passSlotMs);
    expect(session.status, PassStatus.reconnect);
    expect(session.pass, isNull);
    expect(session.offline, isTrue);
    expect(
      session.shouldRetry(t0 + 4 * passSlotMs, lastAttemptMs: t0, inFlight: false),
      isTrue,
    );
  });

  test('a first fetch that fails asks to reconnect', () {
    final session = MemberPassSession()..applyTransientFailure(t0);
    expect(session.status, PassStatus.reconnect);
  });

  test('a later success clears offline', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..applyTransientFailure(t0);
    session.apply(activePassAt(t0 + 1000), t0 + 1000);
    expect(session.offline, isFalse);
  });

  test('a 401 clears the pass', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..applyUnauthorized();
    expect(session.status, PassStatus.signedOut);
    expect(session.pass, isNull);
    expect(session.view(t0).code, isNull);
  });

  test('a 200 without a pass replaces an active pass', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..apply(const NoPass(NoPassState.expired), t0);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.expired);
    expect(session.pass, isNull);
  });

  test('the view never prints the code', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    expect(session.view(t0).toString(), isNot(contains('v1.')));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/member_pass_session_test.dart`
Expected: FAIL, because the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:equatable/equatable.dart';

import '../../data/models/member_pass.dart';

/// Pass codes rotate every 30 seconds.
const passSlotMs = 30000;

/// Fetch more codes when fewer than this many remain.
const passRefetchBelow = 4;

/// While offline or low on codes, try again this often.
const passRetryEveryMs = 15000;

enum PassStatus { loading, active, noPass, reconnect, signedOut }

/// What the pass screen shows at one instant.
class MemberPassView extends Equatable {
  const MemberPassView({
    required this.status,
    this.noPassState,
    this.pass,
    this.code,
    this.msUntilNextSlot = 0,
    this.offline = false,
    this.fetching = false,
    this.serverTime,
  });

  final PassStatus status;
  final NoPassState? noPassState;
  final ActivePass? pass;

  /// The raw code for the QR, or null when none is valid right now.
  final String? code;
  final int msUntilNextSlot;
  final bool offline;
  final bool fetching;

  /// The server's clock now, in UTC.
  final DateTime? serverTime;

  @override
  List<Object?> get props => [
    status,
    noPassState,
    pass,
    code,
    msUntilNextSlot,
    offline,
    fetching,
    serverTime,
  ];

  @override
  bool? get stringify => false;

  @override
  String toString() => 'MemberPassView($status, offline: $offline)';
}

/// The client rules for a live pass, mirroring the web `pass-refresh.ts`.
/// It holds no timers and takes the local clock as an argument.
class MemberPassSession {
  PassStatus _status = PassStatus.loading;
  NoPassState? _noPassState;
  ActivePass? _pass;
  int _drift = 0;
  bool _offline = false;

  PassStatus get status => _status;
  NoPassState? get noPassState => _noPassState;
  ActivePass? get pass => _pass;
  bool get offline => _offline;

  /// Server clock minus local clock, in milliseconds.
  int get drift => _drift;

  /// A 200 answer replaces whatever is shown.
  void apply(MemberPassResponse response, int localNowMs) {
    _offline = false;
    switch (response) {
      case ActivePass():
        _status = PassStatus.active;
        _noPassState = null;
        _pass = response;
        _drift = response.serverNow - localNowMs;
      case NoPass(:final state):
        _status = PassStatus.noPass;
        _noPassState = state;
        _pass = null;
    }
  }

  /// A 401 replaces whatever is shown.
  void applyUnauthorized() {
    _status = PassStatus.signedOut;
    _noPassState = null;
    _pass = null;
    _offline = false;
  }

  /// A 5xx or network failure keeps a pass that can still be shown.
  void applyTransientFailure(int nowMs) {
    _offline = true;
    if (_status == PassStatus.active && current(nowMs) != null) return;
    if (_status == PassStatus.noPass || _status == PassStatus.signedOut) {
      return;
    }
    _status = PassStatus.reconnect;
    _pass = null;
  }

  int slotAt(int nowMs) => (nowMs + _drift) ~/ passSlotMs;

  PassCode? current(int nowMs) {
    final pass = _pass;
    if (pass == null) return null;
    final slot = slotAt(nowMs);
    for (final code in pass.codes) {
      if (code.slot == slot) return code;
    }
    return null;
  }

  int msUntilNextSlot(int nowMs) => passSlotMs - (nowMs + _drift) % passSlotMs;

  int remainingCodes(int nowMs) {
    final pass = _pass;
    if (pass == null) return 0;
    final slot = slotAt(nowMs);
    return pass.codes.where((code) => code.slot >= slot).length;
  }

  bool needsRefetch(int nowMs) =>
      _status == PassStatus.active &&
      (remainingCodes(nowMs) < passRefetchBelow || current(nowMs) == null);

  bool shouldRetry(
    int nowMs, {
    required int? lastAttemptMs,
    required bool inFlight,
  }) {
    if (inFlight) return false;
    if (!_offline && !needsRefetch(nowMs)) return false;
    return lastAttemptMs == null || nowMs - lastAttemptMs >= passRetryEveryMs;
  }

  MemberPassView view(int nowMs, {bool fetching = false}) {
    final active = _status == PassStatus.active;
    return MemberPassView(
      status: _status,
      noPassState: _noPassState,
      pass: _pass,
      code: current(nowMs)?.code,
      msUntilNextSlot: active ? msUntilNextSlot(nowMs) : 0,
      offline: _offline,
      fetching: fetching,
      serverTime: active
          ? DateTime.fromMillisecondsSinceEpoch(nowMs + _drift, isUtc: true)
          : null,
    );
  }
}
```

Note on `applyTransientFailure`:
- A pass that was replaced by a 200 no-pass answer, or by a 401, stays as it is. Only `loading`,
  `reconnect` and an `active` pass with no usable code become `reconnect`.
- `offline` is still set, so the 15 s retry runs. The spec's rule is "replace what is shown only on a
  200 or a 401".

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/member_pass_session_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/providers/member_pass/member_pass_session.dart test/providers/member_pass/member_pass_session_test.dart
git add lib/providers/member_pass/member_pass_session.dart test/providers/member_pass/member_pass_session_test.dart
git commit -m "Add the pass rules for slots, drift and refetching

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 5: Pass notifier (timers, resume, connectivity, keep-alive)

**Files:**
- Modify: `pubspec.yaml` (add `connectivity_plus` and the dev dependency `fake_async`)
- Create: `lib/providers/member_pass/member_pass_provider.dart`
- Test: `test/providers/member_pass/member_pass_notifier_test.dart`

**Interfaces:**
- Consumes:
  - From Task 3: `MemberPassApi`, `MemberPassApiClient` and `MemberPassApiException`.
  - From Task 4: `MemberPassSession`, `MemberPassView` and `PassStatus`.
  - `membershipUserIdProvider` from `lib/providers/membership/membership_overview_provider.dart`.
- Produces:
  - `final memberPassApiProvider = Provider<MemberPassApi>`
  - `final memberPassClockProvider = Provider<int Function()>` (Unix milliseconds)
  - `final connectivityChangesProvider = Provider<Stream<Object?>>`
  - `final memberPassProvider = NotifierProvider.autoDispose<MemberPassNotifier, MemberPassView>`
  - `MemberPassNotifier` with:
    - `KeepAliveLink hold()`
    - `Future<void> retry()`
    - `void onAppResumed()`
    - `void onConnectivityChanged()`

- [ ] **Step 1: Add the dependencies**

Run:

```bash
flutter pub add connectivity_plus
flutter pub add dev:fake_async
```

Expected: `pubspec.yaml` lists `connectivity_plus` under `dependencies` and `fake_async` under
`dev_dependencies`, and `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:async';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;
  const network = MemberPassApiException(MemberPassApiException.network);

  late FakeMemberPassApi api;
  late StreamController<Object?> connectivity;

  setUp(() {
    api = FakeMemberPassApi();
    connectivity = StreamController<Object?>.broadcast();
  });

  tearDown(() => connectivity.close());

  ProviderContainer container(FakeAsync async, {String? userId = 'u1'}) {
    final c = ProviderContainer(
      overrides: [
        memberPassApiProvider.overrideWithValue(api),
        memberPassClockProvider.overrideWithValue(
          () => t0 + async.elapsed.inMilliseconds,
        ),
        connectivityChangesProvider.overrideWithValue(connectivity.stream),
        membershipUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('fetches once when first listened to and shows the current code', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      expect(c.read(memberPassProvider).status, PassStatus.loading);

      async.flushMicrotasks();

      expect(api.fetchPassCalls, 1);
      final view = c.read(memberPassProvider);
      expect(view.status, PassStatus.active);
      expect(view.code, 'v1.user-1.${t0 ~/ 30000}.sig');
    });
  });

  test('moves to the next code on its own without refetching', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));

      expect(c.read(memberPassProvider).code, 'v1.user-1.${t0 ~/ 30000 + 1}.sig');
      expect(api.fetchPassCalls, 1);
    });
  });

  test('refetches when fewer than 4 codes remain', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0, count: 5);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 59));
      expect(api.fetchPassCalls, 1);

      api.onFetchPass = () => activePassAt(t0 + 61000);
      async.elapse(const Duration(seconds: 2));
      expect(api.fetchPassCalls, 2);
    });
  });

  test('keeps the pass through a failure and retries every 15 s', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      api.onFetchPass = () => throw network;
      c.read(memberPassProvider.notifier).onAppResumed();
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 2);
      expect(c.read(memberPassProvider).status, PassStatus.active);
      expect(c.read(memberPassProvider).offline, isTrue);
      expect(c.read(memberPassProvider).code, isNotNull);

      async.elapse(const Duration(seconds: 14));
      expect(api.fetchPassCalls, 2);
      async.elapse(const Duration(seconds: 1));
      expect(api.fetchPassCalls, 3);

      api.onFetchPass = () => activePassAt(t0 + 15000);
      async.elapse(const Duration(seconds: 15));
      expect(api.fetchPassCalls, 4);
      expect(c.read(memberPassProvider).offline, isFalse);
    });
  });

  test('a first fetch that fails asks to reconnect', () {
    fakeAsync((async) {
      api.onFetchPass = () => throw network;
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).status, PassStatus.reconnect);
    });
  });

  test('a 401 shows signed out', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      api.onFetchPass = () => throw const MemberPassApiException(
        'not_authenticated',
        statusCode: 401,
      );
      c.read(memberPassProvider.notifier).retry();
      async.flushMicrotasks();

      expect(c.read(memberPassProvider).status, PassStatus.signedOut);
      expect(c.read(memberPassProvider).code, isNull);
    });
  });

  test('a connectivity change fetches', () {
    fakeAsync((async) {
      api.onFetchPass = () => const NoPass(NoPassState.unavailable);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      connectivity.add(Object());
      async.flushMicrotasks();

      expect(api.fetchPassCalls, 2);
    });
  });

  test('never runs two fetches at once', () {
    fakeAsync((async) {
      final pending = Completer<MemberPassResponse>();
      api.onFetchPass = () => pending.future;
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).fetching, isTrue);

      c.read(memberPassProvider.notifier).retry();
      c.read(memberPassProvider.notifier).onAppResumed();
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 1);

      pending.complete(activePassAt(t0));
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).fetching, isFalse);
    });
  });

  test('a hold keeps the codes while no screen listens', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      final sub = c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      // Riverpod schedules autoDispose with Future(), a zero-length timer.
      final link = c.read(memberPassProvider.notifier).hold();
      sub.close();
      async.elapse(Duration.zero);
      c.listen(memberPassProvider, (_, _) {}).close();
      async.elapse(Duration.zero);
      expect(api.fetchPassCalls, 1);

      link.close();
      async.elapse(Duration.zero);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 2);
    });
  });

  test('without a signed-in user it never asks the server', () {
    fakeAsync((async) {
      final c = container(async, userId: null);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(api.fetchPassCalls, 0);
      expect(c.read(memberPassProvider).status, PassStatus.signedOut);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/member_pass_notifier_test.dart`
Expected: FAIL, because `member_pass_provider.dart` does not exist.

- [ ] **Step 4: Write the implementation**

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';
import '../membership/membership_overview_provider.dart';
import 'member_pass_session.dart';

final memberPassApiProvider = Provider<MemberPassApi>(
  (ref) => MemberPassApiClient(),
);

/// The local clock in Unix milliseconds. Separate so tests can move time.
final memberPassClockProvider = Provider<int Function()>(
  (ref) => () => DateTime.now().millisecondsSinceEpoch,
);

/// Fires when a network interface changes. Only a hint to fetch: a changed
/// interface does not mean the internet works.
final connectivityChangesProvider = Provider<Stream<Object?>>(
  (ref) => Connectivity().onConnectivityChanged,
);

final memberPassProvider =
    NotifierProvider.autoDispose<MemberPassNotifier, MemberPassView>(
      MemberPassNotifier.new,
    );

/// The signed-in member's live pass.
///
/// Codes live only here, in memory. The provider disposes when no screen
/// watches or [hold]s it, and the codes go with it.
class MemberPassNotifier extends AutoDisposeNotifier<MemberPassView> {
  static const tick = Duration(seconds: 1);

  MemberPassSession _session = MemberPassSession();
  bool _inFlight = false;
  int? _lastAttemptMs;

  /// Bumped on every build and dispose, so a fetch started for an earlier
  /// account or lifetime never writes into this one.
  int _generation = 0;

  int _now() => ref.read(memberPassClockProvider)();

  @override
  MemberPassView build() {
    _generation++;
    _session = MemberPassSession();
    _inFlight = false;
    _lastAttemptMs = null;
    ref.onDispose(() => _generation++);

    if (ref.watch(membershipUserIdProvider) == null) {
      _session.applyUnauthorized();
      return _session.view(_now());
    }

    final lifecycle = AppLifecycleListener(onResume: onAppResumed);
    final changes = ref
        .watch(connectivityChangesProvider)
        .listen((_) => onConnectivityChanged());
    final ticker = Timer.periodic(tick, (_) => _onTick());
    ref.onDispose(() {
      lifecycle.dispose();
      changes.cancel();
      ticker.cancel();
    });

    Future.microtask(_fetch);
    return _session.view(_now());
  }

  /// Keeps the codes alive while a route that shows them is open.
  KeepAliveLink hold() => ref.keepAlive();

  Future<void> retry() => _fetch();

  void onAppResumed() => unawaited(_fetch());

  void onConnectivityChanged() => unawaited(_fetch());

  void _onTick() {
    final now = _now();
    if (_session.shouldRetry(
      now,
      lastAttemptMs: _lastAttemptMs,
      inFlight: _inFlight,
    )) {
      unawaited(_fetch());
    }
    state = _session.view(now, fetching: _inFlight);
  }

  Future<void> _fetch() async {
    if (_inFlight) return;
    final generation = _generation;
    final api = ref.read(memberPassApiProvider);
    _inFlight = true;
    _lastAttemptMs = _now();
    state = _session.view(_lastAttemptMs!, fetching: true);

    MemberPassResponse? response;
    MemberPassApiException? failure;
    try {
      response = await api.fetchPass();
    } on MemberPassApiException catch (error) {
      failure = error;
    } catch (_) {
      failure = const MemberPassApiException(MemberPassApiException.network);
    }
    if (generation != _generation) return;

    _inFlight = false;
    final now = _now();
    if (response != null) {
      _session.apply(response, now);
    } else if (failure!.isUnauthorized) {
      _session.applyUnauthorized();
    } else {
      _session.applyTransientFailure(now);
    }
    state = _session.view(now);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/member_pass_notifier_test.dart`
Expected: PASS. Riverpod 2.6 runs disposal and refresh through `Future(task)`, which is a
zero-length timer. That is why the hold test uses `async.elapse(Duration.zero)` and not
`flushMicrotasks()`.

- [ ] **Step 6: Commit**

```bash
dart format lib/providers/member_pass/member_pass_provider.dart test/providers/member_pass/member_pass_notifier_test.dart
git add pubspec.yaml pubspec.lock lib/providers/member_pass/member_pass_provider.dart test/providers/member_pass/member_pass_notifier_test.dart
git commit -m "Keep the member pass fresh while it is on screen

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 6: Scan repeat gate

**Files:**
- Create: `lib/providers/member_pass/scan_gate.dart`
- Test: `test/providers/member_pass/scan_gate_test.dart`

**Interfaces:**
- Produces:
  - `String memberKey(String code)`
  - `class ScanGate({Duration window = const Duration(seconds: 20)})` with
    `bool admit(String code, int nowMs)`, `void finish()` and `bool get busy`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/scan_gate_test.dart`
Expected: FAIL, because the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// The member a pass code belongs to, so one person holding their pass up
/// is one scan. Mirrors the web `scan-repeat.ts`.
///
/// `v1.<id>.<slot>.<sig>` and `a1.<id>.<date>.<sig>` drop the last two parts;
/// `g1.<id>.<totp>` drops the last one. Ids may contain dots. Anything else
/// is its own key.
String memberKey(String code) {
  final parts = code.split('.');
  switch (parts.first) {
    case 'v1' || 'a1' when parts.length >= 4:
      return parts.sublist(1, parts.length - 2).join('.');
    case 'g1' when parts.length >= 3:
      return parts.sublist(1, parts.length - 1).join('.');
  }
  return code;
}

/// Decides which camera reads become scans.
///
/// A member is ignored for [window] after they were last seen, and every
/// read restarts that window. While a scan is busy (in flight or its result
/// on screen) nothing is admitted, and only members already being tracked
/// are refreshed: a stranger glimpsed meanwhile can be scanned straight after.
class ScanGate {
  ScanGate({this.window = const Duration(seconds: 20)});

  final Duration window;
  final Map<String, int> _lastSeen = {};
  bool _busy = false;

  bool get busy => _busy;

  bool admit(String code, int nowMs) {
    _lastSeen.removeWhere(
      (_, seenAt) => nowMs - seenAt >= window.inMilliseconds,
    );
    final key = memberKey(code);
    final recent = _lastSeen.containsKey(key);
    if (_busy) {
      if (recent) _lastSeen[key] = nowMs;
      return false;
    }
    _lastSeen[key] = nowMs;
    if (recent) return false;
    _busy = true;
    return true;
  }

  void finish() => _busy = false;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/scan_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/providers/member_pass/scan_gate.dart test/providers/member_pass/scan_gate_test.dart
git add lib/providers/member_pass/scan_gate.dart test/providers/member_pass/scan_gate_test.dart
git commit -m "Ignore repeat reads of the same member for 20 seconds

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 7: Scan result mapping

**Files:**
- Create: `lib/providers/member_pass/scan_display.dart`
- Test: `test/providers/member_pass/scan_display_test.dart`

**Interfaces:**
- Consumes: `ScanOutcome`, `ScanResult` and `DenyReason` (Task 2); `MemberPassApiException`
  (Task 3).
- Produces:
  - `enum ScanTone { green, orange, amber, red, grey }`
  - `enum ScanMessage { valid, duplicate, checkId, badCode, stale, expired, notMember, notLinked, notValid, unavailable, rateLimited }`
  - `enum ScannerCloseReason { noAccess, signedOut }`
  - `sealed class ScannerDisplay` (Equatable), with four cases:
    - `ScannerIdle()`
    - `ScannerChecking()`
    - `ScannerResult({required ScanTone tone, required ScanMessage message, String? name, String? membershipName, DateTime? expiryDate, int? secondsSincePrevious})`
    - `ScannerClosed(ScannerCloseReason reason)`
  - `const maxScanCodeLength = 256`
  - `const overlongCodeResult` (a red `badCode` `ScannerResult`)
  - `ScannerResult mapScanOutcome(ScanOutcome outcome)`
  - `ScannerDisplay mapScanError(Object error)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid is green with the holder details', () {
    final expiry = DateTime(2026, 12, 31);
    expect(
      mapScanOutcome(
        ScanOutcome(
          result: ScanResult.valid,
          name: 'Kari',
          membershipName: 'Semester',
          expiryDate: expiry,
        ),
      ),
      ScannerResult(
        tone: ScanTone.green,
        message: ScanMessage.valid,
        name: 'Kari',
        membershipName: 'Semester',
        expiryDate: expiry,
      ),
    );
  });

  test('duplicate is orange with the seconds since', () {
    final result = mapScanOutcome(
      const ScanOutcome(
        result: ScanResult.duplicate,
        name: 'Kari',
        secondsSincePrevious: 42,
      ),
    );
    expect(result.tone, ScanTone.orange);
    expect(result.message, ScanMessage.duplicate);
    expect(result.secondsSincePrevious, 42);
    expect(result.name, 'Kari');
  });

  test('check_id is amber', () {
    final result = mapScanOutcome(
      const ScanOutcome(result: ScanResult.checkId, name: 'Kari'),
    );
    expect(result.tone, ScanTone.amber);
    expect(result.message, ScanMessage.checkId);
  });

  test('each denied reason is red with its own message', () {
    for (final (reason, message) in [
      (DenyReason.badCode, ScanMessage.badCode),
      (DenyReason.stale, ScanMessage.stale),
      (DenyReason.expired, ScanMessage.expired),
      (DenyReason.notMember, ScanMessage.notMember),
      (DenyReason.notLinked, ScanMessage.notLinked),
      (DenyReason.other, ScanMessage.notValid),
      (null, ScanMessage.notValid),
    ]) {
      final result = mapScanOutcome(
        ScanOutcome(result: ScanResult.denied, reason: reason),
      );
      expect(result.tone, ScanTone.red, reason: '$reason');
      expect(result.message, message, reason: '$reason');
    }
  });

  test('unavailable is grey', () {
    expect(
      mapScanOutcome(const ScanOutcome(result: ScanResult.unavailable)),
      const ScannerResult(tone: ScanTone.grey, message: ScanMessage.unavailable),
    );
  });

  test('errors', () {
    MemberPassApiException status(int code) =>
        MemberPassApiException('x', statusCode: code);
    expect(
      mapScanError(status(401)),
      const ScannerClosed(ScannerCloseReason.signedOut),
    );
    expect(
      mapScanError(status(403)),
      const ScannerClosed(ScannerCloseReason.noAccess),
    );
    expect(
      mapScanError(status(429)),
      const ScannerResult(tone: ScanTone.grey, message: ScanMessage.rateLimited),
    );
    expect(mapScanError(status(400)), overlongCodeResult);
    for (final error in [
      status(500),
      status(503),
      const MemberPassApiException(MemberPassApiException.network),
      StateError('boom'),
    ]) {
      expect(
        mapScanError(error),
        const ScannerResult(tone: ScanTone.grey, message: ScanMessage.unavailable),
        reason: '$error',
      );
    }
  });

  test('an overlong code reads as not a BISO pass', () {
    expect(
      overlongCodeResult,
      const ScannerResult(tone: ScanTone.red, message: ScanMessage.badCode),
    );
    expect(maxScanCodeLength, 256);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/scan_display_test.dart`
Expected: FAIL, because the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:equatable/equatable.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';

enum ScanTone { green, orange, amber, red, grey }

enum ScanMessage {
  valid,
  duplicate,
  checkId,
  badCode,
  stale,
  expired,
  notMember,
  notLinked,
  notValid,
  unavailable,
  rateLimited,
}

enum ScannerCloseReason { noAccess, signedOut }

/// What the scanner screen shows.
sealed class ScannerDisplay extends Equatable {
  const ScannerDisplay();

  @override
  List<Object?> get props => [];
}

class ScannerIdle extends ScannerDisplay {
  const ScannerIdle();
}

class ScannerChecking extends ScannerDisplay {
  const ScannerChecking();
}

class ScannerResult extends ScannerDisplay {
  const ScannerResult({
    required this.tone,
    required this.message,
    this.name,
    this.membershipName,
    this.expiryDate,
    this.secondsSincePrevious,
  });

  final ScanTone tone;
  final ScanMessage message;
  final String? name;
  final String? membershipName;
  final DateTime? expiryDate;
  final int? secondsSincePrevious;

  @override
  List<Object?> get props => [
    tone,
    message,
    name,
    membershipName,
    expiryDate,
    secondsSincePrevious,
  ];
}

/// The scanner must close: the grant is gone or the session ended.
class ScannerClosed extends ScannerDisplay {
  const ScannerClosed(this.reason);

  final ScannerCloseReason reason;

  @override
  List<Object?> get props => [reason];
}

/// The API refuses longer bodies, so longer reads are not BISO passes.
const maxScanCodeLength = 256;

const overlongCodeResult = ScannerResult(
  tone: ScanTone.red,
  message: ScanMessage.badCode,
);

const _unavailable = ScannerResult(
  tone: ScanTone.grey,
  message: ScanMessage.unavailable,
);

ScannerResult mapScanOutcome(ScanOutcome outcome) => switch (outcome.result) {
  ScanResult.valid => ScannerResult(
    tone: ScanTone.green,
    message: ScanMessage.valid,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
  ),
  ScanResult.duplicate => ScannerResult(
    tone: ScanTone.orange,
    message: ScanMessage.duplicate,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
    secondsSincePrevious: outcome.secondsSincePrevious,
  ),
  ScanResult.checkId => ScannerResult(
    tone: ScanTone.amber,
    message: ScanMessage.checkId,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
  ),
  ScanResult.denied => ScannerResult(
    tone: ScanTone.red,
    message: switch (outcome.reason) {
      DenyReason.badCode => ScanMessage.badCode,
      DenyReason.stale => ScanMessage.stale,
      DenyReason.expired => ScanMessage.expired,
      DenyReason.notMember => ScanMessage.notMember,
      DenyReason.notLinked => ScanMessage.notLinked,
      DenyReason.other || null => ScanMessage.notValid,
    },
  ),
  ScanResult.unavailable => _unavailable,
};

ScannerDisplay mapScanError(Object error) {
  if (error is MemberPassApiException) {
    if (error.isUnauthorized) {
      return const ScannerClosed(ScannerCloseReason.signedOut);
    }
    if (error.isForbidden) {
      return const ScannerClosed(ScannerCloseReason.noAccess);
    }
    if (error.isRateLimited) {
      return const ScannerResult(
        tone: ScanTone.grey,
        message: ScanMessage.rateLimited,
      );
    }
    // The body was refused, so what the camera read was not a pass.
    if (error.isBadRequest) return overlongCodeResult;
  }
  return _unavailable;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/scan_display_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/providers/member_pass/scan_display.dart test/providers/member_pass/scan_display_test.dart
git add lib/providers/member_pass/scan_display.dart test/providers/member_pass/scan_display_test.dart
git commit -m "Map scan answers to what the door staff see

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 8: Scanner access provider

**Files:**
- Create: `lib/providers/member_pass/scanner_access_provider.dart`
- Modify: `test/helpers/fake_member_pass_api.dart` (add `FixedScannerAccess`)
- Test: `test/providers/member_pass/scanner_access_provider_test.dart`

**Interfaces:**
- Consumes:
  - From Task 5: `memberPassApiProvider` and `memberPassClockProvider`.
  - `membershipUserIdProvider`, and `MemberPassApiException`.
- Produces:
  - `sealed class ScannerAccessState` (Equatable), with five cases:
    - `ScannerGranted(ScannerAccess access)`
    - `ScannerDenied()`
    - `ScannerSignedOut()`
    - `ScannerNotConfigured()`
    - `ScannerCheckFailed()`
  - `final scannerAccessProvider = AsyncNotifierProvider<ScannerAccessNotifier, ScannerAccessState>`
  - `ScannerAccessNotifier` with `static const maxAge = Duration(minutes: 5)` and
    `Future<void> ensureFresh({bool force = false})`.
  - Test helper `class FixedScannerAccess extends ScannerAccessNotifier`, constructed as
    `FixedScannerAccess(ScannerAccessState? value)`. A null value never completes, which models
    loading. It has an `int freshCalls` counter.

- [ ] **Step 1: Add the fixed-access fake to the shared helper**

Append to `test/helpers/fake_member_pass_api.dart`. Add these imports to the top of the file:
`package:biso/providers/member_pass/scanner_access_provider.dart`.

```dart
/// A scanner access answer that never touches the network. A null value
/// stays loading forever.
class FixedScannerAccess extends ScannerAccessNotifier {
  FixedScannerAccess(this.value);

  final ScannerAccessState? value;
  int freshCalls = 0;
  int builds = 0;

  @override
  Future<ScannerAccessState> build() {
    builds++;
    final value = this.value;
    return value == null ? Completer<ScannerAccessState>().future : Future.value(value);
  }

  @override
  Future<void> ensureFresh({bool force = false}) async => freshCalls++;
}

const grantedAccess = ScannerGranted(
  ScannerAccess(dayColor: testDayColor),
);
```

(This helper will not compile until Step 4 creates the provider. That is expected, because Step 2's
test imports both.)

- [ ] **Step 2: Write the failing test**

```dart
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
    expect(
      c.read(scannerAccessProvider).valueOrNull,
      const ScannerDenied(),
    );
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/scanner_access_provider_test.dart`
Expected: FAIL, because the provider file does not exist.

- [ ] **Step 4: Write the implementation**

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';
import '../membership/membership_overview_provider.dart';
import 'member_pass_provider.dart';

/// Whether the signed-in user may scan passes, as the server says.
sealed class ScannerAccessState extends Equatable {
  const ScannerAccessState();

  @override
  List<Object?> get props => [];
}

class ScannerGranted extends ScannerAccessState {
  const ScannerGranted(this.access);

  final ScannerAccess access;

  @override
  List<Object?> get props => [access];
}

/// No active grant (or the route is not deployed yet).
class ScannerDenied extends ScannerAccessState {
  const ScannerDenied();
}

class ScannerSignedOut extends ScannerAccessState {
  const ScannerSignedOut();
}

/// The server has no pass secret configured.
class ScannerNotConfigured extends ScannerAccessState {
  const ScannerNotConfigured();
}

/// The server could not be asked. Never cached.
class ScannerCheckFailed extends ScannerAccessState {
  const ScannerCheckFailed();
}

final scannerAccessProvider =
    AsyncNotifierProvider<ScannerAccessNotifier, ScannerAccessState>(
      ScannerAccessNotifier.new,
    );

/// The scanner grant, kept in memory for [maxAge] and re-checked on resume.
/// `/scan` re-checks the grant on every scan, so this only decides what to
/// show.
class ScannerAccessNotifier extends AsyncNotifier<ScannerAccessState> {
  static const maxAge = Duration(minutes: 5);

  int? _checkedAtMs;
  int _generation = 0;

  int _now() => ref.read(memberPassClockProvider)();

  @override
  Future<ScannerAccessState> build() async {
    final generation = ++_generation;
    _checkedAtMs = null;
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ensureFresh()),
    );
    ref.onDispose(() {
      _generation++;
      lifecycle.dispose();
    });
    if (ref.watch(membershipUserIdProvider) == null) {
      return const ScannerSignedOut();
    }
    return _check(generation);
  }

  /// Asks the server again if the answer is older than [maxAge], failed, or
  /// [force] is set. The previous answer stays visible meanwhile.
  Future<void> ensureFresh({bool force = false}) async {
    if (ref.read(membershipUserIdProvider) == null) return;
    if (state.isLoading) return;
    final checkedAt = _checkedAtMs;
    final fresh =
        checkedAt != null &&
        _now() - checkedAt < maxAge.inMilliseconds &&
        state.valueOrNull is! ScannerCheckFailed;
    if (fresh && !force) return;

    final generation = _generation;
    state = const AsyncLoading<ScannerAccessState>().copyWithPrevious(state);
    final next = await _check(generation);
    if (generation != _generation) return;
    state = AsyncData(next);
  }

  Future<ScannerAccessState> _check(int generation) async {
    final startedAt = _now();
    final api = ref.read(memberPassApiProvider);
    ScannerAccessState result;
    try {
      result = ScannerGranted(await api.fetchScannerAccess());
    } on MemberPassApiException catch (error) {
      if (error.isUnauthorized) {
        result = const ScannerSignedOut();
      } else if (error.isForbidden || error.isNotFound) {
        result = const ScannerDenied();
      } else if (error.isNotConfigured) {
        result = const ScannerNotConfigured();
      } else {
        result = const ScannerCheckFailed();
      }
    } catch (_) {
      result = const ScannerCheckFailed();
    }
    if (generation == _generation) _checkedAtMs = startedAt;
    return result;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/scanner_access_provider_test.dart test/providers/member_pass`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
dart format lib/providers/member_pass/scanner_access_provider.dart test/helpers/fake_member_pass_api.dart test/providers/member_pass/scanner_access_provider_test.dart
git add lib/providers/member_pass/scanner_access_provider.dart test/helpers/fake_member_pass_api.dart test/providers/member_pass/scanner_access_provider_test.dart
git commit -m "Ask the server whether the user may scan passes

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 9: Scanner controller

**Files:**
- Create: `lib/providers/member_pass/scanner_controller.dart`
- Test: `test/providers/member_pass/scanner_controller_test.dart`

**Interfaces:**
- Consumes:
  - `ScanGate` (Task 6).
  - From Task 7: `ScannerDisplay`, `mapScanOutcome`, `mapScanError`, `overlongCodeResult` and
    `maxScanCodeLength`.
  - From Task 5: `memberPassApiProvider` and `memberPassClockProvider`.
  - `scannerAccessProvider` (Task 8).
- Produces:
  - `final scanHapticsProvider = Provider<void Function(ScanTone)>`
  - `final scannerControllerProvider = NotifierProvider.autoDispose<ScannerController, ScannerDisplay>`
  - `ScannerController` with `static const resultDuration = Duration(seconds: 3)`,
    `Future<void> onDetected(String raw)` and `void dismiss()`.

- [ ] **Step 1: Write the failing test**

```dart
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
      ..onScan = (_) => const ScanOutcome(
        result: ScanResult.valid,
        name: 'Alice',
      );
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/providers/member_pass/scanner_controller_test.dart`
Expected: FAIL, because `scanner_controller.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'member_pass_provider.dart';
import 'scan_display.dart';
import 'scan_gate.dart';
import 'scanner_access_provider.dart';

/// A different feel per result, so staff notice without looking.
final scanHapticsProvider = Provider<void Function(ScanTone)>(
  (ref) => (tone) {
    switch (tone) {
      case ScanTone.green:
        unawaited(HapticFeedback.mediumImpact());
      case ScanTone.orange || ScanTone.amber:
        unawaited(HapticFeedback.heavyImpact());
      case ScanTone.red:
        unawaited(HapticFeedback.vibrate());
      case ScanTone.grey:
        unawaited(HapticFeedback.selectionClick());
    }
  },
);

final scannerControllerProvider =
    NotifierProvider.autoDispose<ScannerController, ScannerDisplay>(
      ScannerController.new,
    );

/// Turns camera reads into scans and scans into what the screen shows.
/// Scanned strings are held only for the request and never logged.
class ScannerController extends AutoDisposeNotifier<ScannerDisplay> {
  static const resultDuration = Duration(seconds: 3);

  final ScanGate _gate = ScanGate();
  Timer? _dismissTimer;
  bool _disposed = false;

  @override
  ScannerDisplay build() {
    ref.onDispose(() {
      _disposed = true;
      _dismissTimer?.cancel();
    });
    return const ScannerIdle();
  }

  Future<void> onDetected(String raw) async {
    if (!_gate.admit(raw, ref.read(memberPassClockProvider)())) return;
    if (raw.length > maxScanCodeLength) {
      _show(overlongCodeResult);
      return;
    }
    state = const ScannerChecking();
    final api = ref.read(memberPassApiProvider);
    ScannerDisplay next;
    try {
      next = mapScanOutcome(await api.scan(raw));
    } catch (error) {
      next = mapScanError(error);
    }
    if (_disposed) return;
    if (next is ScannerResult) {
      _show(next);
    } else {
      state = next;
      ref.invalidate(scannerAccessProvider);
    }
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (state is ScannerResult) {
      _gate.finish();
      state = const ScannerIdle();
    }
  }

  void _show(ScannerResult result) {
    state = result;
    ref.read(scanHapticsProvider)(result.tone);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(resultDuration, dismiss);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/providers/member_pass/scanner_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
dart format lib/providers/member_pass/scanner_controller.dart test/providers/member_pass/scanner_controller_test.dart
git add lib/providers/member_pass/scanner_controller.dart test/providers/member_pass/scanner_controller_test.dart
git commit -m "Check scanned passes and show each result for three seconds

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 10: Strings (English and Norwegian)

**Files:**
- Create: `tool/add_member_pass_strings.py` (one-off, deleted in Step 4)
- Modify: `lib/generated/l10n/app_en.arb`, `lib/generated/l10n/app_no.arb`, plus the regenerated
  `app_localizations*.dart`
- Test: `test/l10n/member_pass_strings_test.dart`

**Interfaces:**
- Produces these `AppLocalizations` getters. Those with a parameter take the type shown.
  - **Pass:**
    - `memberPassTitle`, `memberPassRowSubtitle`, `memberPassShowAction`
    - `memberPassMemberLabel`, `memberPassSeasonSpring`, `memberPassSeasonFall`
    - `memberPassValidUntil(String date)`
    - `memberPassOffline`, `memberPassUpdating`, `memberPassTapToPresent`
    - `memberPassNextCodeIn(int seconds)`
  - **Pass states:**
    - `memberPassLinkTitle`, `memberPassLinkMessage`, `memberPassLinkAction`,
      `memberPassLinkFailed`
    - `memberPassNotMemberTitle`, `memberPassExpiredTitle`, `memberPassNotMemberMessage`,
      `memberPassBecomeMember`
    - `memberPassUnavailableTitle`, `memberPassUnavailableMessage`
    - `memberPassReconnectTitle`, `memberPassReconnectMessage`
    - `memberPassSignedOutTitle`, `memberPassSignIn`
  - **Wallet:**
    - `walletAddAppleLabel`, `walletAddGoogleLabel`, `walletAdded`
    - `walletErrorNotMember`, `walletErrorNotConfigured`, `walletErrorFailed`,
      `walletErrorInvalid`
  - **Day colors:** `dayColorRed`, `dayColorOrange`, `dayColorYellow`, `dayColorLime`,
    `dayColorGreen`, `dayColorTeal`, `dayColorCyan`, `dayColorBlue`, `dayColorIndigo`,
    `dayColorPurple`, `dayColorPink`, `dayColorBrown`
  - **Scanner:**
    - `scannerTitle`, `scannerSubtitle`, `scannerAccessUntil(String dateTime)`,
      `scannerPointCamera`, `scannerChecking`, `scannerTapToContinue`
    - Results: `scannerValid`, `scannerDuplicateSeconds(int seconds)`,
      `scannerDuplicateMinutes(int minutes)`, `scannerCheckId`
    - Reasons: `scannerBadCode`, `scannerStale`, `scannerExpired`, `scannerNotMember`,
      `scannerNotLinked`, `scannerNotValid`, `scannerUnavailable`, `scannerRateLimited`
    - Access: `scannerNoAccess`, `scannerSignedOut`, `scannerNotConfigured`,
      `scannerCheckFailed`, `scannerCameraError`
  - Existing and reused: `tryAgainMessage`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final no = lookupAppLocalizations(const Locale('no'));

  test('pass strings exist in both languages', () {
    expect(en.memberPassTitle, 'Member pass');
    expect(no.memberPassTitle, 'Medlemskort');
    expect(en.memberPassMemberLabel, 'MEMBER');
    expect(no.memberPassMemberLabel, 'MEDLEM');
    expect(no.memberPassSeasonFall, 'Høst');
    expect(en.memberPassValidUntil('31 Dec 2026'), 'Valid until 31 Dec 2026');
    expect(no.memberPassNextCodeIn(12), 'Ny kode om 12 s');
  });

  test('every day color has a Norwegian name', () {
    expect(no.dayColorTeal, 'Blågrønn');
    expect(no.dayColorPurple, 'Lilla');
    expect(en.dayColorIndigo, 'Indigo');
  });

  test('scanner strings exist in both languages', () {
    expect(en.scannerTitle, 'Scan memberships');
    expect(no.scannerTitle, 'Skann medlemskap');
    expect(en.scannerDuplicateSeconds(42), 'Already scanned 42s ago');
    expect(no.scannerDuplicateMinutes(3), 'Allerede skannet for 3 min siden');
    expect(en.scannerStale, 'Old code — ask them to reopen the pass');
    expect(
      en.scannerNoAccess,
      "You don't have scanning access. Ask BISO staff for an invitation.",
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/l10n/member_pass_strings_test.dart`
Expected: FAIL to compile, because the getters don't exist.

- [ ] **Step 3: Add the strings with a script and regenerate**

Create `tool/add_member_pass_strings.py`:

```python
"""One-off: adds the member pass strings to both ARB files."""
import json
from collections import OrderedDict

S = {
    # key: (en, no, placeholders or None)
    "memberPassTitle": ("Member pass", "Medlemskort", None),
    "memberPassRowSubtitle": ("Show your pass at events", "Vis kortet ditt på arrangementer", None),
    "memberPassShowAction": ("Show member pass", "Vis medlemskort", None),
    "memberPassMemberLabel": ("MEMBER", "MEDLEM", None),
    "memberPassSeasonSpring": ("Spring", "Vår", None),
    "memberPassSeasonFall": ("Fall", "Høst", None),
    "memberPassValidUntil": ("Valid until {date}", "Gyldig til {date}", {"date": {"type": "String"}}),
    "memberPassOffline": ("Offline", "Frakoblet", None),
    "memberPassUpdating": ("Updating…", "Oppdaterer …", None),
    "memberPassTapToPresent": ("Tap to show full screen", "Trykk for å vise i fullskjerm", None),
    "memberPassNextCodeIn": ("New code in {seconds}s", "Ny kode om {seconds} s", {"seconds": {"type": "int"}}),
    "memberPassLinkTitle": ("Link your BI student account", "Koble til BI-studentkontoen din", None),
    "memberPassLinkMessage": ("Your pass needs a linked BI account. You link it once, on biso.no.", "Medlemskortet krever en tilkoblet BI-konto. Du kobler den til én gang, på biso.no.", None),
    "memberPassLinkAction": ("Link on biso.no", "Koble til på biso.no", None),
    "memberPassLinkFailed": ("We could not open biso.no. Please try again.", "Vi kunne ikke åpne biso.no. Prøv igjen.", None),
    "memberPassNotMemberTitle": ("You're not a member", "Du er ikke medlem", None),
    "memberPassExpiredTitle": ("Your membership has ended", "Medlemskapet ditt er utløpt", None),
    "memberPassNotMemberMessage": ("Become a member to get your pass.", "Bli medlem for å få medlemskortet.", None),
    "memberPassBecomeMember": ("Become a member", "Bli medlem", None),
    "memberPassUnavailableTitle": ("Couldn't load your pass", "Kunne ikke laste medlemskortet", None),
    "memberPassUnavailableMessage": ("We couldn't check your membership right now.", "Vi kunne ikke sjekke medlemskapet ditt akkurat nå.", None),
    "memberPassReconnectTitle": ("Reconnect to show your pass", "Koble til internett for å vise kortet", None),
    "memberPassReconnectMessage": ("Your pass needs a connection to get new codes.", "Kortet trenger nett for å hente nye koder.", None),
    "memberPassSignedOutTitle": ("Sign in to see your pass", "Logg inn for å se medlemskortet", None),
    "memberPassSignIn": ("Sign in", "Logg inn", None),
    "walletAddAppleLabel": ("Add to Apple Wallet", "Legg til i Apple Lommebok", None),
    "walletAddGoogleLabel": ("Add to Google Wallet", "Legg til i Google Wallet", None),
    "walletAdded": ("Added to Wallet", "Lagt til i Lommebok", None),
    "walletErrorNotMember": ("Your membership isn't active.", "Medlemskapet ditt er ikke aktivt.", None),
    "walletErrorNotConfigured": ("Wallet isn't available yet.", "Lommebok er ikke tilgjengelig ennå.", None),
    "walletErrorFailed": ("Couldn't reach Wallet — try again.", "Fikk ikke kontakt med Lommebok – prøv igjen.", None),
    "walletErrorInvalid": ("The pass couldn't be read.", "Kortet kunne ikke leses.", None),
    "dayColorRed": ("Red", "Rød", None),
    "dayColorOrange": ("Orange", "Oransje", None),
    "dayColorYellow": ("Yellow", "Gul", None),
    "dayColorLime": ("Lime", "Lime", None),
    "dayColorGreen": ("Green", "Grønn", None),
    "dayColorTeal": ("Teal", "Blågrønn", None),
    "dayColorCyan": ("Cyan", "Cyan", None),
    "dayColorBlue": ("Blue", "Blå", None),
    "dayColorIndigo": ("Indigo", "Indigo", None),
    "dayColorPurple": ("Purple", "Lilla", None),
    "dayColorPink": ("Pink", "Rosa", None),
    "dayColorBrown": ("Brown", "Brun", None),
    "scannerTitle": ("Scan memberships", "Skann medlemskap", None),
    "scannerSubtitle": ("Check member passes at the door", "Sjekk medlemskort i døra", None),
    "scannerAccessUntil": ("Access until {dateTime}", "Tilgang til {dateTime}", {"dateTime": {"type": "String"}}),
    "scannerPointCamera": ("Point the camera at a member pass", "Rett kameraet mot et medlemskort", None),
    "scannerChecking": ("Checking…", "Sjekker …", None),
    "scannerTapToContinue": ("Tap to continue", "Trykk for å fortsette", None),
    "scannerValid": ("Valid member", "Gyldig medlem", None),
    "scannerDuplicateSeconds": ("Already scanned {seconds}s ago", "Allerede skannet for {seconds} s siden", {"seconds": {"type": "int"}}),
    "scannerDuplicateMinutes": ("Already scanned {minutes} min ago", "Allerede skannet for {minutes} min siden", {"minutes": {"type": "int"}}),
    "scannerCheckId": ("Wallet pass — check ID", "Lommebokkort – sjekk legitimasjon", None),
    "scannerBadCode": ("Not a BISO pass", "Ikke et BISO-kort", None),
    "scannerStale": ("Old code — ask them to reopen the pass", "Gammel kode – be dem åpne kortet på nytt", None),
    "scannerExpired": ("Membership has ended", "Medlemskapet er utløpt", None),
    "scannerNotMember": ("Not a member", "Ikke medlem", None),
    "scannerNotLinked": ("No linked student account", "Ingen tilkoblet studentkonto", None),
    "scannerNotValid": ("Not valid", "Ikke gyldig", None),
    "scannerUnavailable": ("Couldn't check — try again", "Kunne ikke sjekke – prøv igjen", None),
    "scannerRateLimited": ("Too many scans — wait a moment", "For mange skanninger – vent litt", None),
    "scannerNoAccess": ("You don't have scanning access. Ask BISO staff for an invitation.", "Du har ikke tilgang til å skanne. Be BISO om en invitasjon.", None),
    "scannerSignedOut": ("You've been signed out — sign in again", "Du er logget ut – logg inn igjen", None),
    "scannerNotConfigured": ("Scanning isn't available right now.", "Skanning er ikke tilgjengelig akkurat nå.", None),
    "scannerCheckFailed": ("Couldn't check your access", "Kunne ikke sjekke tilgangen din", None),
    "scannerCameraError": ("The camera couldn't start. Check camera access in Settings.", "Kameraet kunne ikke starte. Sjekk kameratilgang i Innstillinger.", None),
}

for path, index in (("lib/generated/l10n/app_en.arb", 0), ("lib/generated/l10n/app_no.arb", 1)):
    with open(path, encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=OrderedDict)
    for key, values in S.items():
        assert key not in data, f"{key} already in {path}"
        data[key] = values[index]
        meta = {"description": f"Member pass / scanner: {key}"}
        if values[2]:
            meta["placeholders"] = values[2]
        data["@" + key] = meta
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
```

Run:

```bash
python3 tool/add_member_pass_strings.py
flutter gen-l10n
```

Expected: `flutter gen-l10n` succeeds with no "untranslated" warnings for the new keys.

- [ ] **Step 4: Run the test, and check that the ARB diff only adds lines**

Run: `flutter test test/l10n/member_pass_strings_test.dart`
Expected: PASS

Run: `git diff --stat lib/generated/l10n/`
Expected: only additions in the two `.arb` files, apart from any reformatting that `json.dump`
causes.

If `json.dump` re-escaped or reordered existing entries (the diff shows `-` lines in the ARB
files), revert the ARB files with `git checkout lib/generated/l10n/*.arb` and add the entries by
hand before the closing `}` instead.

Delete the one-off script: `rm tool/add_member_pass_strings.py`

- [ ] **Step 5: Commit**

```bash
dart format test/l10n/member_pass_strings_test.dart
git add lib/generated/l10n test/l10n/member_pass_strings_test.dart
git commit -m "Add the member pass and scanner strings in English and Norwegian

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 11: Pass card widgets

**Files:**
- Create: `lib/presentation/widgets/member_pass/pass_colors.dart`
- Create: `lib/presentation/widgets/member_pass/pass_card.dart`
- Modify: `test/presentation/design_rules_test.dart` (add `pass_card.dart` to `migratedFiles`)
- Test: `test/presentation/widgets/member_pass/pass_card_test.dart`

**Interfaces:**
- Consumes:
  - From Task 4: `MemberPassView` and `PassStatus`.
  - `formatOsloClock` (Task 1), `DayColor` (Task 2), `ScanTone` / `ScanMessage` / `ScannerResult`
    (Task 7) and the Task 10 strings.
- Produces:
  - `abstract final class PassColors`, with the constants `card`, `cardInk`, `cardMuted`,
    `qrBackground`, `liveDot`, `holographic` (a `List<Color>`) and `scannerBackground`, plus
    `static Color scanTone(ScanTone)` and `static Color inkOn(Color background)`.
  - `String dayColorName(AppLocalizations l10n, String name)`
  - `String scanMessageText(AppLocalizations l10n, ScannerResult result)`
  - Widgets:
    - `PassCard({required MemberPassView view, VoidCallback? onTap, bool presentation = false})`
    - `HolographicBand({double height = 10})`
    - `LiveClock({DateTime? serverTime})`
    - `DayStripe({required DayColor dayColor})`
    - `PassQr({required String? code, required double size})`
    - `CountdownRing({required double progress, double size = 22})`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/presentation/widgets/member_pass/pass_colors.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

  MemberPassView viewAt(int now, {bool offline = false, bool withCode = true}) {
    final session = MemberPassSession()..apply(activePassAt(t0), t0);
    if (offline) session.applyTransientFailure(t0);
    final view = session.view(now);
    return withCode
        ? view
        : MemberPassView(
            status: view.status,
            pass: view.pass,
            serverTime: view.serverTime,
          );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the member label, term, color, QR, name and expiry', (
    tester,
  ) async {
    await pump(tester, PassCard(view: viewAt(t0 + 1000)));
    expect(find.text('MEMBER'), findsOneWidget);
    expect(find.text('Fall 2026'), findsOneWidget);
    expect(find.text('TEAL'), findsOneWidget);
    expect(find.text('Kari Nordmann'), findsOneWidget);
    expect(find.textContaining('Valid until'), findsOneWidget);
    expect(find.text('12:00:01'), findsOneWidget); // 10:00:01 UTC in CEST
    expect(
      tester.widget<PassQr>(find.byType(PassQr)).code,
      'v1.user-1.${t0 ~/ 30000}.sig',
    );
    expect(find.byType(HolographicBand), findsOneWidget);
    expect(find.byType(CountdownRing), findsOneWidget);
  });

  testWidgets('speaks Norwegian', (tester) async {
    await pump(
      tester,
      PassCard(view: viewAt(t0)),
      locale: const Locale('no'),
    );
    expect(find.text('MEDLEM'), findsOneWidget);
    expect(find.text('Høst 2026'), findsOneWidget);
    expect(find.text('BLÅGRØNN'), findsOneWidget);
  });

  testWidgets('shows the offline chip', (tester) async {
    await pump(tester, PassCard(view: viewAt(t0, offline: true)));
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('shows Updating when no code is valid', (tester) async {
    await pump(tester, PassCard(view: viewAt(t0, withCode: false)));
    expect(find.text('Updating…'), findsOneWidget);
    expect(tester.widget<PassQr>(find.byType(PassQr)).code, isNull);
  });

  testWidgets('taps open presentation, and the hint is hidden there', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, PassCard(view: viewAt(t0), onTap: () => taps++));
    expect(find.text('Tap to show full screen'), findsOneWidget);
    await tester.tap(find.byType(PassCard));
    expect(taps, 1);

    await pump(tester, PassCard(view: viewAt(t0), presentation: true));
    expect(find.text('Tap to show full screen'), findsNothing);
  });

  testWidgets('the band keeps moving, slower, under reduced motion', (
    tester,
  ) async {
    await pump(tester, const HolographicBand(), reduceMotion: true);
    final controller = tester
        .state<HolographicBandState>(find.byType(HolographicBand))
        .controller;
    expect(controller.isAnimating, isTrue);
    expect(controller.duration, HolographicBandState.reducedLoop);

    await pump(tester, const HolographicBand());
    expect(
      tester
          .state<HolographicBandState>(find.byType(HolographicBand))
          .controller
          .duration,
      HolographicBandState.loop,
    );
  });

  test('ink contrasts with the stripe', () {
    expect(PassColors.inkOn(const Color(0xFFFFE629)), const Color(0xFF111111));
    expect(PassColors.inkOn(const Color(0xFF3E63DD)), const Color(0xFFFFFFFF));
  });

  test('day color names fall back to the raw name', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final name in DayColor.names) {
      expect(dayColorName(en, name), isNot(name), reason: name);
    }
    expect(dayColorName(en, 'mauve'), 'mauve');
  });

  test('scan messages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    String text(ScanMessage m, {int? seconds}) => scanMessageText(
      en,
      ScannerResult(
        tone: ScanTone.orange,
        message: m,
        secondsSincePrevious: seconds,
      ),
    );
    expect(text(ScanMessage.duplicate, seconds: 42), 'Already scanned 42s ago');
    expect(text(ScanMessage.duplicate, seconds: 185), 'Already scanned 3 min ago');
    expect(text(ScanMessage.badCode), 'Not a BISO pass');
    expect(text(ScanMessage.rateLimited), 'Too many scans — wait a moment');
    for (final m in ScanMessage.values) {
      expect(text(m, seconds: 1), isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/widgets/member_pass/pass_card_test.dart`
Expected: FAIL, because the files do not exist.

- [ ] **Step 3: Write `pass_colors.dart`**

```dart
import 'package:flutter/painting.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scan_display.dart';

/// Fixed colors for the member pass and the scanner. They carry meaning
/// (a valid scan is green in any theme), so they stay outside BisoPalette.
abstract final class PassColors {
  static const card = Color(0xFF0B1F3A);
  static const cardInk = Color(0xFFFFFFFF);
  static const cardMuted = Color(0xB3FFFFFF);
  static const qrBackground = Color(0xFFFFFFFF);
  static const liveDot = Color(0xFF30D158);
  static const scannerBackground = Color(0xFF000000);

  /// The band's colors. The last repeats the first so the loop is seamless.
  static const holographic = [
    Color(0xFF7FDBFF),
    Color(0xFFB28DFF),
    Color(0xFFFF9EC7),
    Color(0xFFFFE08A),
    Color(0xFF8CF5C8),
    Color(0xFF7FDBFF),
  ];

  static Color scanTone(ScanTone tone) => switch (tone) {
    ScanTone.green => const Color(0xFF1E9E4A),
    ScanTone.orange => const Color(0xFFF07C00),
    ScanTone.amber => const Color(0xFFE0A800),
    ScanTone.red => const Color(0xFFD7263D),
    ScanTone.grey => const Color(0xFF5B6270),
  };

  /// Dark ink on light backgrounds, white otherwise.
  static Color inkOn(Color background) => background.computeLuminance() > 0.4
      ? const Color(0xFF111111)
      : const Color(0xFFFFFFFF);
}

String dayColorName(AppLocalizations l10n, String name) => switch (name) {
  'red' => l10n.dayColorRed,
  'orange' => l10n.dayColorOrange,
  'yellow' => l10n.dayColorYellow,
  'lime' => l10n.dayColorLime,
  'green' => l10n.dayColorGreen,
  'teal' => l10n.dayColorTeal,
  'cyan' => l10n.dayColorCyan,
  'blue' => l10n.dayColorBlue,
  'indigo' => l10n.dayColorIndigo,
  'purple' => l10n.dayColorPurple,
  'pink' => l10n.dayColorPink,
  'brown' => l10n.dayColorBrown,
  _ => name,
};

String scanMessageText(AppLocalizations l10n, ScannerResult result) =>
    switch (result.message) {
      ScanMessage.valid => l10n.scannerValid,
      ScanMessage.duplicate => _duplicate(l10n, result.secondsSincePrevious ?? 0),
      ScanMessage.checkId => l10n.scannerCheckId,
      ScanMessage.badCode => l10n.scannerBadCode,
      ScanMessage.stale => l10n.scannerStale,
      ScanMessage.expired => l10n.scannerExpired,
      ScanMessage.notMember => l10n.scannerNotMember,
      ScanMessage.notLinked => l10n.scannerNotLinked,
      ScanMessage.notValid => l10n.scannerNotValid,
      ScanMessage.unavailable => l10n.scannerUnavailable,
      ScanMessage.rateLimited => l10n.scannerRateLimited,
    };

String _duplicate(AppLocalizations l10n, int seconds) => seconds < 60
    ? l10n.scannerDuplicateSeconds(seconds)
    : l10n.scannerDuplicateMinutes(seconds ~/ 60);
```

Check the contrast threshold in the test: yellow `#FFE629` has a luminance of about 0.77 (dark
ink), and indigo `#3E63DD` about 0.15 (white ink).

- [ ] **Step 4: Write `pass_card.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/utils/oslo_time.dart';
import '../../../data/models/member_pass.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import 'pass_colors.dart';

/// The live member pass, built to match the web pass.
class PassCard extends StatelessWidget {
  const PassCard({
    super.key,
    required this.view,
    this.onTap,
    this.presentation = false,
  });

  final MemberPassView view;
  final VoidCallback? onTap;

  /// Full-screen mode: a larger QR and no "tap to present" hint.
  final bool presentation;

  @override
  Widget build(BuildContext context) {
    final pass = view.pass!;
    final holder = pass.holder;
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final term = holder.term?.label(
      spring: l10n.memberPassSeasonSpring,
      fall: l10n.memberPassSeasonFall,
    );
    final expiry = holder.expiryDate;
    final seconds = (view.msUntilNextSlot / 1000).ceil();

    return Semantics(
      button: onTap != null,
      label: l10n.memberPassTitle,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColoredBox(
            color: PassColors.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HolographicBand(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.memberPassMemberLabel,
                              style: text.displaySmall?.copyWith(
                                color: PassColors.cardInk,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 2,
                              ),
                            ),
                            if (term != null)
                              Text(
                                term,
                                style: text.titleMedium?.copyWith(
                                  color: PassColors.cardMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      LiveClock(serverTime: view.serverTime),
                    ],
                  ),
                ),
                DayStripe(dayColor: pass.dayColor),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final qrSize = math.min(
                        constraints.maxWidth - 24,
                        presentation ? 340.0 : 260.0,
                      );
                      return Column(
                        children: [
                          Center(
                            child: PassQr(code: view.code, size: qrSize),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CountdownRing(
                                progress: view.msUntilNextSlot / passSlotMs,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.memberPassNextCodeIn(seconds),
                                style: text.bodySmall?.copyWith(
                                  color: PassColors.cardMuted,
                                ),
                              ),
                              if (view.offline) ...[
                                const SizedBox(width: 8),
                                _OfflineChip(label: l10n.memberPassOffline),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        holder.name,
                        style: text.titleLarge?.copyWith(
                          color: PassColors.cardInk,
                        ),
                      ),
                      Text(
                        holder.membershipName,
                        style: text.bodyMedium?.copyWith(
                          color: PassColors.cardMuted,
                        ),
                      ),
                      if (expiry != null)
                        Text(
                          l10n.memberPassValidUntil(
                            DateFormat.yMMMd(locale).format(expiry),
                          ),
                          style: text.bodyMedium?.copyWith(
                            color: PassColors.cardMuted,
                          ),
                        ),
                      if (!presentation && onTap != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.memberPassTapToPresent,
                          style: text.bodySmall?.copyWith(
                            color: PassColors.cardMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: PassColors.cardMuted),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.wifi_slash,
              size: 12,
              color: PassColors.cardInk,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: PassColors.cardInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// A moving holographic band. It never stops: under reduced motion it moves
/// slower, so a screenshot is still told apart from a live pass.
class HolographicBand extends StatefulWidget {
  const HolographicBand({super.key, this.height = 10});

  final double height;

  @override
  State<HolographicBand> createState() => HolographicBandState();
}

@visibleForTesting
class HolographicBandState extends State<HolographicBand>
    with SingleTickerProviderStateMixin {
  static const loop = Duration(seconds: 6);
  static const reducedLoop = Duration(seconds: 24);

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: loop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? reducedLoop
        : loop;
    if (controller.duration != duration || !controller.isAnimating) {
      controller
        ..duration = duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(painter: _BandPainter(controller)),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = animation.value * size.width;
    final colors = PassColors.holographic;
    final stops = [
      for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
    ];
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(dx, 0),
        Offset(dx + size.width, 0),
        colors,
        stops,
        TileMode.repeated,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BandPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

/// HH:MM:SS in Oslo, by the server's clock, with a pulsing live dot.
class LiveClock extends StatelessWidget {
  const LiveClock({super.key, this.serverTime});

  final DateTime? serverTime;

  @override
  Widget build(BuildContext context) {
    final time = serverTime;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _LiveDot(),
        const SizedBox(width: 6),
        Text(
          time == null ? '--:--:--' : formatOsloClock(time),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: PassColors.cardInk,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 1200);
    if (_controller.duration != duration) {
      _controller
        ..duration = duration
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: PassColors.liveDot,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
    );
  }
}

/// Today's color, named, across the full width.
class DayStripe extends StatelessWidget {
  const DayStripe({super.key, required this.dayColor});

  final DayColor dayColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = dayColor.color;
    return ColoredBox(
      color: color,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Text(
            dayColorName(l10n, dayColor.name).toUpperCase(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: PassColors.inkOn(color),
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The QR of the raw code on a white quiet zone. The code is never put in
/// semantics, so screen readers do not read it out.
class PassQr extends StatelessWidget {
  const PassQr({super.key, required this.code, required this.size});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PassColors.qrBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: size,
          child: code == null
              ? Center(
                  child: Text(AppLocalizations.of(context)!.memberPassUpdating),
                )
              : ExcludeSemantics(
                  child: QrImageView(
                    data: code,
                    size: size,
                    padding: EdgeInsets.zero,
                    backgroundColor: PassColors.qrBackground,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
        ),
      ),
    );
  }
}

/// How much of the current code's 30 seconds is left.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, this.size = 22});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RingPainter(progress.clamp(0.0, 1.0))),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final track = Paint()
      ..color = PassColors.cardMuted.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final arc = Paint()
      ..color = PassColors.cardInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
```

- [ ] **Step 5: Add `pass_card.dart` to `migratedFiles`**

In `test/presentation/design_rules_test.dart`, add this line before the closing `];` of
`migratedFiles`:

```dart
  'lib/presentation/widgets/member_pass/pass_card.dart',
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/presentation/widgets/member_pass/pass_card_test.dart test/presentation/design_rules_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
dart format lib/presentation/widgets/member_pass test/presentation/widgets/member_pass/pass_card_test.dart test/presentation/design_rules_test.dart
git add lib/presentation/widgets/member_pass test/presentation/widgets/member_pass/pass_card_test.dart test/presentation/design_rules_test.dart
git commit -m "Draw the live member pass card

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 12: Presentation mode (brightness and wakelock)

**Files:**
- Modify: `pubspec.yaml` (add `wakelock_plus` and `screen_brightness`)
- Create: `lib/data/services/screen_presentation.dart`
- Modify: `lib/providers/member_pass/member_pass_provider.dart` (add `screenPresentationProvider`)
- Create: `lib/presentation/screens/profile/member_pass_presentation.dart`
- Modify: `test/helpers/fake_member_pass_api.dart` (add `activeView`, `FixedMemberPass` and
  `FakeScreenPresentation`)
- Modify: `test/presentation/design_rules_test.dart` (add the new screen file)
- Test: `test/presentation/screens/profile/member_pass_presentation_test.dart`

**Interfaces:**
- Consumes: `memberPassProvider` and `MemberPassNotifier.hold()` (Task 5); `PassCard` and
  `PassColors` (Task 11).
- Produces:
  - `abstract interface class ScreenPresentation { Future<void> enter(); Future<void> exit(); }`
    and `class DeviceScreenPresentation implements ScreenPresentation`.
  - `final screenPresentationProvider = Provider<ScreenPresentation>`
  - `Future<void> showPassPresentation(BuildContext context)` and
    `class MemberPassPresentation extends ConsumerStatefulWidget`.
  - Test helpers:
    - `MemberPassView activeView({bool offline = false, WalletAvailability wallets = const WalletAvailability(apple: true, google: true)})`
    - `FixedMemberPass(MemberPassView view)`, with `retries` and `holds` counters.
    - `FakeScreenPresentation`, with `enters` and `exits` counters.

- [ ] **Step 1: Add the dependencies**

Run:

```bash
flutter pub add wakelock_plus screen_brightness
```

Expected: both packages resolve. If `wakelock_plus`'s newest version needs a newer Dart SDK than
this project allows, pub picks an older compatible one; accept what it chooses.

- [ ] **Step 2: Extend the shared test helper**

Add these imports to `test/helpers/fake_member_pass_api.dart`:

```dart
import 'package:biso/data/services/screen_presentation.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Append:

```dart
/// 10:00:00 UTC on 17 September 2026, the moment test passes are made for.
final testPassNow = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

MemberPassView activeView({
  bool offline = false,
  WalletAvailability wallets = const WalletAvailability(
    apple: true,
    google: true,
  ),
}) {
  final session = MemberPassSession()
    ..apply(activePassAt(testPassNow, wallets: wallets), testPassNow);
  if (offline) session.applyTransientFailure(testPassNow);
  return session.view(testPassNow);
}

/// A pass notifier that shows [view] and never starts timers or fetches.
class FixedMemberPass extends MemberPassNotifier {
  FixedMemberPass(this.view);

  final MemberPassView view;
  int retries = 0;
  int holds = 0;

  @override
  MemberPassView build() => view;

  @override
  Future<void> retry() async => retries++;

  @override
  KeepAliveLink hold() {
    holds++;
    return super.hold();
  }
}

class FakeScreenPresentation implements ScreenPresentation {
  int enters = 0;
  int exits = 0;

  @override
  Future<void> enter() async => enters++;

  @override
  Future<void> exit() async => exits++;
}
```

- [ ] **Step 3: Write the failing test**

```dart
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

void main() {
  late FakeScreenPresentation screen;
  late FixedMemberPass pass;

  Future<void> openPresentation(WidgetTester tester) async {
    screen = FakeScreenPresentation();
    pass = FixedMemberPass(activeView());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberPassProvider.overrideWith(() => pass),
          screenPresentationProvider.overrideWithValue(screen),
        ],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPassPresentation(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('shows the pass full screen and holds the codes', (
    tester,
  ) async {
    await openPresentation(tester);
    expect(find.byType(MemberPassPresentation), findsOneWidget);
    final card = tester.widget<PassCard>(find.byType(PassCard));
    expect(card.presentation, isTrue);
    expect(pass.holds, 1);
    expect(screen.enters, 1);
    expect(screen.exits, 0);
  });

  testWidgets('restores the screen in the background and on close', (
    tester,
  ) async {
    await openPresentation(tester);

    lifecycle(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(screen.exits, 1);

    lifecycle(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(screen.enters, 2);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsNothing);
    expect(screen.exits, 2);
  });

  testWidgets('a tap anywhere closes it', (tester) async {
    await openPresentation(tester);
    await tester.tapAt(const Offset(20, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsNothing);
    expect(screen.exits, 1);
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/profile/member_pass_presentation_test.dart`
Expected: FAIL, because the files do not exist.

- [ ] **Step 5: Write the service and the provider**

`lib/data/services/screen_presentation.dart`:

```dart
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Makes the screen easy to scan: awake and bright. [exit] undoes both.
abstract interface class ScreenPresentation {
  Future<void> enter();
  Future<void> exit();
}

/// Uses the app-level brightness, so the system setting is never changed.
class DeviceScreenPresentation implements ScreenPresentation {
  @override
  Future<void> enter() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Unsupported device: the pass still shows.
    }
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
    } catch (_) {
      // Unsupported device: the pass still shows.
    }
  }

  @override
  Future<void> exit() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {
      // Nothing to restore.
    }
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Nothing to restore.
    }
  }
}
```

In `lib/providers/member_pass/member_pass_provider.dart`, add the import
`import '../../data/services/screen_presentation.dart';` and, below `connectivityChangesProvider`:

```dart
final screenPresentationProvider = Provider<ScreenPresentation>(
  (ref) => DeviceScreenPresentation(),
);
```

- [ ] **Step 6: Write the presentation route**

`lib/presentation/screens/profile/member_pass_presentation.dart`:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/screen_presentation.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import '../../widgets/member_pass/pass_card.dart';
import '../../widgets/member_pass/pass_colors.dart';

/// Shows the pass full screen, above the tab bar.
Future<void> showPassPresentation(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => const MemberPassPresentation(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The pass, large, with the screen kept awake and at full brightness.
/// Both are undone whenever the app leaves the foreground and when this
/// closes, so a forgotten presentation never leaves the phone bright.
class MemberPassPresentation extends ConsumerStatefulWidget {
  const MemberPassPresentation({super.key});

  @override
  ConsumerState<MemberPassPresentation> createState() =>
      _MemberPassPresentationState();
}

class _MemberPassPresentationState
    extends ConsumerState<MemberPassPresentation>
    with WidgetsBindingObserver {
  KeepAliveLink? _hold;
  late final ScreenPresentation _screen;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _hold = ref.read(memberPassProvider.notifier).hold();
    _screen = ref.read(screenPresentationProvider);
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _apply();
    } else {
      _restore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restore();
    _hold?.close();
    super.dispose();
  }

  void _apply() {
    if (_applied) return;
    _applied = true;
    unawaited(_screen.enter());
  }

  void _restore() {
    if (!_applied) return;
    _applied = false;
    unawaited(_screen.exit());
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(memberPassProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: PassColors.card,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 300) _close();
              },
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: view.status == PassStatus.active
                      ? PassCard(view: view, presentation: true)
                      : Text(
                          l10n.memberPassUnavailableTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: PassColors.cardInk),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: _close,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  color: PassColors.cardInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

In `test/presentation/design_rules_test.dart`, add the following line to `migratedFiles`:

```dart
  'lib/presentation/screens/profile/member_pass_presentation.dart',
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/presentation/screens/profile/member_pass_presentation_test.dart test/presentation/design_rules_test.dart`
Expected: PASS.

If the lifecycle helper trips an assertion about an invalid transition, check which state the
test binding starts in (`tester.binding.lifecycleState`) and begin the sequence from there.

- [ ] **Step 8: Commit**

```bash
dart format lib/data/services/screen_presentation.dart lib/providers/member_pass/member_pass_provider.dart lib/presentation/screens/profile/member_pass_presentation.dart test/helpers/fake_member_pass_api.dart test/presentation/screens/profile/member_pass_presentation_test.dart test/presentation/design_rules_test.dart
git add pubspec.yaml pubspec.lock lib/data/services/screen_presentation.dart lib/providers/member_pass/member_pass_provider.dart lib/presentation/screens/profile/member_pass_presentation.dart test/helpers/fake_member_pass_api.dart test/presentation/screens/profile/member_pass_presentation_test.dart test/presentation/design_rules_test.dart
git commit -m "Show the pass full screen, bright and awake

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 13: Member pass screen, route and entry points

**Files:**
- Create: `lib/presentation/screens/profile/member_pass_screen.dart`
- Create: `lib/presentation/widgets/member_pass/member_pass_row.dart`
- Modify:
  - `lib/main.dart`: add the `/profile/member-pass` child route.
  - `lib/presentation/screens/profile/profile_screen.dart`: add the row after `const _MembershipRow(),`.
  - `lib/presentation/screens/profile/membership_screen.dart`: add a row in `_MembershipCard`.
  - `test/presentation/design_rules_test.dart`: add the two new files.

  `MemberPassRow` does not watch the pass, so the existing Profile tests need no new overrides.
  Step 6 confirms this.
- Test: `test/presentation/screens/profile/member_pass_screen_test.dart`

**Interfaces:**
- Consumes:
  - From Task 5: `memberPassProvider`, `MemberPassNotifier.hold()` and `retry()`.
  - `showPassPresentation` (Task 12) and `PassCard` (Task 11).
  - `membershipOverviewProvider.notifier.noteLinkStarted()`.
  - `membershipUrlLauncherProvider` from `lib/providers/membership/membership_checkout_provider.dart`.
  - `membershipLinkUrl` from `lib/presentation/screens/profile/membership_screen.dart`.
- Produces:
  - `class MemberPassScreen extends ConsumerStatefulWidget`, at route `/profile/member-pass` (name
    `member-pass`).
  - `class MemberPassRow extends StatelessWidget`, which pushes `/profile/member-pass`.
  - `const memberPassPath = '/profile/member-pass'`, defined in `member_pass_row.dart`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/screens/profile/member_pass_screen.dart';
import 'package:biso/presentation/screens/profile/membership_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/presentation/widgets/member_pass/member_pass_row.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart';

class _Overview extends MembershipOverviewNotifier {
  bool linkNoted = false;

  @override
  Future<MembershipOverview?> build() async => null;

  @override
  void noteLinkStarted() => linkNoted = true;
}

MemberPassView _noPass(NoPassState state) =>
    MemberPassView(status: PassStatus.noPass, noPassState: state);

void main() {
  late FixedMemberPass pass;
  late _Overview overview;
  late List<Uri> launched;

  List<Override> overrides(MemberPassView view) {
    pass = FixedMemberPass(view);
    overview = _Overview();
    launched = [];
    return [
      memberPassProvider.overrideWith(() => pass),
      membershipOverviewProvider.overrideWith(() => overview),
      membershipUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
    ];
  }

  Future<GoRouter> pumpRouted(WidgetTester tester, MemberPassView view) async {
    final router = GoRouter(
      initialLocation: '/profile/member-pass',
      routes: [
        GoRoute(
          path: '/profile/member-pass',
          builder: (_, _) => const MemberPassScreen(),
        ),
        GoRoute(
          path: '/profile/membership',
          builder: (_, _) => const Scaffold(body: Text('Membership screen')),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (_, _) => const Scaffold(body: Text('Login screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(view),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return router;
  }

  testWidgets('builds cleanly in every appearance', (tester) async {
    for (final view in [
      activeView(),
      const MemberPassView(status: PassStatus.loading),
      _noPass(NoPassState.notMember),
    ]) {
      await expectBuildsCleanly(
        tester,
        () => const MemberPassScreen(),
        overrides: overrides(view),
      );
    }
  });

  testWidgets('active shows the card and holds the codes', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(activeView()),
    );
    expect(find.byType(PassCard), findsOneWidget);
    expect(pass.holds, 1);
  });

  testWidgets('tapping the card opens presentation mode', (tester) async {
    await pumpRouted(tester, activeView());
    await tester.tap(find.byType(PassCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsOneWidget);
  });

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(const MemberPassView(status: PassStatus.loading)),
    );
    expect(find.byType(BisoSkeleton), findsOneWidget);
  });

  final messages = <String, (MemberPassView, String, String)>{
    'no BI identity': (
      _noPass(NoPassState.noBiIdentity),
      'Link your BI student account',
      'Link on biso.no',
    ),
    'not a member': (
      _noPass(NoPassState.notMember),
      "You're not a member",
      'Become a member',
    ),
    'expired': (
      _noPass(NoPassState.expired),
      'Your membership has ended',
      'Become a member',
    ),
    'unavailable': (
      _noPass(NoPassState.unavailable),
      "Couldn't load your pass",
      'Try again',
    ),
    'reconnect': (
      const MemberPassView(status: PassStatus.reconnect, offline: true),
      'Reconnect to show your pass',
      'Try again',
    ),
    'signed out': (
      const MemberPassView(status: PassStatus.signedOut),
      'Sign in to see your pass',
      'Sign in',
    ),
  };
  messages.forEach((name, entry) {
    final (view, title, action) = entry;
    testWidgets('$name shows its message', (tester) async {
      await pumpBisoScreen(
        tester,
        const MemberPassScreen(),
        overrides: overrides(view),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(FilledButton, action), findsOneWidget);
      expect(find.byType(PassCard), findsNothing);
    });
  });

  testWidgets('Try again retries', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(
        const MemberPassView(status: PassStatus.reconnect, offline: true),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    expect(pass.retries, 1);
  });

  testWidgets('Try again is disabled while a fetch runs', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(
        const MemberPassView(status: PassStatus.reconnect, fetching: true),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Try again'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('linking opens biso.no and notes it for the re-check', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(_noPass(NoPassState.noBiIdentity)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Link on biso.no'));
    await tester.pump();
    expect(launched, [membershipLinkUrl]);
    expect(overview.linkNoted, isTrue);
  });

  testWidgets('Become a member opens the membership screen', (tester) async {
    await pumpRouted(tester, _noPass(NoPassState.expired));
    await tester.tap(find.widgetWithText(FilledButton, 'Become a member'));
    await tester.pumpAndSettle();
    expect(find.text('Membership screen'), findsOneWidget);
  });

  testWidgets('Sign in opens the login screen', (tester) async {
    await pumpRouted(
      tester,
      const MemberPassView(status: PassStatus.signedOut),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('the Profile row opens the pass', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: MemberPassRow()),
        ),
        GoRoute(
          path: memberPassPath,
          builder: (_, _) => const Scaffold(body: Text('Pass screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Member pass'), findsOneWidget);
    await tester.tap(find.byType(MemberPassRow));
    await tester.pumpAndSettle();
    expect(find.text('Pass screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/profile/member_pass_screen_test.dart`
Expected: FAIL, because the files do not exist.

- [ ] **Step 3: Write the row and the screen**

`lib/presentation/widgets/member_pass/member_pass_row.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../biso/biso.dart';

const memberPassPath = '/profile/member-pass';

/// Opens the member pass from Profile.
class MemberPassRow extends StatelessWidget {
  const MemberPassRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BisoListRow(
      leading: const BisoIconTile(
        icon: CupertinoIcons.qrcode,
        accent: BisoAccent.gold,
      ),
      title: l10n.memberPassTitle,
      subtitle: l10n.memberPassRowSubtitle,
      onTap: () => context.push(memberPassPath),
    );
  }
}
```

`lib/presentation/screens/profile/member_pass_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/member_pass.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/member_pass/pass_card.dart';
import 'member_pass_presentation.dart';
import 'membership_screen.dart' show membershipLinkUrl;

/// The signed-in member's live pass, or why there is none.
class MemberPassScreen extends ConsumerStatefulWidget {
  const MemberPassScreen({super.key});

  @override
  ConsumerState<MemberPassScreen> createState() => _MemberPassScreenState();
}

class _MemberPassScreenState extends ConsumerState<MemberPassScreen> {
  KeepAliveLink? _hold;

  @override
  void initState() {
    super.initState();
    _hold = ref.read(memberPassProvider.notifier).hold();
  }

  @override
  void dispose() {
    _hold?.close();
    super.dispose();
  }

  Future<void> _openLinkPage() async {
    ref.read(membershipOverviewProvider.notifier).noteLinkStarted();
    final opened = await ref.read(membershipUrlLauncherProvider)(
      membershipLinkUrl,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.memberPassLinkFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final view = ref.watch(memberPassProvider);
    final notifier = ref.read(memberPassProvider.notifier);
    final VoidCallback? retry = view.fetching
        ? null
        : () => unawaited(notifier.retry());

    Widget message({
      required IconData icon,
      required String title,
      String? body,
      required String action,
      required VoidCallback? onPressed,
      BisoAccent accent = BisoAccent.neutral,
    }) {
      return BisoEmptyState(
        icon: icon,
        title: title,
        message: body,
        accent: accent,
        action: FilledButton(onPressed: onPressed, child: Text(action)),
      );
    }

    final Widget body = switch (view.status) {
      PassStatus.loading => const BisoSkeleton.card(),
      PassStatus.active => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PassCard(
            view: view,
            onTap: () => unawaited(showPassPresentation(context)),
          ),
        ],
      ),
      PassStatus.signedOut => message(
        icon: CupertinoIcons.person_crop_circle,
        title: l10n.memberPassSignedOutTitle,
        action: l10n.memberPassSignIn,
        onPressed: () => context.go('/auth/login'),
      ),
      PassStatus.reconnect => message(
        icon: CupertinoIcons.wifi_slash,
        title: l10n.memberPassReconnectTitle,
        body: l10n.memberPassReconnectMessage,
        action: l10n.tryAgainMessage,
        onPressed: retry,
      ),
      PassStatus.noPass => switch (view.noPassState) {
        NoPassState.noBiIdentity => message(
          icon: CupertinoIcons.link,
          title: l10n.memberPassLinkTitle,
          body: l10n.memberPassLinkMessage,
          action: l10n.memberPassLinkAction,
          onPressed: () => unawaited(_openLinkPage()),
          accent: BisoAccent.gold,
        ),
        NoPassState.notMember || NoPassState.expired => message(
          icon: CupertinoIcons.checkmark_seal,
          title: view.noPassState == NoPassState.expired
              ? l10n.memberPassExpiredTitle
              : l10n.memberPassNotMemberTitle,
          body: l10n.memberPassNotMemberMessage,
          action: l10n.memberPassBecomeMember,
          onPressed: () => context.push('/profile/membership'),
          accent: BisoAccent.gold,
        ),
        NoPassState.unavailable || null => message(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: l10n.memberPassUnavailableTitle,
          body: l10n.memberPassUnavailableMessage,
          action: l10n.tryAgainMessage,
          onPressed: retry,
        ),
      },
    };

    return BisoPage(
      title: l10n.memberPassTitle,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverToBoxAdapter(child: body),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Wire the route and the entry points**

In `lib/main.dart`, import `presentation/screens/profile/member_pass_screen.dart`. In the
`/profile` route's `routes:` list, after the `/membership` `GoRoute`, add:

```dart
            GoRoute(
              path: '/member-pass',
              name: 'member-pass',
              builder: (context, state) => const MemberPassScreen(),
            ),
```

In `lib/presentation/screens/profile/profile_screen.dart`, import
`../../widgets/member_pass/member_pass_row.dart` and replace `const _MembershipRow(),` with:

```dart
                const _MembershipRow(),
                const MemberPassRow(),
```

In `lib/presentation/screens/profile/membership_screen.dart`, import
`../../../generated/l10n/app_localizations.dart` (if it is not already imported) and
`../../widgets/member_pass/member_pass_row.dart`. In `_MembershipCard.build`, add this as the
last child of the `BisoListGroup`, after the `Student ID` row:

```dart
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.qrcode,
              accent: BisoAccent.gold,
            ),
            title: AppLocalizations.of(context)!.memberPassShowAction,
            onTap: () => context.push(memberPassPath),
          ),
```

In `test/presentation/design_rules_test.dart`, add these lines to `migratedFiles`:

```dart
  'lib/presentation/screens/profile/member_pass_screen.dart',
  'lib/presentation/widgets/member_pass/member_pass_row.dart',
```

- [ ] **Step 5: Run the new tests**

Run: `flutter test test/presentation/screens/profile/member_pass_screen_test.dart test/presentation/design_rules_test.dart`
Expected: PASS

- [ ] **Step 6: Run the neighbouring screen tests**

Run: `flutter test test/presentation/screens/profile`
Expected: PASS. If `membership_screen_test.dart` has an assertion that counts the rows in the
member card, update that count by one. Nothing else should change.

- [ ] **Step 7: Commit**

```bash
dart format lib/main.dart lib/presentation/screens/profile lib/presentation/widgets/member_pass test/presentation/screens/profile/member_pass_screen_test.dart test/presentation/design_rules_test.dart
git add lib/main.dart lib/presentation/screens/profile lib/presentation/widgets/member_pass test/presentation/screens/profile test/presentation/design_rules_test.dart
git commit -m "Add the member pass screen to Profile

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 14: Add to Wallet (iOS channel, Android save link, badges)

**Files:**
- Create: `lib/data/services/wallet_channel.dart`
- Modify: `lib/providers/member_pass/member_pass_provider.dart` (add `walletChannelProvider` and
  `canAddApplePassesProvider`)
- Create: `lib/presentation/widgets/member_pass/wallet_buttons.dart`
- Modify: `lib/presentation/screens/profile/member_pass_screen.dart` (show `WalletButtons` under
  the card)
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `pubspec.yaml` (declare the four badge assets)
- Modify: `test/presentation/design_rules_test.dart`
- Test: `test/presentation/widgets/member_pass/wallet_buttons_test.dart`

**Interfaces:**
- Consumes:
  - From Task 3: `MemberPassApi.fetchApplePass()`, `fetchGoogleSaveUrl()` and
    `MemberPassApiException`.
  - `membershipUrlLauncherProvider`; `memberPassProvider.notifier.retry()`.
- Produces:
  - `enum WalletAddResult { added, cancelled }`
  - `class WalletChannel` with `const WalletChannel([MethodChannel channel])`,
    `Future<bool> canAddPasses()` and `Future<WalletAddResult> addPass(Uint8List bytes)`.
    `addPass` throws `PlatformException(code: 'invalid_pass')` when PassKit rejects the file.
  - `final walletChannelProvider = Provider<WalletChannel>`
  - `final canAddApplePassesProvider = FutureProvider.autoDispose<bool>`
  - `WalletButtons({required WalletAvailability wallets})`
  - `const appleWalletBadge = {'en': ..., 'no': ...}` and `const googleWalletBadge`, both asset
    path maps.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/data/services/wallet_channel.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/member_pass/wallet_buttons.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_member_pass_api.dart';

class _FakeWallet implements WalletChannel {
  bool canAdd = true;
  Object? addError;
  WalletAddResult result = WalletAddResult.added;
  final added = <Uint8List>[];

  @override
  Future<bool> canAddPasses() async => canAdd;

  @override
  Future<WalletAddResult> addPass(Uint8List bytes) async {
    added.add(bytes);
    if (addError != null) throw addError!;
    return result;
  }
}

void main() {
  late FakeMemberPassApi api;
  late _FakeWallet wallet;
  late List<Uri> launched;
  late FixedMemberPass pass;

  setUp(() {
    api = FakeMemberPassApi()
      ..onFetchApplePass = () => Uint8List.fromList([1, 2, 3])
      ..onFetchGoogleSaveUrl = () =>
          Uri.parse('https://pay.google.com/gp/v/save/x');
    wallet = _FakeWallet();
    launched = [];
    pass = FixedMemberPass(activeView());
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> pump(
    WidgetTester tester, {
    required TargetPlatform platform,
    WalletAvailability wallets = const WalletAvailability(
      apple: true,
      google: true,
    ),
    Locale locale = const Locale('en'),
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberPassApiProvider.overrideWithValue(api),
          walletChannelProvider.overrideWithValue(wallet),
          memberPassProvider.overrideWith(() => pass),
          membershipUrlLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(body: WalletButtons(wallets: wallets)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  String? badge(WidgetTester tester) {
    final finder = find.byType(SvgPicture);
    if (finder.evaluate().isEmpty) return null;
    final loader = tester.widget<SvgPicture>(finder).bytesLoader;
    return (loader as SvgAssetLoader).assetName;
  }

  testWidgets('iOS shows the Apple badge in the app language', (tester) async {
    await pump(tester, platform: TargetPlatform.iOS);
    expect(badge(tester), appleWalletBadge['en']);
    await pump(tester, platform: TargetPlatform.iOS, locale: const Locale('no'));
    expect(badge(tester), appleWalletBadge['no']);
  });

  testWidgets('iOS hides the badge when the flag is off or Wallet cannot add', (
    tester,
  ) async {
    await pump(
      tester,
      platform: TargetPlatform.iOS,
      wallets: const WalletAvailability(apple: false, google: true),
    );
    expect(badge(tester), isNull);

    wallet.canAdd = false;
    await pump(tester, platform: TargetPlatform.iOS);
    expect(badge(tester), isNull);
  });

  testWidgets('Android shows only the Google badge', (tester) async {
    await pump(tester, platform: TargetPlatform.android);
    expect(badge(tester), googleWalletBadge['en']);

    await pump(
      tester,
      platform: TargetPlatform.android,
      wallets: const WalletAvailability(apple: true, google: false),
    );
    expect(badge(tester), isNull);
  });

  testWidgets('adding on iOS hands the pass to Wallet and says so', (
    tester,
  ) async {
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture));
    await tester.pump();
    await tester.pump();
    expect(api.applePassCalls, 1);
    expect(wallet.added.single, [1, 2, 3]);
    expect(find.text('Added to Wallet'), findsOneWidget);
    expect(badge(tester), isNull);
  });

  testWidgets('a cancelled sheet keeps the badge', (tester) async {
    wallet.result = WalletAddResult.cancelled;
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture));
    await tester.pump();
    await tester.pump();
    expect(find.text('Added to Wallet'), findsNothing);
    expect(badge(tester), appleWalletBadge['en']);
  });

  testWidgets('a rejected pass explains itself', (tester) async {
    wallet.addError = PlatformException(code: 'invalid_pass');
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture));
    await tester.pump();
    await tester.pump();
    expect(find.text("The pass couldn't be read."), findsOneWidget);
  });

  testWidgets('server refusals explain themselves', (tester) async {
    for (final (status, text) in [
      (403, "Your membership isn't active."),
      (404, "Wallet isn't available yet."),
      (500, "Couldn't reach Wallet — try again."),
    ]) {
      api.onFetchApplePass = () =>
          throw MemberPassApiException('x', statusCode: status);
      await pump(tester, platform: TargetPlatform.iOS);
      await tester.tap(find.byType(SvgPicture));
      await tester.pump();
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: '$status');
      ScaffoldMessenger.of(
        tester.element(find.byType(WalletButtons)),
      ).removeCurrentSnackBar();
      await tester.pump();
    }
  });

  testWidgets('a 401 lets the pass screen re-check the session', (
    tester,
  ) async {
    api.onFetchApplePass = () =>
        throw const MemberPassApiException('x', statusCode: 401);
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byType(SvgPicture));
    await tester.pump();
    await tester.pump();
    expect(pass.retries, 1);
  });

  testWidgets('adding on Android opens the save link', (tester) async {
    await pump(tester, platform: TargetPlatform.android);
    await tester.tap(find.byType(SvgPicture));
    await tester.pump();
    await tester.pump();
    expect(launched, [Uri.parse('https://pay.google.com/gp/v/save/x')]);
  });

  test('every badge asset is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final path in [
      ...appleWalletBadge.values,
      ...googleWalletBadge.values,
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/widgets/member_pass/wallet_buttons_test.dart`
Expected: FAIL, because the files do not exist.

- [ ] **Step 3: Write the Dart channel and the providers**

`lib/data/services/wallet_channel.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum WalletAddResult { added, cancelled }

/// Apple Wallet through `biso/wallet` in `AppDelegate.swift`. The pass
/// bytes go straight to PassKit and never touch disk.
class WalletChannel {
  const WalletChannel([this._channel = const MethodChannel('biso/wallet')]);

  final MethodChannel _channel;

  Future<bool> canAddPasses() async {
    try {
      return await _channel.invokeMethod<bool>('canAddPasses') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Presents Apple's add-pass sheet. Throws a [PlatformException] with code
  /// `invalid_pass` when PassKit cannot read [bytes].
  Future<WalletAddResult> addPass(Uint8List bytes) async {
    final result = await _channel.invokeMethod<String>('addPass', {
      'pass': bytes,
    });
    return result == 'added' ? WalletAddResult.added : WalletAddResult.cancelled;
  }
}
```

In `lib/providers/member_pass/member_pass_provider.dart`, import
`../../data/services/wallet_channel.dart` and add:

```dart
final walletChannelProvider = Provider<WalletChannel>(
  (ref) => const WalletChannel(),
);

final canAddApplePassesProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(walletChannelProvider).canAddPasses(),
);
```

- [ ] **Step 4: Write the buttons**

`lib/presentation/widgets/member_pass/wallet_buttons.dart`:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/models/member_pass.dart';
import '../../../data/services/member_pass_api_client.dart';
import '../../../data/services/wallet_channel.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../biso/biso.dart';

/// Apple's badge with its styles inlined for flutter_svg; the originals in
/// assets/wallet/apple are the sources (see tool/inline_svg_styles.py).
const appleWalletBadge = {
  'en': 'assets/wallet/apple/flutter/add_to_wallet_en.svg',
  'no': 'assets/wallet/apple/flutter/add_to_wallet_no.svg',
};

const googleWalletBadge = {
  'en': 'assets/wallet/google/add_to_wallet_en.svg',
  'no': 'assets/wallet/google/add_to_wallet_no.svg',
};

/// The platform's own Add to Wallet badge, when the server offers that
/// wallet: Apple's on iOS, Google's on Android, never both.
class WalletButtons extends ConsumerStatefulWidget {
  const WalletButtons({super.key, required this.wallets});

  final WalletAvailability wallets;

  @override
  ConsumerState<WalletButtons> createState() => _WalletButtonsState();
}

class _WalletButtonsState extends ConsumerState<WalletButtons> {
  bool _busy = false;
  bool _added = false;

  String _badge(Map<String, String> assets) {
    final language = Localizations.localeOf(context).languageCode;
    return assets[language] ?? assets['en']!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS when widget.wallets.apple:
        final canAdd =
            ref.watch(canAddApplePassesProvider).valueOrNull ?? false;
        if (!canAdd) return const SizedBox.shrink();
        if (_added) return _AddedLabel(text: l10n.walletAdded);
        return _Badge(
          asset: _badge(appleWalletBadge),
          label: l10n.walletAddAppleLabel,
          busy: _busy,
          onPressed: _addApple,
        );
      case TargetPlatform.android when widget.wallets.google:
        return _Badge(
          asset: _badge(googleWalletBadge),
          label: l10n.walletAddGoogleLabel,
          busy: _busy,
          onPressed: _addGoogle,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _addApple() => _run(() async {
    final bytes = await ref.read(memberPassApiProvider).fetchApplePass();
    final result = await ref.read(walletChannelProvider).addPass(bytes);
    if (result == WalletAddResult.added && mounted) {
      setState(() => _added = true);
    }
  });

  Future<void> _addGoogle() => _run(() async {
    final url = await ref.read(memberPassApiProvider).fetchGoogleSaveUrl();
    final opened = await ref.read(membershipUrlLauncherProvider)(url);
    if (!opened) _say((l10n) => l10n.walletErrorFailed);
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on MemberPassApiException catch (error) {
      if (error.isUnauthorized) {
        // The pass screen re-checks and shows the sign-in prompt.
        unawaited(ref.read(memberPassProvider.notifier).retry());
      } else if (error.isForbidden) {
        _say((l10n) => l10n.walletErrorNotMember);
      } else if (error.isNotFound) {
        _say((l10n) => l10n.walletErrorNotConfigured);
      } else {
        _say((l10n) => l10n.walletErrorFailed);
      }
    } on PlatformException catch (error) {
      _say(
        (l10n) => error.code == 'invalid_pass'
            ? l10n.walletErrorInvalid
            : l10n.walletErrorFailed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String Function(AppLocalizations l10n) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text(AppLocalizations.of(context)!))),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.asset,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String asset;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        enabled: !busy,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: busy ? null : onPressed,
          child: AnimatedOpacity(
            opacity: busy ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: SvgPicture.asset(asset, height: 48),
          ),
        ),
      ),
    );
  }
}

class _AddedLabel extends StatelessWidget {
  const _AddedLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.checkmark_circle_fill, color: palette.muted),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.muted),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Declare the assets and show the buttons on the pass screen**

In `pubspec.yaml`, under `flutter: assets:`, add:

```yaml
    - assets/wallet/apple/flutter/add_to_wallet_en.svg
    - assets/wallet/apple/flutter/add_to_wallet_no.svg
    - assets/wallet/google/add_to_wallet_en.svg
    - assets/wallet/google/add_to_wallet_no.svg
```

In `member_pass_screen.dart`, import `../../widgets/member_pass/wallet_buttons.dart` and change the
`PassStatus.active` column's children to:

```dart
        children: [
          PassCard(
            view: view,
            onTap: () => unawaited(showPassPresentation(context)),
          ),
          const SizedBox(height: 16),
          WalletButtons(wallets: view.pass!.wallets),
        ],
```

In `test/presentation/design_rules_test.dart`, add this line to `migratedFiles`:
`'lib/presentation/widgets/member_pass/wallet_buttons.dart',`

In `test/presentation/screens/profile/member_pass_screen_test.dart`, add this override to
`overrides(...)`, so the screen tests never touch the platform channel:

```dart
      canAddApplePassesProvider.overrideWith((ref) async => false),
```

- [ ] **Step 6: Write the iOS channel**

In `ios/Runner/AppDelegate.swift`:

1. Add `import PassKit` below `import UIKit`.
2. Add these properties next to `expenseIntakeChannel`:

```swift
  private let walletChannelName = "biso/wallet"
  private var walletChannel: FlutterMethodChannel?
  private var pendingWalletResult: FlutterResult?
  private var pendingWalletPass: PKPass?
```

3. Inside `if let controller = ...`, after the expense channel's `setMethodCallHandler { ... }`
   block, add:

```swift
      let wallet = FlutterMethodChannel(
        name: walletChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      walletChannel = wallet
      wallet.setMethodCallHandler { [weak self] call, result in
        self?.handleWalletCall(call, result: result)
      }
```

4. At the end of the file, add:

```swift
// MARK: - Apple Wallet

extension AppDelegate: PKAddPassesViewControllerDelegate {
  fileprivate func handleWalletCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canAddPasses":
      result(PKAddPassesViewController.canAddPasses())
    case "addPass":
      guard pendingWalletResult == nil else {
        result(FlutterError(code: "busy", message: nil, details: nil))
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let data = args["pass"] as? FlutterStandardTypedData,
        let pass = try? PKPass(data: data.data),
        let sheet = PKAddPassesViewController(pass: pass)
      else {
        result(FlutterError(code: "invalid_pass", message: nil, details: nil))
        return
      }
      guard let presenter = topViewController() else {
        result(FlutterError(code: "no_presenter", message: nil, details: nil))
        return
      }
      sheet.delegate = self
      pendingWalletResult = result
      pendingWalletPass = pass
      presenter.present(sheet, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    controller.dismiss(animated: true)
    // containsPass only sees pass types listed in the app's entitlements.
    // Without that capability this reports "cancelled" and the Add button
    // simply stays visible.
    let added = pendingWalletPass.map { PKPassLibrary().containsPass($0) } ?? false
    pendingWalletResult?(added ? "added" : "cancelled")
    pendingWalletResult = nil
    pendingWalletPass = nil
  }

  private func topViewController() -> UIViewController? {
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
```

- [ ] **Step 7: Run the tests and build iOS**

Run: `flutter test test/presentation/widgets/member_pass test/presentation/screens/profile test/presentation/design_rules_test.dart`
Expected: PASS

Run: `flutter build ios --debug --no-codesign`
Expected: `Built build/ios/iphoneos/Runner.app`. This compiles the Swift and installs the new pods
(`screen_brightness`, `wakelock_plus`, `connectivity_plus`). If CocoaPods reports an outdated
spec repo, run `cd ios && pod install --repo-update && cd ..` and build again.

- [ ] **Step 8: Commit**

```bash
dart format lib/data/services/wallet_channel.dart lib/providers/member_pass/member_pass_provider.dart lib/presentation/widgets/member_pass/wallet_buttons.dart lib/presentation/screens/profile/member_pass_screen.dart test/presentation/widgets/member_pass/wallet_buttons_test.dart test/presentation/screens/profile/member_pass_screen_test.dart test/presentation/design_rules_test.dart
git add pubspec.yaml ios/Runner/AppDelegate.swift ios/Podfile.lock lib/data/services/wallet_channel.dart lib/providers/member_pass/member_pass_provider.dart lib/presentation/widgets/member_pass/wallet_buttons.dart lib/presentation/screens/profile/member_pass_screen.dart test/presentation/widgets/member_pass/wallet_buttons_test.dart test/presentation/screens/profile/member_pass_screen_test.dart test/presentation/design_rules_test.dart
git commit -m "Add the member pass to Apple or Google Wallet

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 15: Scanner screen, gate and route

**Files:**
- Create: `lib/data/services/scanner_camera.dart`
- Create: `lib/presentation/screens/scanner/scanner_route.dart`
- Create: `lib/presentation/screens/scanner/scanner_gate.dart`
- Create: `lib/presentation/screens/scanner/membership_scanner_screen.dart`
- Modify:
  - `lib/main.dart`: add `membershipScannerRoute()` to the top-level routes, before the tab
    `ShellRoute`.
  - `test/helpers/fake_member_pass_api.dart`: add `FakeScannerCamera`.
  - `test/presentation/design_rules_test.dart`.
- Test: `test/presentation/screens/scanner/membership_scanner_test.dart`

**Interfaces:**
- Consumes:
  - From Task 8: `scannerAccessProvider`, `ScannerAccessState` and its cases.
  - From Task 9: `scannerControllerProvider` and `scanHapticsProvider`.
  - From Task 7: `ScannerDisplay` and its cases.
  - From Task 11: `PassColors`, `dayColorName` and `scanMessageText`.
  - `osloWallClock` (Task 1).
- Produces:
  - `abstract interface class ScannerCamera`, with the members:
    - `Widget preview({required void Function(String code) onCode, required WidgetBuilder onError})`
    - `Future<void> pause()`, `Future<void> resume()` and `Future<void> dispose()`
  - `class MobileScannerCamera implements ScannerCamera`
  - `final scannerCameraFactoryProvider = Provider<ScannerCamera Function()>`
  - `const membershipScannerPath = '/explore/scan'` and `GoRoute membershipScannerRoute()`
  - `class ScannerGate extends ConsumerStatefulWidget`
  - `class MembershipScannerScreen extends ConsumerStatefulWidget`, constructed as
    `({required ScannerAccess access})`
  - Test helper `FakeScannerCamera`, with `pauses`, `resumes`, `disposed` and
    `void read(String code)`.

- [ ] **Step 1: Add the fake camera to the shared helper**

Append to `test/helpers/fake_member_pass_api.dart`. Also add the imports
`package:biso/data/services/scanner_camera.dart` and `package:flutter/widgets.dart`.

```dart
/// A camera that shows a placeholder and reads whatever the test says.
class FakeScannerCamera implements ScannerCamera {
  void Function(String code)? _onCode;
  int pauses = 0;
  int resumes = 0;
  bool disposed = false;

  void read(String code) => _onCode!(code);

  @override
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  }) {
    _onCode = onCode;
    return const SizedBox.expand(key: Key('fake-camera'));
  }

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> dispose() async => disposed = true;
}
```

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:async';

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/scanner/membership_scanner_screen.dart';
import 'package:biso/presentation/screens/scanner/scanner_gate.dart';
import 'package:biso/presentation/screens/scanner/scanner_route.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/member_pass/scanner_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart';

void main() {
  late FakeMemberPassApi api;
  late FakeScannerCamera camera;
  late int camerasMade;
  late FixedScannerAccess access;
  late List<ScanTone> haptics;

  final expiring = ScannerGranted(
    ScannerAccess(
      dayColor: testDayColor,
      expiresAt: DateTime.utc(2026, 9, 20, 22),
    ),
  );

  List<Override> overrides(ScannerAccessState? state) {
    api = FakeMemberPassApi()
      ..onScan = (_) => ScanOutcome(
        result: ScanResult.valid,
        name: 'Kari Nordmann',
        membershipName: 'Semester',
        expiryDate: DateTime(2026, 12, 31),
      );
    camera = FakeScannerCamera();
    camerasMade = 0;
    access = FixedScannerAccess(state);
    haptics = [];
    return [
      memberPassApiProvider.overrideWithValue(api),
      scannerAccessProvider.overrideWith(() => access),
      scanHapticsProvider.overrideWithValue(haptics.add),
      scannerCameraFactoryProvider.overrideWithValue(() {
        camerasMade++;
        return camera;
      }),
    ];
  }

  Future<void> pumpGate(WidgetTester tester, ScannerAccessState? state) =>
      pumpBisoScreen(
        tester,
        const ScannerGate(),
        overrides: overrides(state),
        inShell: false,
        routed: true,
      );

  group('gate', () {
    testWidgets('shows a spinner and no camera while checking', (
      tester,
    ) async {
      await pumpGate(tester, null);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(camerasMade, 0);
    });

    final messages = {
      'denied': (
        const ScannerDenied(),
        "You don't have scanning access. Ask BISO staff for an invitation.",
      ),
      'signed out': (
        const ScannerSignedOut(),
        "You've been signed out — sign in again",
      ),
      'not configured': (
        const ScannerNotConfigured(),
        "Scanning isn't available right now.",
      ),
      'failed': (const ScannerCheckFailed(), "Couldn't check your access"),
    };
    messages.forEach((name, entry) {
      final (state, text) = entry;
      testWidgets('$name shows its message and no camera', (tester) async {
        await pumpGate(tester, state);
        expect(find.text(text), findsOneWidget);
        expect(camerasMade, 0);
        expect(find.byType(BisoPage), findsOneWidget);
      });
    });

    testWidgets('a failed check can be retried', (tester) async {
      await pumpGate(tester, const ScannerCheckFailed());
      final before = access.freshCalls;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(access.freshCalls, before + 1);
    });

    testWidgets('granted opens the camera and refreshes access', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      expect(find.byType(MembershipScannerScreen), findsOneWidget);
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
      expect(camerasMade, 1);
      expect(access.freshCalls, 1);
    });
  });

  group('scanner', () {
    testWidgets('the top bar shows the day color and the access end', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      expect(find.text('Teal'), findsOneWidget);
      expect(find.textContaining('Access until'), findsOneWidget);
      expect(find.text('Point the camera at a member pass'), findsOneWidget);
    });

    testWidgets('a valid read fills the screen, pauses, then resumes', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();

      expect(find.text('Valid member'), findsOneWidget);
      expect(find.text('Kari Nordmann'), findsOneWidget);
      expect(find.textContaining('Valid until'), findsOneWidget);
      expect(camera.pauses, 1);
      expect(haptics, [ScanTone.green]);

      await tester.pump(ScannerController.resultDuration);
      await tester.pump();
      expect(find.text('Valid member'), findsNothing);
      expect(camera.resumes, 1);
    });

    testWidgets('a tap dismisses the result', (tester) async {
      await pumpGate(tester, expiring);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Tap to continue'));
      await tester.pump();
      expect(find.text('Valid member'), findsNothing);
      expect(camera.resumes, 1);
    });

    final outcomes = <String, (ScanOutcome, String)>{
      'duplicate': (
        const ScanOutcome(
          result: ScanResult.duplicate,
          name: 'Kari',
          secondsSincePrevious: 42,
        ),
        'Already scanned 42s ago',
      ),
      'check id': (
        const ScanOutcome(result: ScanResult.checkId, name: 'Kari'),
        'Wallet pass — check ID',
      ),
      'stale': (
        const ScanOutcome(result: ScanResult.denied, reason: DenyReason.stale),
        'Old code — ask them to reopen the pass',
      ),
      'not linked': (
        const ScanOutcome(
          result: ScanResult.denied,
          reason: DenyReason.notLinked,
        ),
        'No linked student account',
      ),
      'unavailable': (
        const ScanOutcome(result: ScanResult.unavailable),
        "Couldn't check — try again",
      ),
    };
    outcomes.forEach((name, entry) {
      final (outcome, text) = entry;
      testWidgets('$name shows "$text"', (tester) async {
        await pumpGate(tester, expiring);
        api.onScan = (_) => outcome;
        camera.read('v1.kari.1.sig');
        await tester.pump();
        await tester.pump();
        expect(find.text(text), findsOneWidget);
        await tester.pump(ScannerController.resultDuration);
      });
    });

    testWidgets('a rate limit says to wait', (tester) async {
      await pumpGate(tester, expiring);
      api.onScan = (_) =>
          throw const MemberPassApiException('rate_limited', statusCode: 429);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();
      expect(find.text('Too many scans — wait a moment'), findsOneWidget);
      await tester.pump(ScannerController.resultDuration);
    });

    testWidgets('an overlong read is denied without a request', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      camera.read('x' * 300);
      await tester.pump();
      expect(find.text('Not a BISO pass'), findsOneWidget);
      expect(api.scanned, isEmpty);
      await tester.pump(ScannerController.resultDuration);
    });

    testWidgets('a 403 mid-shift closes the scanner with a message', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/explore',
        routes: [
          membershipScannerRoute(),
          GoRoute(
            path: '/explore',
            builder: (_, _) => const Scaffold(body: Text('Explore')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(expiring),
          child: MaterialApp.router(
            theme: PremiumTheme.build(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push(membershipScannerPath));
      await tester.pumpAndSettle();
      expect(find.byType(MembershipScannerScreen), findsOneWidget);

      api.onScan = (_) =>
          throw const MemberPassApiException('not_scanner', statusCode: 403);
      camera.read('v1.kari.1.sig');
      await tester.pumpAndSettle();

      expect(find.byType(MembershipScannerScreen), findsNothing);
      expect(find.text('Explore'), findsOneWidget);
      expect(
        find.text(
          "You don't have scanning access. Ask BISO staff for an invitation.",
        ),
        findsOneWidget,
      );
      expect(camera.disposed, isTrue);
    });
  });

  testWidgets('the route is matched ahead of the tab shell', (tester) async {
    final router = GoRouter(
      initialLocation: membershipScannerPath,
      routes: [
        membershipScannerRoute(),
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            GoRoute(
              path: '/explore',
              builder: (_, _) => const Text('Explore'),
              routes: [
                GoRoute(path: '/events', builder: (_, _) => const Text('Events')),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(const ScannerDenied()),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScannerGate), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/scanner/membership_scanner_test.dart`
Expected: FAIL, because the files do not exist.

- [ ] **Step 4: Write the camera wrapper**

`lib/data/services/scanner_camera.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The camera behind the scanner, so the screen can be tested without one.
abstract interface class ScannerCamera {
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  });

  Future<void> pause();
  Future<void> resume();
  Future<void> dispose();
}

/// QR codes only. `mobile_scanner` itself pauses in the background.
class MobileScannerCamera implements ScannerCamera {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  }) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.isNotEmpty) {
            onCode(value);
            return;
          }
        }
      },
      errorBuilder: (context, _) => onError(context),
    );
  }

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> resume() => _controller.start();

  @override
  Future<void> dispose() => _controller.dispose();
}

final scannerCameraFactoryProvider = Provider<ScannerCamera Function()>(
  (ref) => MobileScannerCamera.new,
);
```

- [ ] **Step 5: Write the route and the gate**

`lib/presentation/screens/scanner/scanner_route.dart`:

```dart
import 'package:go_router/go_router.dart';

import 'scanner_gate.dart';

const membershipScannerPath = '/explore/scan';

/// Full screen, outside the tab shell. The gate checks access on every
/// arrival, including cold starts and deep links.
GoRoute membershipScannerRoute() => GoRoute(
  path: membershipScannerPath,
  name: 'membership-scanner',
  builder: (context, state) => const ScannerGate(),
);
```

`lib/presentation/screens/scanner/scanner_gate.dart`:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scanner_access_provider.dart';
import '../../widgets/biso/biso.dart';
import 'membership_scanner_screen.dart';

/// Shows the scanner only to users the server calls scanners. The camera
/// is not created until then.
class ScannerGate extends ConsumerStatefulWidget {
  const ScannerGate({super.key});

  @override
  ConsumerState<ScannerGate> createState() => _ScannerGateState();
}

class _ScannerGateState extends ConsumerState<ScannerGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(scannerAccessProvider.notifier).ensureFresh(force: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(scannerAccessProvider);
    final value = async.valueOrNull;
    if (value is ScannerGranted) {
      return MembershipScannerScreen(access: value.access);
    }

    final Widget body;
    if (value == null || async.isLoading) {
      body = const CupertinoActivityIndicator();
    } else {
      body = switch (value) {
        ScannerDenied() => BisoEmptyState(
          icon: CupertinoIcons.lock,
          title: l10n.scannerNoAccess,
        ),
        ScannerSignedOut() => BisoEmptyState(
          icon: CupertinoIcons.person_crop_circle,
          title: l10n.scannerSignedOut,
          action: FilledButton(
            onPressed: () => context.go('/auth/login'),
            child: Text(l10n.memberPassSignIn),
          ),
        ),
        ScannerNotConfigured() => BisoEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: l10n.scannerNotConfigured,
        ),
        ScannerCheckFailed() => BisoEmptyState(
          icon: CupertinoIcons.wifi_slash,
          title: l10n.scannerCheckFailed,
          action: FilledButton(
            onPressed: () => unawaited(
              ref
                  .read(scannerAccessProvider.notifier)
                  .ensureFresh(force: true),
            ),
            child: Text(l10n.tryAgainMessage),
          ),
        ),
        ScannerGranted() => const SizedBox.shrink(),
      };
    }

    return BisoPage(
      title: l10n.scannerTitle,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      body: Center(child: body),
    );
  }
}
```

- [ ] **Step 6: Write the scanner screen**

`lib/presentation/screens/scanner/membership_scanner_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../data/models/member_pass.dart';
import '../../../data/services/scanner_camera.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scan_display.dart';
import '../../../providers/member_pass/scanner_controller.dart';
import '../../widgets/member_pass/pass_colors.dart';

/// Full-screen camera. Each result covers the whole screen, so door staff
/// read it at a glance.
class MembershipScannerScreen extends ConsumerStatefulWidget {
  const MembershipScannerScreen({super.key, required this.access});

  final ScannerAccess access;

  @override
  ConsumerState<MembershipScannerScreen> createState() =>
      _MembershipScannerScreenState();
}

class _MembershipScannerScreenState
    extends ConsumerState<MembershipScannerScreen> {
  late final ScannerCamera _camera = ref.read(scannerCameraFactoryProvider)();

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _close(ScannerCloseReason reason) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    NavigationUtils.safeGoBack(context, fallbackRoute: '/explore');
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          reason == ScannerCloseReason.noAccess
              ? l10n.scannerNoAccess
              : l10n.scannerSignedOut,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(scannerControllerProvider.notifier);
    ref.listen(scannerControllerProvider, (previous, next) {
      if (next is ScannerResult && previous is! ScannerResult) {
        unawaited(_camera.pause());
      } else if (next is ScannerIdle && previous is ScannerResult) {
        unawaited(_camera.resume());
      } else if (next is ScannerClosed) {
        _close(next.reason);
      }
    });
    final display = ref.watch(scannerControllerProvider);

    return Scaffold(
      backgroundColor: PassColors.scannerBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _camera.preview(
            onCode: (code) => unawaited(controller.onDetected(code)),
            onError: (context) => _CameraError(text: l10n.scannerCameraError),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              access: widget.access,
              onClose: () =>
                  NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
            ),
          ),
          if (display is ScannerIdle)
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: SafeArea(
                child: Text(
                  l10n.scannerPointCamera,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PassColors.cardInk,
                  ),
                ),
              ),
            ),
          if (display is ScannerChecking)
            const Center(
              child: CupertinoActivityIndicator(
                radius: 18,
                color: PassColors.cardInk,
              ),
            ),
          if (display is ScannerResult)
            Positioned.fill(
              child: ScanResultOverlay(
                result: display,
                onTap: controller.dismiss,
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.access, required this.onClose});

  final ScannerAccess access;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final expiresAt = access.expiresAt;
    final dayColor = access.dayColor.color;
    return ColoredBox(
      color: PassColors.scannerBackground.withValues(alpha: 0.6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  color: PassColors.cardInk,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.scannerTitle,
                      style: text.titleMedium?.copyWith(
                        color: PassColors.cardInk,
                      ),
                    ),
                    if (expiresAt != null)
                      Text(
                        l10n.scannerAccessUntil(
                          DateFormat.MMMd(
                            locale,
                          ).add_Hm().format(osloWallClock(expiresAt)),
                        ),
                        style: text.bodySmall?.copyWith(
                          color: PassColors.cardMuted,
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: dayColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    dayColorName(l10n, access.dayColor.name),
                    style: text.labelLarge?.copyWith(
                      color: PassColors.inkOn(dayColor),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scan result over the whole screen, in its tone.
class ScanResultOverlay extends StatelessWidget {
  const ScanResultOverlay({
    super.key,
    required this.result,
    required this.onTap,
  });

  final ScannerResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final background = PassColors.scanTone(result.tone);
    final ink = PassColors.inkOn(background);
    final expiry = result.expiryDate;
    final icon = switch (result.tone) {
      ScanTone.green => CupertinoIcons.checkmark_circle_fill,
      ScanTone.orange => CupertinoIcons.arrow_counterclockwise_circle_fill,
      ScanTone.amber => CupertinoIcons.person_crop_rectangle_fill,
      ScanTone.red => CupertinoIcons.xmark_circle_fill,
      ScanTone.grey => CupertinoIcons.exclamationmark_circle_fill,
    };

    return Semantics(
      liveRegion: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: background,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 112, color: ink),
                  const SizedBox(height: 20),
                  Text(
                    scanMessageText(l10n, result),
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (result.name != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      result.name!,
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(color: ink),
                    ),
                  ],
                  if (result.membershipName != null)
                    Text(
                      result.membershipName!,
                      style: text.titleMedium?.copyWith(color: ink),
                    ),
                  if (expiry != null)
                    Text(
                      l10n.memberPassValidUntil(
                        DateFormat.yMMMd(locale).format(expiry),
                      ),
                      style: text.titleMedium?.copyWith(color: ink),
                    ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.scannerTapToContinue,
                    style: text.bodyMedium?.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: PassColors.cardInk),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Register the route**

In `lib/main.dart`, import `presentation/screens/scanner/scanner_route.dart`. In the
`_router`'s top-level `routes:` list, directly before the `// Main app shell with tab navigation`
`ShellRoute(`, add:

```dart
    membershipScannerRoute(),
```

In `test/presentation/design_rules_test.dart`, add these lines to `migratedFiles`:

```dart
  'lib/presentation/screens/scanner/scanner_gate.dart',
  'lib/presentation/screens/scanner/membership_scanner_screen.dart',
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/presentation/screens/scanner test/presentation/design_rules_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
dart format lib/main.dart lib/data/services/scanner_camera.dart lib/presentation/screens/scanner test/helpers/fake_member_pass_api.dart test/presentation/screens/scanner test/presentation/design_rules_test.dart
git add lib/main.dart lib/data/services/scanner_camera.dart lib/presentation/screens/scanner test/helpers/fake_member_pass_api.dart test/presentation/screens/scanner test/presentation/design_rules_test.dart
git commit -m "Add the membership scanner for people with scanning access

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---
### Task 16: "Scan memberships" in Explore

**Files:**
- Modify: `lib/presentation/screens/explore/explore_screen.dart`
- Modify: `test/presentation/screens/explore/explore_design_test.dart` and
  `test/presentation/screens/explore/expenses_entry_points_test.dart` (override access in both, so
  they never hit the network)
- Test: `test/presentation/screens/explore/explore_scanner_tile_test.dart`

**Interfaces:**
- Consumes: from Task 8, `scannerAccessProvider`, `ScannerGranted` and
  `ScannerAccessNotifier.ensureFresh()`; from Task 15, `membershipScannerPath`; from Task 10,
  `scannerTitle` and `scannerSubtitle`.
- Produces: the first Explore category, shown only for `ScannerGranted`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/screens/scanner/scanner_route.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_member_pass_api.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

class _Locale extends LocaleNotifier {}

void main() {
  late FixedScannerAccess access;

  Future<void> pump(WidgetTester tester, ScannerAccessState? state) async {
    access = FixedScannerAccess(state);
    final router = GoRouter(
      initialLocation: '/explore',
      routes: [
        GoRoute(
          path: '/explore',
          builder: (_, _) => const ExploreScreen(),
        ),
        GoRoute(
          path: membershipScannerPath,
          builder: (_, _) => const Scaffold(body: Text('Scanner')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filterCampusProvider.overrideWithValue(_campus),
          campusInitializedProvider.overrideWithValue(true),
          currentCampusDataProvider.overrideWithValue(
            const AsyncValue.data(null),
          ),
          appConfigProvider.overrideWith((ref) async => const AppConfig()),
          featuredLargeEventProvider.overrideWithValue(null),
          localeProvider.overrideWith((ref) => _Locale()),
          scannerAccessProvider.overrideWith(() => access),
        ],
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('scanners see the tile first', (tester) async {
    await pump(tester, grantedAccess);
    final titles = tester
        .widgetList<BisoListRow>(find.byType(BisoListRow))
        .map((row) => row.title)
        .toList();
    expect(titles.first, 'Scan memberships');
    expect(find.text('Check member passes at the door'), findsOneWidget);
  });

  testWidgets('the tile opens the scanner', (tester) async {
    await pump(tester, grantedAccess);
    await tester.tap(find.text('Scan memberships'));
    await tester.pumpAndSettle();
    expect(find.text('Scanner'), findsOneWidget);
  });

  testWidgets('everyone else never sees it', (tester) async {
    await pump(tester, const ScannerDenied());
    expect(find.text('Scan memberships'), findsNothing);
  });

  testWidgets('it stays hidden while access is being checked', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.text('Scan memberships'), findsNothing);
  });

  testWidgets('opening Explore asks whether access is still fresh', (
    tester,
  ) async {
    await pump(tester, const ScannerDenied());
    expect(access.freshCalls, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/explore/explore_scanner_tile_test.dart`
Expected: FAIL. The tile does not exist, and `freshCalls` is 0.

- [ ] **Step 3: Add the tile**

In `lib/presentation/screens/explore/explore_screen.dart`:

1. Add `import 'dart:async';` at the top, plus these two imports:

```dart
import '../../../providers/member_pass/scanner_access_provider.dart';
import '../scanner/scanner_route.dart';
```

2. In `_ExploreScreenState`, add:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(scannerAccessProvider.notifier).ensureFresh());
    });
  }
```

3. In `build`, after `final event = ref.watch(featuredLargeEventProvider);`, add:

```dart
    final canScan =
        ref.watch(scannerAccessProvider).valueOrNull is ScannerGranted;
```

4. Make this the first entry of `categories`:

```dart
      if (canScan)
        _CategoryData(
          icon: CupertinoIcons.qrcode_viewfinder,
          accent: BisoAccent.gold,
          title: l10n.scannerTitle,
          subtitle: l10n.scannerSubtitle,
          onTap: () => context.push(membershipScannerPath),
        ),
```

- [ ] **Step 4: Keep the existing Explore tests offline**

In `test/presentation/screens/explore/explore_design_test.dart` and
`test/presentation/screens/explore/expenses_entry_points_test.dart`:
- Import `package:biso/providers/member_pass/scanner_access_provider.dart` and
  `../../../helpers/fake_member_pass_api.dart`.
- Add this to the override list that builds `ExploreScreen` (`_overrides()` and `_explore(...)`
  respectively):

```dart
  scannerAccessProvider.overrideWith(
    () => FixedScannerAccess(const ScannerDenied()),
  ),
```

- [ ] **Step 5: Run the Explore tests**

Run: `flutter test test/presentation/screens/explore`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
dart format lib/presentation/screens/explore/explore_screen.dart test/presentation/screens/explore
git add lib/presentation/screens/explore/explore_screen.dart test/presentation/screens/explore
git commit -m "Show Scan memberships in Explore to people with scanning access

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 17: Retire controller mode and the validators check

**Files:**
- Delete:
  - `lib/data/services/validator_service.dart`
  - `lib/presentation/screens/validator/controller_mode_screen.dart`
  - `test/presentation/screens/validator/controller_mode_design_test.dart`
- Modify:
  - `lib/main.dart`: remove the import on line 50 and the `/controller-mode` `GoRoute`.
  - `lib/presentation/screens/profile/settings_screen.dart`: remove the `validator_service`
    import, `controllerPermissionsProvider`, and the "Validator Mode" section.
  - `test/presentation/screens/profile/settings_design_test.dart`
  - `test/presentation/design_rules_test.dart`: remove the `controller_mode_screen.dart` entry.
  - `lib/generated/l10n/app_en.arb` and `app_no.arb`: remove `showThisToValidatorsMessage`, then
    regenerate.

**Interfaces:**
- Removes: `ValidatorService`, `ControllerModeScreen`, `controllerPermissionsProvider`, the route
  `/controller-mode` and `AppLocalizations.showThisToValidatorsMessage`.

- [ ] **Step 1: Replace the Settings test that relied on Validator Mode**

In `test/presentation/screens/profile/settings_design_test.dart`:
- Delete the `controllerPermissionsProvider.overrideWith(...)` entry and the
  `{bool controllerPermissions = false}` parameter from `_overrides`. Update the callers that pass
  `controllerPermissions:`.
- Replace the whole test `'Validator Mode row pushes /controller-mode when the user is permitted'`
  with:

```dart
  testWidgets('Settings no longer offers Validator Mode', (tester) async {
    await pumpBisoScreen(
      tester,
      const SettingsSectionPage(section: SettingsSection.general),
      overrides: _overrides(),
    );
    expect(find.text('Validator Mode'), findsNothing);
    expect(find.text('Open Validator Mode'), findsNothing);
  });
```


- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/profile/settings_design_test.dart`
Expected: FAIL. It won't compile, because `_overrides` no longer accepts `controllerPermissions`
and the settings screen still references the provider. Or, if it compiles, the new test fails once
the provider override is gone and the real `ValidatorService` is used.

- [ ] **Step 3: Remove the old code**

```bash
git rm lib/data/services/validator_service.dart lib/presentation/screens/validator/controller_mode_screen.dart test/presentation/screens/validator/controller_mode_design_test.dart
```

Then:
- In `lib/main.dart`, delete
  `import 'presentation/screens/validator/controller_mode_screen.dart';` and the whole
  `GoRoute(path: '/controller-mode', ...)` block.
- In `lib/presentation/screens/profile/settings_screen.dart`, delete the
  `import '../../../data/services/validator_service.dart';` line, the
  `// Controller permissions provider` comment, `final controllerPermissionsProvider = ...;`, and
  the whole `// Controller Mode Section ...` expression, from `ref` through
  `error: (_, _) => const SizedBox.shrink(),\n            ),`.
- In `test/presentation/design_rules_test.dart`, delete
  `'lib/presentation/screens/validator/controller_mode_screen.dart',`.
- Delete `"showThisToValidatorsMessage"` and its `"@showThisToValidatorsMessage"` block from
  `app_en.arb` and `app_no.arb`, then run `flutter gen-l10n`.

- [ ] **Step 4: Check that nothing refers to the old path**

Run:

```bash
grep -rnE "issue_pass_token|verify_pass_token|verify_biso_membership|biso://verify|controller-mode|ControllerMode|ValidatorService|controllerPermissions|'validators'|showThisToValidators" lib test ios android
```

Expected: no output.

Run:

```bash
grep -rnE "student_id" lib | grep -viE "^\S+:\s*(//|///)" | grep -iE "createRow|updateRow|createDocument|updateDocument|upsert"
```

Expected: no output. The client never writes `student_id`.

- [ ] **Step 5: Run the affected tests and the analyzer**

Run: `flutter test test/presentation/screens/profile test/presentation/design_rules_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: at most the 3 remaining pre-existing infos (`app_logger.dart`, and two in
`settings_screen.dart` whose line numbers have shifted). No errors, no warnings.

- [ ] **Step 6: Commit**

```bash
dart format lib/main.dart lib/presentation/screens/profile/settings_screen.dart test/presentation/screens/profile/settings_design_test.dart test/presentation/design_rules_test.dart
git add -A lib/main.dart lib/data/services lib/presentation/screens/validator lib/presentation/screens/profile/settings_screen.dart lib/generated/l10n test/presentation/screens/validator test/presentation/screens/profile/settings_design_test.dart test/presentation/design_rules_test.dart
git commit -m "Retire controller mode and the validators team check

The member pass scanner replaces it. Scanning rights now come from
server-side grants checked through /api/member-pass/scanner.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

---

### Task 18: Documentation and full verification

**Files:**
- Modify: `CLAUDE.md` (add a section after "🎫 Membership (verification, BI link, purchase)")

- [ ] **Step 1: Document the feature**

Insert this into `CLAUDE.md`, directly before `#### 💼 Jobs/Volunteer Board`:

```markdown
#### 🪪 Member pass and membership scanning
- **The server signs and decides everything.** `GET /api/member-pass` returns either the pass
  state (`no_bi_identity`, `not_member`, `expired`, `unavailable`) or an active pass with 20
  signed `v1` codes (one per 30 s slot), `serverNow`, the day color and wallet flags. The app
  shows the code for `(now + drift) ~/ 30000`. It refetches below 4 codes, retries every 15 s while
  offline or low, and refetches on resume and on connectivity changes. A 5xx never removes a pass
  that still has a usable code; only a 200 or a 401 replaces what is shown. Codes, JWTs and
  scanned strings stay in memory and are never logged.
- **Rules live in pure classes:** `MemberPassSession` (pass) and `ScanGate` (20 s repeat
  filter, keyed by member id) mirror the web `pass-refresh.ts` / `scan-repeat.ts`.
- **Presentation mode** keeps the screen awake at full app brightness, and undoes both when the
  app leaves the foreground or the route closes.
- **Wallet:** iOS downloads the `.pkpass` and hands it to `PKAddPassesViewController` through the
  `biso/wallet` channel in `AppDelegate.swift`. Android opens the `saveUrl` from
  `GET /api/member-pass/google`. The badges are the official assets in `assets/wallet/`; Apple's
  are converted for flutter_svg by `tool/inline_svg_styles.py`.
- **Scanning access is a server grant**, given by admins to an email address.
  `GET /api/member-pass/scanner` (200 or 403) decides both the Explore tile and the
  `/explore/scan` route guard. `POST /api/member-pass/scan` re-checks the grant on every scan.
  The old controller mode, the `validators` team check and the
  `issue_pass_token`/`verify_pass_token` functions are gone from the app.
- **Before the API deploys**, a 404 from `/api/member-pass` reads as "unavailable" and a 404 from
  `/scanner` reads as "no access". Nothing else treats 404 that way.
- **Location**: `lib/providers/member_pass/`, `lib/data/services/member_pass_api_client.dart`,
  `lib/presentation/screens/profile/member_pass_screen.dart`,
  `lib/presentation/screens/scanner/`. **Routes**: `/profile/member-pass`, `/explore/scan`.
- **Spec**: `docs/superpowers/specs/2026-09-17-member-pass-and-scanner-design.md`.
```

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests pass. That is the 828 baseline, minus the deleted controller-mode and Validator
Mode tests, plus the new ones. Record the final count.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: no errors and no warnings. Only the pre-existing infos in `app_logger.dart` and
`settings_screen.dart` remain.

- [ ] **Step 4: Check formatting on every file this plan touched**

Run:

```bash
dart format --output=none --set-exit-if-changed $(git diff --name-only main... -- '*.dart' | grep -v '^lib/generated/' | xargs ls 2>/dev/null)
```

Expected: exit code 0.

Some files are only partly touched by this plan: `lib/main.dart`, `settings_screen.dart`,
`explore_screen.dart`, `profile_screen.dart` and `membership_screen.dart`. If one of them fails,
check whether it was already unformatted on `main`:

```bash
git show main:<path> | dart format --output=none --set-exit-if-changed
```

If it was, revert the formatter's changes to lines you did not touch (`git add -p` helps) and keep
only your own hunks formatted.

- [ ] **Step 5: Build both platforms**

Run: `flutter build apk --debug`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

Run: `flutter build ios --debug --no-codesign`
Expected: `Built build/ios/iphoneos/Runner.app`

- [ ] **Step 6: Check for leaks of codes and tokens**

Run:

```bash
grep -rnE "(logPrint|AppLogger\.\w+|debugPrint|print)\(" lib/providers/member_pass lib/data/services/member_pass_api_client.dart lib/data/services/wallet_channel.dart lib/data/services/scanner_camera.dart lib/presentation/screens/scanner lib/presentation/screens/profile/member_pass_screen.dart lib/presentation/screens/profile/member_pass_presentation.dart lib/presentation/widgets/member_pass
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the member pass and membership scanning

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VbWhhpQor2AcweeYUzuN7f"
```

- [ ] **Step 8: Write down what is left for Markus**

Report these in the hand-off, and in the PR description if a PR is opened:
- **Switching on:** deploy BISO-Sites `feat/member-pass-api`. The app needs no change unless the
  generated contract doc differs from brief v2; compare it with `member_pass_api_client.dart`.
- **Manual QA once the API is live:**
  - Pass states for a member, a non-member and an unlinked account.
  - Airplane mode keeps the pass until its codes run out, then shows "Reconnect".
  - Presentation mode brightness is restored after locking the phone.
  - Apple Wallet add on a device, and the Google save link on Android.
  - Scanner results against the web scanner, including a duplicate within 10 minutes, a Wallet
    pass and a revoked grant mid-shift.
- **iOS entitlement:** add the Wallet capability with the server's pass type identifier to
  `Runner.entitlements`, so `containsPass` can confirm an add. Without it, the Add button stays
  visible after adding.
- **Server clean-up (outside both repos):** remove the Appwrite functions `issue_pass_token`,
  `verify_pass_token` and `verify_biso_membership` (if nothing else uses it), and the
  `validators` team.
- **Google "View in Wallet":** the badge assets are in the repo but unused until
  `/api/member-pass` reports a saved state and a view link.
