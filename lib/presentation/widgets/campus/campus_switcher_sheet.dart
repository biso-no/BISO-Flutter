import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/campus_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../biso/biso.dart';

/// The app's campus switcher, a sheet listing every campus with a tick on
/// [selectedCampusId]. Tapping one calls [onSelected] and closes the sheet;
/// what the choice changes is up to the caller.
Future<void> showCampusSwitcher(
  BuildContext context, {
  required String? selectedCampusId,
  required ValueChanged<CampusModel> onSelected,
}) => showBisoSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Consumer(
    builder: (context, ref, child) {
      final allCampusesAsync = ref.watch(switcherCampusesProvider);
      return allCampusesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            AppLocalizations.of(context)!.failedToLoadCampusesMessage,
          ),
        ),
        data: (allCampuses) => _CampusSwitcherModal(
          selectedCampusId: selectedCampusId,
          allCampuses: allCampuses,
          onCampusSelected: (campus) {
            onSelected(campus);
            Navigator.pop(context);
          },
        ),
      );
    },
  ),
);

class _CampusSwitcherModal extends StatelessWidget {
  final String? selectedCampusId;
  final List<CampusModel> allCampuses;
  final ValueChanged<CampusModel> onCampusSelected;

  const _CampusSwitcherModal({
    required this.selectedCampusId,
    required this.allCampuses,
    required this.onCampusSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: palette.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select Campus',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: palette.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(CupertinoIcons.xmark, color: palette.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              BisoListGroup(
                children: [
                  for (final campus in allCampuses)
                    _CampusModalCard(
                      campus: campus,
                      isSelected: campus.id == selectedCampusId,
                      onTap: () => onCampusSelected(campus),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampusModalCard extends StatelessWidget {
  final CampusModel campus;
  final bool isSelected;
  final VoidCallback onTap;

  const _CampusModalCard({
    required this.campus,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return BisoListRow(
      title: campus.name,
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark, color: palette.link)
          : null,
      onTap: onTap,
    );
  }
}
