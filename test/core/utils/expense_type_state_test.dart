import 'package:biso/core/utils/expense_type_state.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:biso/data/models/expense_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const types = [
    ExpenseCostTypeOption(slug: 'food', label: 'Food'),
    ExpenseCostTypeOption(slug: 'party', label: 'Party', askOccasion: true),
  ];

  ExpenseReceiptDraft receipt({
    double? amount = 100,
    String documentType = 'receipt',
    String? parentReceiptId,
  }) => ExpenseReceiptDraft(
    localId: 'a',
    fileName: 'a.jpg',
    mimeType: 'image/jpeg',
    amount: amount,
    documentType: documentType,
    parentReceiptId: parentReceiptId,
  );

  group('needsType', () {
    test('a receipt with an amount needs a type', () {
      expect(needsType(receipt()), isTrue);
    });
    test('a bank statement does not', () {
      expect(needsType(receipt(documentType: 'bank-statement')), isFalse);
    });
    test('a child receipt does not', () {
      expect(needsType(receipt(parentReceiptId: 'p')), isFalse);
    });
    test('a zero or missing amount does not', () {
      expect(needsType(receipt(amount: 0)), isFalse);
      expect(needsType(receipt(amount: null)), isFalse);
    });
  });

  group('withAiPick', () {
    ExpenseOcrResult ocr(String? slug, double confidence) =>
        ExpenseOcrResult(costType: slug, costTypeConfidence: confidence);

    test('0.8 picks', () {
      final r = receipt().withAiPick(ocr('food', 0.8), types);
      expect(r.typeState, ExpenseTypeState.aiPicked);
      expect(r.costType, 'food');
      expect(r.aiConfidence, 0.8);
    });

    test('a 0.79 pick needs a choice', () {
      final r = receipt().withAiPick(ocr('food', 0.79), types);
      expect(r.typeState, ExpenseTypeState.needsChoice);
      expect(r.costType, isNull);
    });

    test('an inactive slug needs a choice', () {
      final r = receipt().withAiPick(ocr('gone', 0.95), types);
      expect(r.typeState, ExpenseTypeState.needsChoice);
      expect(r.costType, isNull);
    });

    test('a null slug needs a choice and clears an earlier pick', () {
      final picked = receipt().withAiPick(ocr('food', 0.9), types);
      final r = picked.withAiPick(ocr(null, 0), types);
      expect(r.typeState, ExpenseTypeState.needsChoice);
      expect(r.costType, isNull);
    });

    test('issues, duplicate and OCR amount are copied', () {
      final r = receipt().withAiPick(
        const ExpenseOcrResult(
          receiptIssues: ['blurry'],
          possibleDuplicate: true,
          ocrAmount: 99.5,
        ),
        types,
      );
      expect(r.receiptIssues, ['blurry']);
      expect(r.possibleDuplicate, isTrue);
      expect(r.ocrAmount, 99.5);
    });
  });

  group('chooseType and useOwnText', () {
    test('chooseType picks the slug and clears own text', () {
      final r = receipt().useOwnText('Pizza').chooseType('food');
      expect(r.typeState, ExpenseTypeState.chosen);
      expect(r.costType, 'food');
      expect(r.costTypeText, isNull);
    });

    test('useOwnText trims, clears the slug and is chosen', () {
      final r = receipt().chooseType('food').useOwnText('  Pizza  ');
      expect(r.typeState, ExpenseTypeState.chosen);
      expect(r.costType, isNull);
      expect(r.costTypeText, 'Pizza');
    });

    test('useOwnText refuses blank text and leaves the receipt unchanged', () {
      final before = receipt().chooseType('food');
      final after = before.useOwnText('   ');
      expect(after.costType, 'food');
      expect(after.costTypeText, isNull);
      expect(after.typeState, ExpenseTypeState.chosen);
    });

    test('useOwnText caps the text at 120 characters', () {
      final r = receipt().useOwnText('x' * 200);
      expect(r.costTypeText!.length, 120);
    });
  });

  group('hydrateType', () {
    test('own text from a draft stays chosen', () {
      final r = receipt().hydrateType(slug: '', text: ' Pizza ', types: types);
      expect(r.typeState, ExpenseTypeState.chosen);
      expect(r.costTypeText, 'Pizza');
      expect(r.costType, isNull);
    });

    test('an active slug is chosen', () {
      final r = receipt().hydrateType(slug: 'food', types: types);
      expect(r.typeState, ExpenseTypeState.chosen);
      expect(r.costType, 'food');
    });

    test('an unknown slug needs a choice', () {
      final r = receipt().hydrateType(slug: 'gone', types: types);
      expect(r.typeState, ExpenseTypeState.needsChoice);
      expect(r.costType, isNull);
    });

    test('nothing saved needs a choice', () {
      final r = receipt().hydrateType(types: types);
      expect(r.typeState, ExpenseTypeState.needsChoice);
    });
  });

  group('isTypeMissing', () {
    test('only a receipt that needs a type and has none', () {
      expect(isTypeMissing(receipt()), isTrue);
      expect(isTypeMissing(receipt().chooseType('food')), isFalse);
      expect(isTypeMissing(receipt(amount: 0)), isFalse);
    });
  });

  group('attachmentTypeFields', () {
    test('a slug', () {
      expect(attachmentTypeFields(receipt().chooseType('food')), {
        'cost_type': 'food',
        'cost_type_text': null,
        'cost_type_chosen': true,
      });
    });

    test('own text', () {
      expect(attachmentTypeFields(receipt().useOwnText('Pizza')), {
        'cost_type': '',
        'cost_type_text': 'Pizza',
        'cost_type_chosen': true,
      });
    });

    test('needs a choice sends an empty type, still marked chosen', () {
      expect(attachmentTypeFields(receipt()), {
        'cost_type': '',
        'cost_type_text': null,
        'cost_type_chosen': true,
      });
    });
  });

  group('occasionRequired', () {
    test('true when a receipt has a chosen slug that asks', () {
      expect(occasionRequired([receipt().chooseType('party')], types), isTrue);
    });

    test('true for an AI-picked slug that asks', () {
      final r = receipt().withAiPick(
        const ExpenseOcrResult(costType: 'party', costTypeConfidence: 0.9),
        types,
      );
      expect(occasionRequired([r], types), isTrue);
    });

    test('false when the slug does not ask or own text is used', () {
      expect(occasionRequired([receipt().chooseType('food')], types), isFalse);
      expect(occasionRequired([receipt().useOwnText('Party')], types), isFalse);
    });

    test('ignores receipts that need no type', () {
      expect(
        occasionRequired([receipt(amount: 0).chooseType('party')], types),
        isFalse,
      );
    });
  });
}
