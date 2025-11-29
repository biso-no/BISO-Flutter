import 'package:appwrite/appwrite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../models/student_id_model.dart';
import 'membership_service.dart';
import 'appwrite_service.dart';
import '../../core/logging/app_logger.dart';
import 'auth_service.dart';

class StudentService {
  // Other Appwrite modules (auth/functions) are fine; database access uses RobustDocumentService
  static final _appAuth = FlutterAppAuth();
  static final _authService = AuthService();

  /// Initiates OAuth2 flow with Microsoft Azure for BI student account
  /// Returns the student ID extracted from the email
  Future<String> registerStudentIdViaOAuth() async {
    try {
      AppLogger.info('Starting OAuth student ID registration');

      // Microsoft Azure configuration for BI tenant
      const String clientId = '09d8bb72-2cef-4b98-a1d3-2414a7a40873';
      const String tenantId = 'adee44b2-91fc-40f1-abdd-9cc29351b5fd';
      const String redirectUrl = 'com.biso.no://oauth/callback';

      // OAuth2 request configuration
      final AuthorizationTokenRequest request = AuthorizationTokenRequest(
        clientId,
        redirectUrl,
        // Avoid discovery hangs by providing explicit Azure endpoints
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint:
              'https://login.microsoftonline.com/adee44b2-91fc-40f1-abdd-9cc29351b5fd/oauth2/v2.0/authorize',
          tokenEndpoint:
              'https://login.microsoftonline.com/adee44b2-91fc-40f1-abdd-9cc29351b5fd/oauth2/v2.0/token',
        ),
        scopes: const [
          'openid',
          'email',
          'profile',
          'https://graph.microsoft.com/User.Read',
        ],
        promptValues: const ['select_account'],
      );

      AppLogger.info('Initiating OAuth flow with Microsoft Azure');

      // Perform OAuth flow
      // ignore: unnecessary_nullable_for_final_variable_declarations
      final AuthorizationTokenResponse? response = await _appAuth
          .authorizeAndExchangeCode(request);

      if (response == null) {
        throw StudentException('OAuth flow was cancelled by user');
      }

      final AuthorizationTokenResponse result = response;

      if (result.accessToken == null) {
        throw StudentException('Failed to obtain access token from Microsoft');
      }

      AppLogger.info('OAuth flow completed successfully, fetching user email');

      // Fetch user email from Microsoft Graph API
      final String email = await _fetchUserEmailFromMicrosoft(
        result.accessToken!,
      );

      // Validate email domain
      if (!email.endsWith('@bi.no') && !email.endsWith('@biso.no')) {
        throw StudentException(
          'Please use a valid BI email address ending with @bi.no or @biso.no',
        );
      }

      // Extract student number from email: take local-part as-is
      final String studentNumber = email.split('@').first;

      AppLogger.info(
        'Student number extracted from email',
        extra: {'studentNumber': studentNumber, 'email': email},
      );

      // Get current user
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        throw StudentException('User not authenticated. Please log in first.');
      }

      // Create student ID record
      final studentRecord = await createStudentIdRecord(
        userId: currentUser.id,
        studentNumber: studentNumber,
        isVerified: true, // OAuth verification counts as verified
      );

