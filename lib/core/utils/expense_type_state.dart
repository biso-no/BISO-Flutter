import '../../data/models/expense_cost_type_option.dart';
import '../../data/models/expense_v2_models.dart';

/// Where a receipt's expense type came from. Mirrors the web's
/// `apps/web/src/components/expense-v3/receipt-types.ts`.
enum ExpenseTypeState { aiPicked, needsChoice, chosen }

/// The AI's pick counts only at or above this confidence.
const aiTypeConfidenceThreshold = 0.8;

/// The longest own-words type the server keeps.
const maxOwnTypeTextLength = 120;

/// A receipt takes a type when it has an amount of its own. The amount is
/// what is sent (a typed amount counts as well as a scanned one), since that
/// is what the server judges. A statement attached to a receipt backs that
/// receipt up and never takes one.
bool needsType(ExpenseReceiptDraft r) =>
    r.effectiveAmount > 0 && !r.isBankStatement && r.parentReceiptId == null;

/// A receipt that needs a type and has neither a slug nor own text.
bool isTypeMissing(ExpenseReceiptDraft r) =>
    needsType(r) &&
    (r.costType == null || r.costType!.isEmpty) &&
    (r.costTypeText?.trim().isEmpty ?? true);

/// The type fields of an attachment in the draft and submit payloads.
/// `cost_type` is a slug, or empty when there is no choice yet or the student
/// wrote their own text.
Map<String, dynamic> attachmentTypeFields(ExpenseReceiptDraft r) {
  final text = r.costTypeText?.trim();
  final hasText = text != null && text.isNotEmpty;
  return {
    'cost_type': hasText ? '' : (r.costType ?? ''),
    'cost_type_text': hasText ? text : null,
    'cost_type_chosen': true,
  };
}

/// True when a receipt that needs a type has a chosen or AI-picked type
/// that asks for the occasion.
bool occasionRequired(
  List<ExpenseReceiptDraft> receipts,
  List<ExpenseCostTypeOption> types,
) {
  return receipts.any(
    (r) =>
        needsType(r) &&
        r.costType != null &&
        types.any((t) => t.slug == r.costType && t.askOccasion),
  );
}
