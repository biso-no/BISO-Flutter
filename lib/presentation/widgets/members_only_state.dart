import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../generated/l10n/app_localizations.dart';
import 'biso/biso.dart';

/// What a non-member sees where something for members could not be shown:
/// a link they followed may point at content only members can open.
class MembersOnlyState extends StatelessWidget {
  const MembersOnlyState({super.key, this.title});

  /// Replaces the default "Members only" heading.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BisoEmptyState(
      icon: CupertinoIcons.lock,
      accent: BisoAccent.teal,
      title: title ?? l10n.membersOnlyTitle,
      message: l10n.membersOnlyBody,
      action: FilledButton(
        onPressed: () => context.push('/profile/membership'),
        child: Text(l10n.membersOnlyBecomeMember),
      ),
    );
  }
}