      // Update user profile to link student ID
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: currentUser.id,
        data: {'student_id': studentNumber, 'student': studentRecord.id},
      );

      AppLogger.info(
        'OAuth student registration completed successfully',
        extra: {
          'userId': currentUser.id,
          'studentNumber': studentNumber,
          'studentRecordId': studentRecord.id,
        },
      );

      return studentNumber;
    } catch (e) {
      AppLogger.error('OAuth student registration failed', error: e.toString());
      if (e is StudentException) {
        rethrow;
      }
      throw StudentException('OAuth registration failed: $e');
    }
  }

  /// Fetches user email from Microsoft Graph API using access token
  Future<String> _fetchUserEmailFromMicrosoft(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/oidc/userinfo'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw StudentException(
          'Failed to fetch user email from Microsoft: ${response.statusCode}',
        );
      }

      final dynamic userData = json.decode(response.body);
      final String? email = userData['email'];

      if (email == null || email.isEmpty) {
        throw StudentException('Email not found in Microsoft user profile');
      }

      return email;
    } catch (e) {
      AppLogger.error(
        'Error fetching user email from Microsoft',
        error: e.toString(),
      );
      throw StudentException('Failed to fetch user email: $e');
    }
  }

  /// Creates a student ID record in the student_id collection
  Future<StudentIdModel> createStudentIdRecord({
    required String userId,
    required String studentNumber,
    bool isVerified = false,
  }) async {
    try {
      final studentData = {
        'user_id': userId,
        'student_number': studentNumber,
        'verified': isVerified,
        'is_member': false, // Will be updated after membership check
        'verified_at': isVerified ? DateTime.now().toIso8601String() : null,
      };

      final createdData = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'student_id',
        rowId: studentNumber,
        data: studentData,
      );

      return StudentIdModel.fromMap(createdData.data);
    } catch (e) {
      throw StudentException('Failed to create student ID record: $e');
    }
  }

  // Note: Previously had a helper to update user-student relationship. Keep logic within specific flows to avoid unused function warnings.

  /// Checks membership status using the existing MembershipService
  /// Returns true if the student is a member
  Future<bool> checkMembershipStatus(String studentNumber) async {
    try {
      AppLogger.info(
        'Checking membership status for student',
        extra: {'studentNumber': studentNumber},
      );

      // Use the existing MembershipService which properly calls verify_biso_membership
      final membershipService = MembershipService();
      final verificationResult = await membershipService.verifyMembership(
        studentNumber,
      );

      AppLogger.info(
        'Membership check completed',
        extra: {
          'studentNumber': studentNumber,
          'isMember': verificationResult.isMember,
          'membershipName': verificationResult.membership?.name,
        },
      );

      return verificationResult.isMember;
    } catch (e) {
      AppLogger.error('Membership check error', error: e.toString());
      throw StudentException('Membership check failed: $e');
    }
  }

  // Removed write-based membership status updates. Verification is read-only via MembershipService.

  /// Gets student ID record for a user
  Future<StudentIdModel?> getStudentIdRecord(String userId) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'student_id',
        queries: [
          Query.equal('user_id', userId).toString(),
          Query.limit(1).toString(),
        ],
      );

      if (documents.rows.isEmpty) {
        return null;
      }

      return StudentIdModel.fromMap(documents.rows.first.data);
    } catch (e) {
      throw StudentException('Failed to get student ID record: $e');
    }
  }

  /// Removes student ID record
  Future<void> removeStudentId(String userId) async {
    try {
      // Get student ID record
      final studentRecord = await getStudentIdRecord(userId);
      if (studentRecord == null) {
        return; // Nothing to remove
      }

      // Remove from student_id collection
      await db.deleteRow(
        databaseId: AppConstants.databaseId,
        tableId: 'student_id',
        rowId: studentRecord.id,
      );

      // Update user profile to remove relationship
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
        data: {'student_id': null, 'student': null},
      );

      AppLogger.info(
        'Student ID removed successfully',
        extra: {'userId': userId, 'studentNumber': studentRecord.studentNumber},
      );
    } catch (e) {
      throw StudentException('Failed to remove student ID: $e');
    }
  }

  /// Launch membership purchase using the existing MembershipService
  Future<void> launchMembershipPurchase() async {
    try {
      // Use the existing membership service to get available memberships
      final membershipService = MembershipService();
      final availableMemberships = await membershipService
          .getAvailableMemberships();

      if (availableMemberships.isEmpty) {
        throw StudentException('No membership options available at the moment');
      }

      // For now, we'll launch the purchase page URL directly
      // In a complete implementation, you would show a membership selection dialog
      // and then call membershipService.initiateMembershipCheckout()
      const membershipUrl = 'https://biso.no/membership';

      if (await canLaunchUrl(Uri.parse(membershipUrl))) {
        await launchUrl(
          Uri.parse(membershipUrl),
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw StudentException('Could not open membership purchase page');
      }
    } catch (e) {
      throw StudentException('Failed to open membership page: $e');
    }
  }
}

class StudentException implements Exception {
  final String message;
  StudentException(this.message);

  @override
  String toString() => message;
}
