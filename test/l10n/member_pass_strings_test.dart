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
