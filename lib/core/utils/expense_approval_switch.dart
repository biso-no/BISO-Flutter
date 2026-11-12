/// Which self-declaration switch the expense form offers for a department.
///
/// A port of `approvalSwitchFor` in BISO-Sites
/// `packages/shared/utils/expense-approvers.ts`. Keep the two in step.
enum ApprovalSwitch { financialManager, controller }

const _osloCampusId = '1';

/// Drift Campus and Ledelsen per campus (Finago department ids). National
/// (`5`) has Drift BISO (`1000`) and Operations Unit (`1002`); the other
/// National departments, such as HR and the Control Committee, have no switch.
const _campusLeadershipDepartments = <String, Set<String>>{
  '1': {'1', '2'},
  '2': {'300', '301'},
  '3': {'600', '601'},
  '4': {'800', '801'},
  '5': {'1000', '1002'},
};

/// The switch to offer, or null when the department has none. A leadership
/// department gets the controller switch on its own campus only (on National
/// the controller is the National controller); any other
/// Oslo department gets the financial-manager switch.
ApprovalSwitch? approvalSwitchFor(String campusId, String? departmentId) {
  if (_campusLeadershipDepartments[campusId]?.contains(departmentId ?? '') ==
      true) {
    return ApprovalSwitch.controller;
  }
  return campusId == _osloCampusId ? ApprovalSwitch.financialManager : null;
}
