import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'public_profile_service.dart';
import 'appwrite_service.dart';

class PrivacyService {
  static final PrivacyService _instance = PrivacyService._internal();
  factory PrivacyService() => _instance;
  PrivacyService._internal();

  /// Check if user has set their privacy preference
  /// Returns null if not set, true if public, false if private
  Future<bool?> getUserPrivacySetting(String userId) async {
    try {
      final document = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
      );

      return document.data['is_public'] as bool?;
    } catch (e) {
      return null;
    }
  }

  /// Update user's privacy setting and manage public profile
  Future<bool> setUserPrivacySetting(
    String userId,
    bool isPublic, {
    UserModel? userData,
  }) async {
    try {
      final publicProfileService = PublicProfileService();

      if (isPublic) {
        // Create public profile if making user public
        await _createPublicProfileIfNeeded(userId, userData);
      } else {
        // Delete public profile if making user private
        await publicProfileService.deletePublicProfile(userId);
      }

      // Update the user's privacy setting
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
        data: {'is_public': isPublic},
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if user should be prompted for privacy setting
  /// Returns true if user has null privacy setting (hasn't been asked)
  Future<bool> shouldPromptForPrivacy(String userId) async {
    final setting = await getUserPrivacySetting(userId);
    return setting == null;
  }

  /// Get a user's current privacy status with helpful description
  Future<String> getPrivacyStatusDescription(String userId) async {
    final isPublic = await getUserPrivacySetting(userId);

    if (isPublic == null) {
      return 'Privacy setting not configured';
    } else if (isPublic) {
      return 'Public - Others can find and message you';
    } else {
      return 'Private - Others cannot find you in search';
    }
  }

  /// Check if user has a public profile
  Future<bool> hasPublicProfile(String userId) async {
    final publicProfileService = PublicProfileService();
    return await publicProfileService.hasPublicProfile(userId);
  }

  /// Create public profile with user data
  Future<void> createPublicProfileFromUserData(
    UserModel userData, {
    bool emailVisible = false,
    bool phoneVisible = false,
  }) async {
    final publicProfileService = PublicProfileService();
    await publicProfileService.createPublicProfile(
      userId: userData.id,
      name: userData.name,
      email: userData.email,
      phone: userData.phone,
      campusId: userData.campusId,
      avatar: userData.avatarUrl,
      emailVisible: emailVisible,
      phoneVisible: phoneVisible,
    );
  }

  /// Sync public profile when user data changes
  Future<void> syncPublicProfile(UserModel userData) async {
    final publicProfileService = PublicProfileService();
    await publicProfileService.syncWithUserData(
      userId: userData.id,
      name: userData.name,
      email: userData.email,
      phone: userData.phone,
      campusId: userData.campusId,
      avatar: userData.avatarUrl,
    );
  }

  /// Private helper to create public profile if needed
  Future<void> _createPublicProfileIfNeeded(
    String userId,
    UserModel? userData,
  ) async {
    final publicProfileService = PublicProfileService();
    final hasProfile = await publicProfileService.hasPublicProfile(userId);

    if (hasProfile) {
      // Profile already exists, sync with current user data if provided
      if (userData != null) {
        await syncPublicProfile(userData);
      }
      return;
    }

    // Need to fetch user data if not provided
    UserModel user;
    if (userData != null) {
      user = userData;
    } else {
      final userDoc = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
      );
      user = UserModel.fromMap(userDoc.data);
    }

    // Create new public profile
    await createPublicProfileFromUserData(user);
  }
}
