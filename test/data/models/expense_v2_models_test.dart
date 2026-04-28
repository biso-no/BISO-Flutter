import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseOcrResult', () {
    test('parses receipt OCR response with foreign currency conversion', () {
      final result = ExpenseOcrResult.fromMap({
        'success': true,
        'method': 'vision',
        'data': {
          'documentType': 'receipt',
          'vendor': 'Cafe BI',
          'description': 'Team lunch',
          'amount': 42.5,
          'currency': 'eur',
          'amountInNok': 498.25,
          'exchangeRate': 11.72,
          'date': '2026-04-28',
          'category': 'meal',
        },
      });

      expect(result.documentType, 'receipt');
      expect(result.vendor, 'Cafe BI');
      expect(result.currency, 'EUR');
      expect(result.amount, 42.5);
      expect(result.amountInNok, 498.25);
      expect(result.method, 'vision');
    });

    test('parses bank statement OCR response', () {
      final result = ExpenseOcrResult.fromMap({
        'success': true,
        'data': {
          'documentType': 'bank-statement',
          'amount': 501,
          'currency': 'NOK',
          'vendor': 'Cafe BI',
        },
      });

      expect(result.documentType, 'bank-statement');
      expect(result.amount, 501);
      expect(result.currency, 'NOK');
    });
  });

  group('ExpensePayloadBuilder', () {
    const assignment = ExpenseAssignment(
      campusId: 'campus-1',
      campusName: 'Oslo',
      departmentId: 'dept-1',
      departmentName: 'BISO Oslo',
    );

    test('builds summary payload from ready receipt rows', () {
      final receipt = ExpenseReceiptDraft(
        localId: 'local-1',
        fileName: 'receipt.pdf',
        fileId: 'file-1',
        mimeType: 'application/pdf',
        status: ExpenseReceiptStatus.ready,
        amount: 100,
        category: 'meal',
        currency: 'NOK',
        description: 'Lunch',
        vendor: 'Vendor',
        date: DateTime(2026, 4, 28),
      );

      final payload = ExpensePayloadBuilder.buildSummaryPayload(
        assignment: assignment,
        receipts: [receipt],
      );

      expect(payload['assignment']['campusId'], 'campus-1');
      expect(payload['receipts'], hasLength(1));
      expect(payload['receipts'][0]['amount'], 100);
      expect(payload['receipts'][0]['date'], '2026-04-28');
    });

    test('builds draft and submit payload with expenseId and file IDs', () {
      final receipt = ExpenseReceiptDraft(
        localId: 'local-1',
        fileName: 'receipt.jpg',
        fileId: 'appwrite-file-id',
        mimeType: 'image/jpeg',
        status: ExpenseReceiptStatus.ready,
        amount: 75,
        amountInNok: 80,
        currency: 'EUR',
        description: 'Foreign receipt',
      );

      final payload = ExpensePayloadBuilder.buildBasePayload(
        expenseId: 'draft-1',
        assignment: assignment,
        bankAccount: '8601 11 17947',
        description: 'Accounting summary',
        receipts: [receipt],
        eventName: 'Career day',
      );

      expect(payload['expenseId'], 'draft-1');
      expect(payload['campus'], 'campus-1');
      expect(payload['department'], 'dept-1');
      expect(payload['bank_account'], '86011117947');
      expect(payload['total'], 80);
      expect(payload['eventName'], 'Career day');
      expect(payload['expenseAttachments'], hasLength(1));
      expect(payload['expenseAttachments'][0]['url'], 'appwrite-file-id');
      expect(payload['expenseAttachments'][0]['type'], 'image/jpeg');
    });
  });

  group('ExpenseProfileReadiness', () {
    test('reports complete profile as ready', () {
      const user = UserModel(
        id: 'user-1',
        name: 'Test User',
        email: 'test@bi.no',
        phone: '12345678',
        address: 'Nydalsveien 37',
        zipCode: '0484',
        city: 'Oslo',
        bankAccount: '86011117947',
      );

      expect(ExpenseProfileReadiness.fromUser(user).isReady, isTrue);
    });

    test('reports missing and invalid fields', () {
      const user = UserModel(
        id: 'user-1',
        name: '',
        email: 'test@bi.no',
        bankAccount: '1234',
      );

      final readiness = ExpenseProfileReadiness.fromUser(user);

      expect(readiness.isReady, isFalse);
      expect(readiness.missingFields, contains('name'));
      expect(readiness.missingFields, contains('phone'));
      expect(readiness.missingFields, contains('valid bank account'));
      expect(readiness.missingFields, contains('address'));
    });
  });
}
