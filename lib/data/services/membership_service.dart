import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import '../../core/constants/app_constants.dart';
import '../models/membership_model.dart';
import 'appwrite_service.dart';

class MembershipService {
  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal();

  /// Verifies if a student ID has an active BISO membership
  /// Returns the actual membership object if found
  Future<MembershipVerificationResult> verifyMembership(
    String studentId,
  ) async {
    try {
      // The function expects just the student ID as body (string/number)
      final execution = await functions.createExecution(
        functionId: 'verify_biso_membership',
        body: studentId,
      );

      if (execution.responseStatusCode == 200) {
        final responseBody = execution.responseBody;

        // Parse the JSON response
        try {
          final Map<String, dynamic> response = json.decode(responseBody);

          // Check if membership was found
          if (response.containsKey('membership')) {
            final membershipData =
                response['membership'] as Map<String, dynamic>;
            final membership = MembershipModel.fromMap(membershipData);

            return MembershipVerificationResult(
              isMember: true,
              membership: membership,
            );
          } else if (response.containsKey('error')) {
            return MembershipVerificationResult(
              isMember: false,
              error: response['error'] as String,
            );
          } else {
            return const MembershipVerificationResult(
              isMember: false,
              error: 'No active membership found',
            );
          }
        } catch (parseError) {
          return MembershipVerificationResult(
            isMember: false,
            error: 'Failed to parse membership response: $parseError',
          );
        }
      } else {
        return MembershipVerificationResult(
          isMember: false,
          error:
              'Failed to verify membership: HTTP ${execution.responseStatusCode}',
        );
      }
    } catch (e) {
      return MembershipVerificationResult(
        isMember: false,
        error: 'Error verifying membership: ${e.toString()}',
      );
    }
  }

  /// Gets available membership options from database
  Future<List<MembershipPurchaseOption>> getAvailableMemberships() async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'memberships',
        queries: [
          Query.equal('status', true),
          Query.orderAsc('price'),
          Query.equal('canPurchase', true),
        ],
      );

      return documents.rows.map((docData) {
        final membership = MembershipModel.fromMap(docData.data);
        return MembershipPurchaseOption.fromMembership(membership);
      }).toList();
    } catch (e) {
      throw Exception('Error fetching memberships: ${e.toString()}');
    }
  }

  /// Initiates membership purchase checkout using vipps_checkout function
  Future<String?> initiateMembershipCheckout({
    required String membershipId,
    required String membershipName,
    required int amount,
    required String description,
    required String returnUrl,
    String? phoneNumber,
    String paymentMethod = 'VIPPS', // VIPPS or CARD
  }) async {
    try {
      final requestBody = {
        'amount': amount,
        'description': description,
        'returnUrl': returnUrl,
        'membershipId': membershipId,
        'phoneNumber': phoneNumber,
        'paymentMethod': paymentMethod,
        'membershipName': membershipName,
      };

      final execution = await functions.createExecution(
        functionId: 'vipps_checkout',
        body: json.encode(requestBody),
      );

      if (execution.responseStatusCode == 200) {
        final responseBody = execution.responseBody;

        try {
          final Map<String, dynamic> response = json.decode(responseBody);

          if (response.containsKey('checkout')) {
            final checkout = response['checkout'];

            // The checkout object should contain the redirect URL
            if (checkout is Map<String, dynamic> &&
                checkout.containsKey('redirectUrl')) {
              return checkout['redirectUrl'] as String;
            } else if (checkout is Map<String, dynamic> &&
                checkout.containsKey('url')) {
              return checkout['url'] as String;
            }
          } else if (response.containsKey('error')) {
            throw Exception('Checkout error: ${response['error']}');
          }

          throw Exception('No checkout URL found in response');
        } catch (parseError) {
          throw Exception('Failed to parse checkout response: $parseError');
        }
      } else {
        throw Exception(
          'Failed to initiate checkout: HTTP ${execution.responseStatusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error initiating membership checkout: ${e.toString()}');
    }
  }

  /// Gets user's membership from the database
  Future<MembershipModel?> getUserMembership(String userId) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'biso_membership',
        queries: [
          Query.equal('user_id', userId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );

      if (documents.rows.isNotEmpty) {
        return MembershipModel.fromMap(documents.rows.first.data);
      }

      return null;
    } catch (e) {
      throw Exception('Error fetching user membership: ${e.toString()}');
    }
  }

  /// Subscribes to student ID document creation for realtime updates
  RealtimeSubscription subscribeToStudentIdUpdates(
    String userId,
    Function(RealtimeMessage) callback,
  ) {
    final sub = realtime.subscribe([
      Channel.tablesdb(AppConstants.databaseId).table('student_id').row(),
    ], queries: [
      Query.equal('user_id', userId),
    ]);
    sub.stream.listen(callback);
    return sub;
  }

  /// Subscribes to membership updates for realtime notifications
  RealtimeSubscription subscribeToMembershipUpdates(
    String userId,
    Function(RealtimeMessage) callback,
  ) {
    final sub = realtime.subscribe([
      Channel.tablesdb(AppConstants.databaseId).table('biso_membership').row(),
    ], queries: [
      Query.equal('user_id', userId),
    ]);
    sub.stream.listen(callback);
    return sub;
  }
}
