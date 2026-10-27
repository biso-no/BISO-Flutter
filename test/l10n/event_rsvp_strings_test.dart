import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final no = lookupAppLocalizations(const Locale('no'));

  test('event RSVP strings exist in English', () {
    expect(en.eventRsvpTitle, 'Are you going?');
    expect(en.eventRsvpGoing, 'Going');
    expect(en.eventRsvpMaybe, 'Maybe');
    expect(en.eventRsvpNotGoing, 'Not going');
    expect(en.eventRsvpGoingCount(5), '5 going');
    expect(en.eventRsvpMaybeCount(2), '2 maybe');
    expect(en.eventRsvpSignIn, 'Sign in to respond');
    expect(
      en.eventRsvpTicketHint,
      "Saying you're going doesn't get you a ticket.",
    );
    expect(en.eventRsvpSaveFailed, "Couldn't save your answer. Try again.");
  });

  test('event RSVP strings exist in Norwegian', () {
    expect(no.eventRsvpTitle, 'Blir du med?');
    expect(no.eventRsvpGoing, 'Kommer');
    expect(no.eventRsvpMaybe, 'Kanskje');
    expect(no.eventRsvpNotGoing, 'Kommer ikke');
    expect(no.eventRsvpGoingCount(5), '5 kommer');
    expect(no.eventRsvpMaybeCount(3), '3 kanskje');
    expect(no.eventRsvpSignIn, 'Logg inn for å svare');
    expect(no.eventRsvpTicketHint, 'Du får ikke billett ved å svare her.');
    expect(no.eventRsvpSaveFailed, 'Kunne ikke lagre svaret. Prøv igjen.');
  });
}
