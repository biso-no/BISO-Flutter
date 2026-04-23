import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as aw_enums;
import 'package:biso/core/logging/migration_helper.dart';

import '../models/validation_result_model.dart';
import 'appwrite_service.dart';

class ValidatorService {
  late final Functions _functions = functions;

  /// Verifies a pass token by calling the verify_pass_token Appwrite function
  Future<ValidationResultModel> verifyPassToken({
    required String token,
    Map<String, dynamic>? context,
  }) async {
    try {
      final requestBody = {
        'token': token,
        if (context != null) 'context': context,
      };

      final response = await _functions.createExecution(
        functionId: 'verify_pass_token',
        body: json.encode(requestBody),
        xasync: false,
      );

      if (response.status == aw_enums.ExecutionStatus.completed) {
        final responseData = json.decode(response.responseBody);

        // Log the audit entry
        _logValidationAttempt(
          token: token,
          result: responseData,
          context: context,
        );

        return ValidationResultModel.fromJson(responseData);
      } else if (response.status == aw_enums.ExecutionStatus.failed) {
        throw ValidationException(
          'Function execution failed: ${response.responseBody}',
          code: 'FUNCTION_FAILED',
        );
      } else {
        throw ValidationException(
          'Unexpected function status: ${response.status}',
          code: 'UNEXPECTED_STATUS',
        );
      }
    } on AppwriteException catch (e) {
      // Handle specific Appwrite errors
      switch (e.code) {
        case 403:
          throw ValidationException(
            'Unauthorized: You are not permitted to validate tokens',
            code: 'UNAUTHORIZED_SCANNER',
          );
        case 401:
          throw ValidationException(
            'Authentication required',
            code: 'UNAUTHENTICATED',
          );
        case 400:
          throw ValidationException(
            'Invalid token format',
            code: 'TOKEN_INVALID',
          );
        case 409:
          throw ValidationException(
            'Token has already been used',
            code: 'REPLAY_DETECTED',
          );
        case 404:
          throw ValidationException(
            'No active membership found for this user',
            code: 'NO_ACTIVE_MEMBERSHIP',
          );
        default:
          throw ValidationException(
            e.message ?? 'Validation failed',
            code: 'VALIDATION_ERROR',
          );
      }
    } catch (e) {
      throw ValidationException(
        'Network error: ${e.toString()}',
        code: 'NETWORK_ERROR',
      );
    }
  }

  /// Issues a new pass token for the current user (for Student ID screen)
  Future<PassTokenResult> issuePassToken() async {
    try {
      final response = await _functions.createExecution(
        functionId: 'issue_pass_token',
        body: '', // No body needed, uses authenticated user context
        xasync: false,
      );

      if (response.status == aw_enums.ExecutionStatus.completed) {
        final responseData = json.decode(response.responseBody);

        if (responseData['ok'] == true) {
          return PassTokenResult(
            ok: true,
            token: responseData['token'] as String,
            ttlSeconds: responseData['ttlSeconds'] as int,
            serverTime: DateTime.parse(responseData['serverTime'] as String),
          );
        } else {
          throw ValidationException(
            responseData['error'] as String? ?? 'Failed to issue token',
            code: responseData['code'] as String? ?? 'TOKEN_ISSUE_FAILED',
          );
        }
      } else if (response.status == aw_enums.ExecutionStatus.failed) {
        final errorData = json.decode(response.responseBody);
        throw ValidationException(
          errorData['error'] as String? ?? 'Function execution failed',
          code: errorData['code'] as String? ?? 'FUNCTION_FAILED',
        );
      } else {
        throw ValidationException(
          'Unexpected function status: ${response.status}',
          code: 'UNEXPECTED_STATUS',
        );
      }
    } on AppwriteException catch (e) {
      switch (e.code) {
        case 401:
          throw ValidationException(
            'Authentication required',
            code: 'UNAUTHENTICATED',
          );
        case 400:
          throw ValidationException(
            'No student ID found for your account',
            code: 'NO_STUDENT_ID',
          );
        default:
          throw ValidationException(
            e.message ?? 'Failed to issue token',
            code: 'TOKEN_ISSUE_ERROR',
          );
      }
    } catch (e) {
      if (e is ValidationException) rethrow;
      throw ValidationException(
        'Network error: ${e.toString()}',
        code: 'NETWORK_ERROR',
      );
    }
  }

  /// Log validation attempts for audit purposes
  Future<void> _logValidationAttempt({
    required String token,
    required Map<String, dynamic> result,
    Map<String, dynamic>? context,
  }) async {
    try {
      // Extract JTI from the result metadata if available
      final jti = result['meta']?['jti'] as String?;

      // Create audit log entry
      final auditEntry = {
        'timestamp': DateTime.now().toIso8601String(),
        'action': 'token_validation',
        'result': result['ok'] == true ? 'success' : 'failure',
        'resultCode': result['result'] ?? 'UNKNOWN',
        'errorCode': result['code'],
        'jti': jti,
        'context': context,
        // Note: We don't log the actual token for security reasons
        'tokenHash': token.hashCode.toString(), // Just a hash for tracking
      };

      // Store in a dedicated audit collection (you'll need to create this)
      await db.createRow(
        databaseId: 'app',
        tableId:
            'validation_audit', // You'll need to create this collection
        rowId: ID.unique(),
        data: auditEntry,
      );
    } catch (e) {
      logPrint('Failed to log validation attempt: $e');
    }
  }

  /// Check if current user has controller permissions
  Future<bool> hasControllerPermissions() async {
    try {
      // Check if the user is a member of the 'validators' team
      final teamsList = await teams.list();

      // Look for membership in the 'validators' team
      for (final team in teamsList.teams) {
        if (team.$id == 'validators') {
          // User is in the validators team
          return true;
        }
      }

      return false;
    } catch (e) {
      // If there's an error (e.g., user not authenticated, no teams access), return false
      return false;
    }
  }
}

class PassTokenResult {
  final bool ok;
  final String token;
  final int ttlSeconds;
  final DateTime serverTime;
  final String? error;
  final String? code;

  const PassTokenResult({
    required this.ok,
    required this.token,
    required this.ttlSeconds,
    required this.serverTime,
    this.error,
    this.code,
  });

  factory PassTokenResult.error({required String error, String? code}) {
    return PassTokenResult(
      ok: false,
      token: '',
      ttlSeconds: 0,
      serverTime: DateTime.now(),
      error: error,
      code: code,
    );
  }
}

class ValidationException implements Exception {
  final String message;
  final String code;

  const ValidationException(this.message, {required this.code});

  @override
  String toString() => 'ValidationException: $message (Code: $code)';
}
