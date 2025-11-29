import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../models/public_profile_model.dart';
import 'appwrite_service.dart';

class PublicProfileService {
  static final PublicProfileService _instance =
      PublicProfileService._internal();
  factory PublicProfileService() => _instance;
  PublicProfileService._internal();

  // Note: Using RobustDocumentService for all database operations

  /// Create a public profile for a user
  Future<PublicProfileModel> createPublicProfile({
    required String userId,
    required String name,
    String? email,
    String? phone,
    String? campusId,
    String? avatar,
    bool emailVisible = false,
    bool phoneVisible = false,
  }) async {
    try {
      final profileData = {
        'user_id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'campus_id': campusId,
        'avatar': avatar,
        'email_visible': emailVisible,
        'phone_visible': phoneVisible,
      };

      final document = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        rowId: ID.unique(),
        data: profileData,
      );

      return PublicProfileModel.fromMap(document.data);
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to create public profile: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Get a user's public profile by user ID
  Future<PublicProfileModel?> getPublicProfileByUserId(String userId) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        queries: [Query.equal('user_id', userId), Query.limit(1)],
      );

      if (documents.rows.isEmpty) {
        return null;
      }

      return PublicProfileModel.fromMap(documents.rows.first.data);
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to get public profile: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Update a user's public profile
  Future<PublicProfileModel> updatePublicProfile({
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? campusId,
    String? avatar,
    bool? emailVisible,
    bool? phoneVisible,
  }) async {
    try {
      // First, get the current public profile
      final currentProfile = await getPublicProfileByUserId(userId);
      if (currentProfile == null) {
        throw PublicProfileException('Public profile not found for user');
      }

      final updateData = <String, dynamic>{};
      if (name != null) updateData['name'] = name;
      if (email != null) updateData['email'] = email;
      if (phone != null) updateData['phone'] = phone;
      if (campusId != null) updateData['campus_id'] = campusId;
      if (avatar != null) updateData['avatar'] = avatar;
      if (emailVisible != null) updateData['email_visible'] = emailVisible;
      if (phoneVisible != null) updateData['phone_visible'] = phoneVisible;

      final document = await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        rowId: currentProfile.id,
        data: updateData,
      );

      return PublicProfileModel.fromMap(document.data);
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to update public profile: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Delete a user's public profile
  Future<void> deletePublicProfile(String userId) async {
    try {
      final currentProfile = await getPublicProfileByUserId(userId);
      if (currentProfile == null) {
        return; // Profile doesn't exist, nothing to delete
      }

      await db.deleteRow(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        rowId: currentProfile.id,
      );
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to delete public profile: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Search public profiles by name
  Future<List<PublicProfileModel>> searchPublicProfiles({
    required String query,
    String? campusId,
    int limit = 20,
  }) async {
    try {
      if (query.trim().isEmpty) return [];

      List<String> queries = [
        Query.search('name', query),
        Query.limit(limit),
        Query.orderAsc('name'),
      ];

      // Filter by campus if specified
      if (campusId != null && campusId.isNotEmpty) {
        queries.add(Query.equal('campus_id', campusId));
      }

      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        queries: queries,
      );

      return documents.rows.map((doc) => PublicProfileModel.fromMap(doc.data)).toList();
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to search public profiles: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Get public profiles for multiple user IDs
  Future<List<PublicProfileModel>> getMultiplePublicProfiles(
    List<String> userIds,
  ) async {
    try {
      if (userIds.isEmpty) return [];

      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        queries: [
          Query.contains('user_id', userIds),
          Query.limit(userIds.length),
        ],
      );

      return documents.rows.map((doc) => PublicProfileModel.fromMap(doc.data)).toList();
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to get multiple public profiles: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }

  /// Check if user has a public profile
  Future<bool> hasPublicProfile(String userId) async {
    try {
      final profile = await getPublicProfileByUserId(userId);
      return profile != null;
    } catch (e) {
      return false;
    }
  }

  /// Sync public profile with user data (called when user updates their profile)
  Future<PublicProfileModel?> syncWithUserData({
    required String userId,
    required String name,
    String? email,
    String? phone,
    String? campusId,
    String? avatar,
  }) async {
    try {
      final existingProfile = await getPublicProfileByUserId(userId);
      if (existingProfile == null) {
        return null; // No public profile to sync
      }

      // Update the public profile with new user data
      return await updatePublicProfile(
        userId: userId,
        name: name,
        email: email,
        phone: phone,
        campusId: campusId,
        avatar: avatar,
        // Keep existing visibility settings
        emailVisible: existingProfile.emailVisible,
        phoneVisible: existingProfile.phoneVisible,
      );
    } catch (e) {
      throw PublicProfileException('Failed to sync public profile: $e');
    }
  }

  /// Get public profiles by campus
  Future<List<PublicProfileModel>> getPublicProfilesByCampus({
    required String campusId,
    int limit = 50,
  }) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'public_profiles',
        queries: [
          Query.equal('campus_id', campusId),
          Query.orderAsc('name'),
          Query.limit(limit),
        ],
      );

      return documents.rows.map((doc) => PublicProfileModel.fromMap(doc.data)).toList();
    } on AppwriteException catch (e) {
      throw PublicProfileException(
        'Failed to get campus public profiles: ${e.message}',
      );
    } catch (e) {
      throw PublicProfileException('Network error occurred');
    }
  }
}

class PublicProfileException implements Exception {
  final String message;
  PublicProfileException(this.message);

  @override
  String toString() => message;
}
