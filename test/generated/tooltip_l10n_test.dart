import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('header and avatar tooltips are localized in English and Norwegian', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final no = lookupAppLocalizations(const Locale('no'));

    expect(en.chatInfo, 'Chat Info');
    expect(no.chatInfo, 'Chatinfo');
    expect(en.turnFlashOnMessage, 'Turn flash on');
    expect(no.turnFlashOnMessage, 'Slå på blits');
    expect(en.turnFlashOffMessage, 'Turn flash off');
    expect(no.turnFlashOffMessage, 'Slå av blits');
    expect(en.moreMessage, 'More');
    expect(no.moreMessage, 'Mer');
    expect(en.favoriteMessage, 'Favorite');
    expect(no.favoriteMessage, 'Favoritt');
    expect(en.changePhotoMessage, 'Change photo');
    expect(no.changePhotoMessage, 'Bytt bilde');
  });
}
