/// Which `departments` rows a student is allowed to see.
///
/// Dart port of `packages/shared/utils/unit-visibility.ts` in BISO-Sites. The
/// `departments` table mirrors the 24SevenOffice chart of accounts, so besides
/// the real student units it holds operating ledgers (`Drift *`) and national
/// governance bodies. Those rows are `active`, so `active` alone is not a
/// publication signal.
///
/// Names are matched raw (campus prefix NOT stripped), so a campus unit named
/// "OSL Board" stays visible while the bare national "Board" row is hidden.
library;

const _operatingLedgerPrefix = 'drift';

final _whitespace = RegExp(r'\s+');

const _nonPublicUnitNames = <String>{
  // Accounting / ledger entities
  'accounting departement', // 24SO's own spelling
  'accounting department',
  'national - accounting',
  'student groups outside biso (gift fund)',
  'samlinger - cl',
  'investment committee',
  'finance committee',
  // Governance bodies, already presented under National leadership
  'board',
  'operations unit',
  'operations unit / administration',
  'control committee',
  'hr',
  'administration',
  'national administration',
  'organisasjonsstrukturkomiteen',
  'academic/political forum',
  'branding committee',
};

String _normalize(String name) =>
    name.trim().toLowerCase().replaceAll(_whitespace, ' ');

/// Is this unit's raw name one a student should see listed? Says nothing about
/// `active`.
bool isPublicUnitName(String? name) {
  if (name == null) return false;
  final normalized = _normalize(name);
  if (normalized.isEmpty) return false;
  if (normalized == _operatingLedgerPrefix ||
      normalized.startsWith('$_operatingLedgerPrefix ')) {
    return false;
  }
  return !_nonPublicUnitNames.contains(normalized);
}

/// Both halves of the rule. A null `active` counts as active.
bool isPublicUnit({String? name, bool? active}) {
  if (active == false) return false;
  return isPublicUnitName(name);
}
