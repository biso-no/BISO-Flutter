/// Which self-declaration switch the expense form offers for a department.
///
/// A port of `approvalSwitchFor` in BISO-Sites
/// `packages/shared/utils/expense-approvers.ts`. Keep the two in step.
enum ApprovalSwitch { financialManager, controller }

const _osloCampusId = '1';

/// Drift Campus and Ledelsen per campus (Finago department ids).
const _campusLeadershipDepartments = <String, Set<String>>{
  '1': {'1', '2'},
  '2': {'300', '301'},
  '3': {'600', '601'},
  '4': {'800', '801'},
};

/// The switch to offer, or null when the department has none. A leadership
/// department gets the controller switch on its own campus only; any other
/// Oslo department gets the financial-manager switch.
ApprovalSwitch? approvalSwitchFor(String campusId, String? departmentId) {
  if (_campusLeadershipDepartments[campusId]?.contains(departmentId ?? '') ==
      true) {
    return ApprovalSwitch.controller;
  }
  return campusId == _osloCampusId ? ApprovalSwitch.financialManager : null;
}
