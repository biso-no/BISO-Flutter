import 'package:flutter/cupertino.dart';
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
