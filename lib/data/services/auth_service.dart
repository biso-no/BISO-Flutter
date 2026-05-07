import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/student_id_model.dart';
import 'appwrite_service.dart';
import 'privacy_service.dart';
import 'student_service.dart';
import '../../core/logging/app_logger.dart';

import '../../core/logging/print_migration.dart';

class AuthService {
  // Using simplified global Appwrite instances
  Account get _account => account;
  TablesDB get _databases => db;
  Storage get _storage => storage;

  // Student service for managing student verification
  final StudentService _studentService = StudentService();

  // SharedPreferences keys for local session cache
  static const _cachedUserIdKey = 'session_user_id';
  static const _cachedUserEmailKey = 'session_user_email';
  static const _cachedUserNameKey = 'session_user_name';

  Future<void> _cacheSessionUser(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedUserIdKey, user.id);
      await prefs.setString(_cachedUserEmailKey, user.email);
      await prefs.setString(_cachedUserNameKey, user.name);
    } catch (_) {}
  }

  Future<UserModel?> getCachedSessionUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_cachedUserIdKey);
      if (userId == null || userId.isEmpty) return null;
      return UserModel(
        id: userId,
        email: prefs.getString(_cachedUserEmailKey) ?? '',
        name: prefs.getString(_cachedUserNameKey) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedUserIdKey);
      await prefs.remove(_cachedUserEmailKey);
      await prefs.remove(_cachedUserNameKey);
    } catch (_) {}
  }

  Future<String> sendMagicLink(String email) async {
    try {
      AppLogger.auth(
        'Creating magic link for user',
        action: 'send_magic_link',
        extra: {
          'email': email.replaceAll(
            RegExp(r'(.{2}).*(@.*)'),
            r'\1***\2',
          ), // Mask email for privacy
        },
      );

      // Generate a unique ID for this magic link session
      final userId = ID.unique();

      // Create magic URL with custom scheme
      const magicLinkUrl = 'https://biso.no/auth/verify';

      final token = await _account.createMagicURLToken(
        userId: userId,
        email: email,
        url: magicLinkUrl,
      );

      AppLogger.auth(
        'Magic link token created successfully',
        userId: token.userId,
        action: 'magic_link_created',
        extra: {
          'token_user_id': token.userId,
          'session_user_id': userId,
          'ids_match': userId == token.userId,
        },
      );

      return token.userId;
    } on AppwriteException catch (e) {
      throw AuthException('Failed to send magic link: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred');
    }
  }

  Future<String> sendOtp(String email) async {
    try {
      AppLogger.auth(
        'Creating OTP for user',
        action: 'send_otp',
        extra: {
          'email': email.replaceAll(
            RegExp(r'(.{2}).*(@.*)'),
            r'\1***\2',
          ), // Mask email for privacy
        },
      );

      // Generate a unique ID for this OTP session
      final userId = ID.unique();

      final token = await _account.createEmailToken(
        userId: userId,
        email: email,
      );

      AppLogger.auth(
        'OTP token created successfully',
        userId: token.userId,
        action: 'otp_created',
        extra: {
          'token_user_id': token.userId,
          'session_user_id': userId,
          'ids_match': userId == token.userId,
        },
      );

      return token.userId;
    } on AppwriteException catch (e) {
      throw AuthException('Failed to send OTP: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred');
    }
  }

  Future<UserModel> verifyMagicLink(String userId, String secret) async {
    logPrint(
      '🔗 DEBUG: Starting verifyMagicLink with userId: $userId, secret: $secret',
    );
    try {
      // Create session with magic link tokens
      logPrint('🔗 DEBUG: About to call _account.createSession for magic link...');
      logPrint('🔗 DEBUG: Parameters - userId: $userId, secret: $secret');
      final session = await _account.createSession(
        userId: userId,
        secret: secret,
      );
      logPrint('🔗 DEBUG: Magic link session created successfully!');
      logPrint('🔗 DEBUG: Session ID: ${session.$id}');
      logPrint('🔗 DEBUG: Session userId: ${session.userId}');
      logPrint('🔗 DEBUG: Session provider: ${session.provider}');

      // Get user account info
      final accountUser = await _account.get();

      // Check if user profile exists in database
      UserModel? userProfile;
      try {
        final doc = await _databases.getRow(
          databaseId: AppConstants.databaseId,
          tableId: 'user',
          rowId: accountUser.$id,
        );
        userProfile = UserModel.fromMap(doc.data);
      } catch (e) {
        // User profile doesn't exist, will need onboarding
      }

      final result = userProfile ??
          UserModel(
            id: accountUser.$id,
            name: accountUser.name,
            email: accountUser.email,
          );
      await _cacheSessionUser(result);
      return result;
    } on AppwriteException catch (e) {
      logPrint(
        '🔗 DEBUG: AppwriteException - Code: ${e.code}, Message: ${e.message}',
      );
      logPrint('🔗 DEBUG: AppwriteException - Type: ${e.type}');
      logPrint('🔗 DEBUG: AppwriteException - Response: ${e.response}');
      
      // Handle specific magic link errors
      if (e.message?.contains('Invalid credentials') == true ||
          e.message?.contains('User (role: guests) missing scope') == true ||
          e.code == 401) {
        throw MagicLinkException('This magic link has expired or is invalid. Please request a new one.');
      } else if (e.message?.contains('A user with the same email already exists') == true) {
        throw MagicLinkException('You may already have an active session. Try clearing your session and signing in again.');
      }
      
      throw MagicLinkException('Failed to sign in with magic link: ${e.message}');
    } catch (e) {
      logPrint('🔗 DEBUG: General exception: $e');
      throw MagicLinkException('Magic link sign-in failed');
    }
  }

  Future<UserModel> verifyOtp(String userId, String secret) async {
    logPrint(
      '🔥 DEBUG: Starting verifyOtp with userId: $userId, secret: $secret',
    );
    try {
      // Create session with OTP
      logPrint('🔥 DEBUG: About to call _account.createSession...');
      logPrint('🔥 DEBUG: Parameters - userId: $userId, secret: $secret');
      final session = await _account.createSession(
        userId: userId,
        secret: secret,
      );
      logPrint('🔥 DEBUG: Session created successfully!');
      logPrint('🔥 DEBUG: Session ID: ${session.$id}');
      logPrint('🔥 DEBUG: Session userId: ${session.userId}');
      logPrint('🔥 DEBUG: Session provider: ${session.provider}');
      logPrint('🔥 DEBUG: Full session object: $session');

      // Get user account info
      final accountUser = await _account.get();

      // Check if user profile exists in database
      UserModel? userProfile;
      try {
        final doc = await _databases.getRow(
          databaseId: AppConstants.databaseId,
          tableId: 'user',
          rowId: accountUser.$id,
        );
        userProfile = UserModel.fromMap(doc.data);
      } catch (e) {
        // User profile doesn't exist, will need onboarding
      }

      final result = userProfile ??
          UserModel(
            id: accountUser.$id,
            name: accountUser.name,
            email: accountUser.email,
          );
      await _cacheSessionUser(result);
      return result;
    } on AppwriteException catch (e) {
      logPrint(
        '🔥 DEBUG: AppwriteException - Code: ${e.code}, Message: ${e.message}',
      );
      logPrint('🔥 DEBUG: AppwriteException - Type: ${e.type}');
      logPrint('🔥 DEBUG: AppwriteException - Response: ${e.response}');
      throw AuthException('Invalid verification code: ${e.message}');
    } catch (e) {
      logPrint('🔥 DEBUG: General exception: $e');
      throw AuthException('Verification failed');
    }
  }

  Future<UserModel?> getCurrentUser() async {
    try {
      final accountUser = await _account.get();

      try {
        final doc = await _databases.getRow(
          databaseId: AppConstants.databaseId,
          tableId: 'user',
          rowId: accountUser.$id,
          queries: [
            Query.select([
              'name',
              'email',
              'phone',
              'address',
              'city',
              'zip',
              'campus_id',
              'avatar',
              '\$id',
              'student_id',
            ]),
          ],
        );
        return UserModel.fromMap(doc.data);
      } catch (e) {
        // User profile doesn't exist
        return UserModel(
          id: accountUser.$id,
          name: accountUser.name,
          email: accountUser.email,
        );
      }
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        // Server confirmed no valid session — clear local cache
        await _clearSessionCache();
        return null;
      }
      throw AuthException('Failed to get current user: ${e.message}');
    } catch (e) {
      // Network/connectivity error — don't clear the local cache;
      // the caller should distinguish this from "not authenticated".
      throw NetworkException('Network error: $e');
    }
  }

  Future<void> logout() async {
    await _clearSessionCache();
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException catch (e) {
      throw AuthException('Logout failed: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred');
    }
  }

  Future<void> clearSession() async {
    await _clearSessionCache();
    try {
      // Try to delete the current session
      await _account.deleteSession(sessionId: 'current');
    } catch (e) {
      // Session might not exist, which is fine
    }

    try {
      // Also try to delete all sessions to be thorough
      await _account.deleteSessions();
    } catch (e) {
      // Sessions might not exist, which is fine
    }
  }

  Future<UserModel> createUserProfile({
    required String name,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    List<String>? departments,
    String? bankAccount,
  }) async {
    try {
      final accountUser = await _account.get();

      final userData = {
        'name': name,
        'email': accountUser.email,
        'phone': phone,
        'address': address,
        'city': city,
        'zip': zipCode,
        'campus_id': campusId,
        'departments': departments ?? [],
        'bank_account': bankAccount,
      };

      final doc = await _databases.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: accountUser.$id,
        data: userData,
      );

      return UserModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      throw AuthException('Failed to create profile: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred');
    }
  }

  Future<UserModel> updateUserProfile({
    String? name,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    List<String>? departments,
    dynamic avatarFile, // XFile or File
    String? bankAccount,
  }) async {
    try {
      // Get current user first
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        throw AuthException('User not authenticated');
      }

      // Handle avatar upload if provided
      String? avatarUrl = currentUser.avatarUrl;
      if (avatarFile != null) {
        try {
          avatarUrl = await _uploadAvatar(avatarFile, currentUser.id);
        } catch (e) {
          logPrint('🔴 Avatar upload failed: $e');
          // Continue with profile update even if avatar upload fails
        }
      }

      // Create updated user data
      final updatedData = {
        'name': name ?? currentUser.name,
        'phone': phone ?? currentUser.phone,
        'address': address ?? currentUser.address,
        'city': city ?? currentUser.city,
        'zip': zipCode ?? currentUser.zipCode,
        'campus_id': campusId ?? currentUser.campusId,
        'departments': departments ?? currentUser.departments,
        'avatar': avatarUrl,
        'bank_account': bankAccount ?? currentUser.bankAccount,
      };

      final doc = await _databases.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: currentUser.id,
        data: updatedData,
      );

      final updatedUser = UserModel.fromMap(doc.data);

      // Sync public profile if user is public
      try {
        final privacyService = PrivacyService();
        if (updatedUser.isPublic == true) {
          await privacyService.syncPublicProfile(updatedUser);
        }
      } catch (e) {
        logPrint('🔴 Failed to sync public profile: $e');
        // Don't fail the entire profile update if public profile sync fails
      }

      return updatedUser;
    } on AppwriteException catch (e) {
      throw AuthException('Failed to update profile: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred: $e');
    }
  }

  /// Uploads an avatar image to Appwrite Storage and returns the file URL
  Future<String> _uploadAvatar(dynamic avatarFile, String userId) async {
    try {
      // Delete any existing avatar for this user
      try {
        final existingFiles = await _storage.listFiles(bucketId: 'avatars');
        final userAvatars = existingFiles.files.where(
          (file) => file.name.startsWith('avatar_$userId'),
        );
        for (final file in userAvatars) {
          await _storage.deleteFile(bucketId: 'avatars', fileId: file.$id);
        }
      } catch (e) {
        // Ignore errors when deleting old avatars
        logPrint('🟡 Could not delete existing avatar: $e');
      }

      // Create a unique file ID for this avatar
      final fileId =
          'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}';

      // Prepare the file for upload
      InputFile inputFile;
      if (avatarFile is XFile) {
        inputFile = InputFile.fromPath(
          path: avatarFile.path,
          filename: '$fileId.jpg',
        );
      } else if (avatarFile is File) {
        inputFile = InputFile.fromPath(
          path: avatarFile.path,
          filename: '$fileId.jpg',
        );
      } else {
        throw AuthException('Invalid file type for avatar upload');
      }

      // Upload the file to Appwrite Storage
      final file = await _storage.createFile(
        bucketId: 'avatars',
        fileId: fileId,
        file: inputFile,
      );

      // Generate the file URL for viewing
      final fileUrl =
          '${AppConstants.appwriteEndpoint}/storage/buckets/avatars/files/${file.$id}/view?project=${AppConstants.appwriteProjectId}';

      logPrint('✅ Avatar uploaded successfully: $fileUrl');
      return fileUrl;
    } on AppwriteException catch (e) {
      logPrint('🔴 Appwrite avatar upload error: ${e.message}');
      throw AuthException('Failed to upload avatar: ${e.message}');
    } catch (e) {
      logPrint('🔴 General avatar upload error: $e');
      throw AuthException('Avatar upload failed: $e');
    }
  }

  /// Register student ID via OAuth (Azure)
  Future<String> registerStudentIdViaOAuth() async {
    try {
      return await _studentService.registerStudentIdViaOAuth();
    } catch (e) {
      if (e is StudentException) {
        throw AuthException(e.message);
      }
      throw AuthException('Student ID registration failed: $e');
    }
  }

  /// Check membership status for a student
  Future<bool> checkMembershipStatus(String studentNumber) async {
    try {
      return await _studentService.checkMembershipStatus(studentNumber);
    } catch (e) {
      if (e is StudentException) {
        throw AuthException(e.message);
      }
      throw AuthException('Failed to check membership: $e');
    }
  }

  /// Get student ID record for current user
  Future<StudentIdModel?> getStudentIdRecord() async {
    try {
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        return null;
      }

      return await _studentService.getStudentIdRecord(currentUser.id);
    } catch (e) {
      if (e is StudentException) {
        throw AuthException(e.message);
      }
      throw AuthException('Failed to get student ID: $e');
    }
  }

  // Removed write-based membership status updates. Verification is read-only via MembershipService.

  /// Remove student ID
  Future<void> removeStudentId() async {
    try {
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        throw AuthException('User not authenticated');
      }

      await _studentService.removeStudentId(currentUser.id);
    } catch (e) {
      if (e is StudentException) {
        throw AuthException(e.message);
      }
      throw AuthException('Failed to remove student ID: $e');
    }
  }

  /// Launch membership purchase page
  Future<void> launchMembershipPurchase() async {
    try {
      await _studentService.launchMembershipPurchase();
    } catch (e) {
      if (e is StudentException) {
        throw AuthException(e.message);
      }
      throw AuthException('Failed to open membership page: $e');
    }
  }

  /// Update payment information (bank account and SWIFT code)
  Future<UserModel> updatePaymentInformation({
    required String bankAccount,
    String? swift,
  }) async {
    try {
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        throw AuthException('User not authenticated');
      }

      AppLogger.auth(
        'Updating payment information',
        userId: currentUser.id,
        action: 'update_payment_info',
        extra: {
          'has_bank_account': bankAccount.isNotEmpty,
          'has_swift': swift?.isNotEmpty == true,
        },
      );

      // Prepare update data
      final updateData = <String, dynamic>{'bank_account': bankAccount};

      // Only include SWIFT if provided, otherwise set to null
      updateData['swift'] = swift?.isNotEmpty == true ? swift : null;

      // Update user document in Appwrite
      final response = await _databases.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: currentUser.id,
        data: updateData,
      );

      AppLogger.auth(
        'Payment information updated successfully',
        userId: currentUser.id,
        action: 'payment_info_updated',
      );

      // Return updated user model
      return UserModel.fromDocument(response);
    } on AppwriteException catch (e) {
      throw AuthException('Failed to update payment information: ${e.message}');
    } catch (e) {
      throw AuthException('Network error occurred: $e');
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class MagicLinkException implements Exception {
  final String message;
  MagicLinkException(this.message);

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => message;
}
