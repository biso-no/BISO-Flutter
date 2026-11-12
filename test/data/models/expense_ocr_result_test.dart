import 'package:biso/data/models/expense_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromMap reads the AI type pick, issues, amount and duplicate flag', () {
    final result = ExpenseOcrResult.fromMap({
      'data': {
        'costType': 'food',
        'costTypeConfidence': 0.82,
        'receiptIssues': ['blurry', 'cropped'],
        'ocrAmount': 199,
        'possibleDuplicate': true,
      },
    });
    expect(result.costType, 'food');
    expect(result.costTypeConfidence, 0.82);
    expect(result.receiptIssues, ['blurry', 'cropped']);
    expect(result.ocrAmount, 199.0);
    expect(result.possibleDuplicate, isTrue);
  });

  test('new OCR fields default when absent', () {
    final result = ExpenseOcrResult.fromMap({
      'data': {'vendor': 'Rema'},
    });
    expect(result.costType, isNull);
    expect(result.costTypeConfidence, 0);
    expect(result.receiptIssues, isEmpty);
    expect(result.ocrAmount, isNull);
    expect(result.possibleDuplicate, isFalse);
  });
}
