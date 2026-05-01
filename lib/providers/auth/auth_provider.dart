import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_id_model.dart';
import '../../data/models/membership_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/membership_service.dart';
import '../../data/services/appwrite_service.dart';

import '../../core/logging/print_migration.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});

class AuthState {
  final UserModel? user;
  final StudentIdModel? studentRecord;
  final MembershipVerificationResult? membershipVerification;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final String? pendingUserId; // Store userId from OTP send
  final bool hasProfile;
  final bool isProfileComplete;

  const AuthState({
    this.user,
    this.studentRecord,
    this.membershipVerification,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.pendingUserId,
    this.hasProfile = false,
    this.isProfileComplete = false,
  });

  AuthState copyWith({
    UserModel? user,
    StudentIdModel? studentRecord,
    MembershipVerificationResult? membershipVerification,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
    String? pendingUserId,
    bool? hasProfile,
    bool? isProfileComplete,
  }) {
    return AuthState(
      user: user ?? this.user,
      studentRecord: studentRecord ?? this.studentRecord,
      membershipVerification:
          membershipVerification ?? this.membershipVerification,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      pendingUserId: pendingUserId ?? this.pendingUserId,
      hasProfile: hasProfile ?? this.hasProfile,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
    );
  }

  // Computed properties
  bool get hasStudentId => studentRecord != null;
  String? get studentNumber => studentRecord?.studentNumber;
  bool get isStudentVerified => studentRecord?.isVerified ?? false;
  bool get isStudentMember => membershipVerification?.isMember ?? false;
  bool get hasValidMembership => membershipVerification?.isMember ?? false;
  MembershipModel? get membershipDetails => membershipVerification?.membership;
  String get membershipStatus {
    if (!hasStudentId) return 'No Student ID';
    if (!isStudentVerified) return 'Student ID Pending Verification';
    if (membershipVerification == null) return 'Membership Not Checked';
    if (membershipVerification!.isMember) return 'Active Member';
    return 'Not a Member';
  }

  bool get needsOnboarding => isAuthenticated && !isProfileComplete;
  bool get needsStudentId => isAuthenticated && !hasStudentId;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final MembershipService _membershipService = MembershipService();

  AuthNotifier(this._authService) : super(const AuthState()) {
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.getCurrentUser();

      // If user exists, also load their complete profile
      if (user != null) {
        await _loadCompleteProfile(user.id);
      } else {
        // Server confirmed: no valid session exists
        state = state.copyWith(
          user: null,
          isAuthenticated: false,
          isLoading: false,
          hasProfile: false,
          isProfileComplete: false,
        );
      }
    } on NetworkException catch (e) {
      // Network unavailable — restore from local cache so the user
      // isn't logged out due to a transient connectivity issue.
      final cachedUser = await _authService.getCachedSessionUser();
      if (cachedUser != null) {
        logPrint('🔐 AuthProvider: Network error, restoring session from cache');
        state = state.copyWith(
          user: cachedUser,
          isAuthenticated: true,
          isLoading: false,
          hasProfile: false,
          isProfileComplete: false,
          error: e.message,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          error: e.message,
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        isAuthenticated: false,
        hasProfile: false,
        isProfileComplete: false,
      );
    }
  }

  /// Loads complete user profile from database using RobustDocumentService
  Future<void> _loadCompleteProfile(String userId) async {
    try {
      logPrint('🔐 AuthProvider: Loading complete profile for userId: $userId');

      // Use RobustDocumentService to handle SDK issues
      final documentData = await db.getRow(
        databaseId: 'app',
        tableId: 'user',
        rowId: userId,
      );

      final profile = UserModel.fromMap(documentData.data);
      logPrint('🔐 AuthProvider: Profile loaded successfully: ${profile.name}');

      // Check if user has student_id in their profile
      StudentIdModel? studentRecord;
      MembershipVerificationResult? membershipVerification;

      if (profile.studentId != null && profile.studentId!.isNotEmpty) {
        // Create StudentIdModel from user profile data
        studentRecord = StudentIdModel(
          id: 'profile_${profile.id}', // Synthetic ID since it's from user profile
          userId: profile.id,
          studentNumber: profile.studentId!,
          isVerified: true, // Assume verified since it's in their profile
          createdAt: profile.createdAt ?? DateTime.now(),
        );
        logPrint(
          '🔐 AuthProvider: Student ID found in profile: ${studentRecord.studentNumber}',
        );

        // Check membership status using the student number
        try {
          membershipVerification = await _membershipService.verifyMembership(
            studentRecord.studentNumber,
          );
          logPrint(
            '🔐 AuthProvider: Membership verified: ${membershipVerification.isMember}',
          );
        } catch (e) {
          logPrint('🔐 AuthProvider: Error verifying membership: $e');
        }
      } else {
        logPrint('🔐 AuthProvider: No student ID found in user profile');
      }

      final hasProfile = true;
      final isProfileComplete =
          profile.campusId != null && profile.campusId!.isNotEmpty;

      state = state.copyWith(
        user: profile,
        studentRecord: studentRecord,
        membershipVerification: membershipVerification,
        isAuthenticated: true,
        isLoading: false,
        hasProfile: hasProfile,
        isProfileComplete: isProfileComplete,
      );
    } catch (e) {
      if (e.toString().contains('404')) {
        // Profile doesn't exist yet - user needs onboarding
        logPrint(
          '🔐 AuthProvider: Profile not found (404) - user needs onboarding',
        );

        // Get basic user info from auth service
        final basicUser = await _authService.getCurrentUser();

        state = state.copyWith(
          user: basicUser,
          isAuthenticated: true,
          isLoading: false,
          hasProfile: false,
          isProfileComplete: false,
        );
      } else if (e is NetworkException) {
        // Network error while loading profile — user is still authenticated,
        // just couldn't fetch full profile details right now.
        logPrint('🔐 AuthProvider: Network error loading profile: $e');
        rethrow; // Let _checkAuthState handle via NetworkException branch
      } else {
        logPrint('🔐 AuthProvider: Error loading profile: $e');
        // Keep the user authenticated — a profile fetch error is not a sign-out event.
        // The basic user object from the session check is sufficient for now.
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          hasProfile: false,
          isProfileComplete: false,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> sendMagicLink(String email) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userId = await _authService.sendMagicLink(email);
      state = state.copyWith(isLoading: false, pendingUserId: userId);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        pendingUserId: null,
      );
      rethrow;
    }
  }

  Future<void> sendOtp(String email) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userId = await _authService.sendOtp(email);
      state = state.copyWith(isLoading: false, pendingUserId: userId);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        pendingUserId: null,
      );
      rethrow;
    }
  }

  Future<void> verifyMagicLink(String userId, String secret) async {
    logPrint(
      '🔗 DEBUG: Starting verifyMagicLink with userId: $userId, secret: $secret',
    );
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.verifyMagicLink(userId, secret);
      logPrint('🔗 DEBUG: Magic link verification successful, user: ${user.email}');

      // After successful magic link verification, load complete profile
      await _loadCompleteProfile(user.id);

      // Clear pending userId
      state = state.copyWith(pendingUserId: null);
    } catch (e) {
      logPrint('🔗 DEBUG: Magic link verification failed: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  Future<void> verifyOtp(String userId, String secret) async {
    logPrint(
      '🔥 DEBUG: Starting verifyOtp with userId: $userId, secret: $secret',
    );
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.verifyOtp(userId, secret);
      logPrint('🔥 DEBUG: OTP verification successful, user: ${user.email}');

      // After successful OTP verification, load complete profile
      await _loadCompleteProfile(user.id);

      // Clear pending userId
      state = state.copyWith(pendingUserId: null);
    } catch (e) {
      logPrint('🔥 DEBUG: OTP verification failed: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  Future<void> createProfile({
    required String name,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    List<String>? departments,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.createUserProfile(
        name: name,
        phone: phone,
        address: address,
        city: city,
        zipCode: zipCode,
        campusId: campusId,
        departments: departments,
      );

      final hasProfile = true;
      final isProfileComplete = campusId != null && campusId.isNotEmpty;

      state = state.copyWith(
        user: user,
        isLoading: false,
        hasProfile: hasProfile,
        isProfileComplete: isProfileComplete,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    List<String>? departments,
    dynamic avatarFile, // XFile or File
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final updatedUser = await _authService.updateUserProfile(
        name: name,
        phone: phone,
        address: address,
        city: city,
        zipCode: zipCode,
        campusId: campusId,
        departments: departments,
        avatarFile: avatarFile,
      );

      final hasProfile = true;
      final isProfileComplete =
          updatedUser.campusId != null && updatedUser.campusId!.isNotEmpty;

      state = state.copyWith(
        user: updatedUser,
        isLoading: false,
        hasProfile: hasProfile,
        isProfileComplete: isProfileComplete,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  Future<void> updatePaymentInformation({
    required String bankAccount,
    String? swift,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final updatedUser = await _authService.updatePaymentInformation(
        bankAccount: bankAccount,
        swift: swift,
      );

      state = state.copyWith(user: updatedUser, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await logout();
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.logout();
      // Clear JWT cache when user signs out
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> clearSession() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.clearSession();
      // Clear JWT cache when session is cleared
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Refresh complete profile (useful after updates)
  Future<void> refreshProfile() async {
    final currentUser = state.user;
    if (currentUser != null) {
      await _loadCompleteProfile(currentUser.id);
    }
  }

  /// Register student ID via OAuth
  Future<void> registerStudentIdViaOAuth() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.registerStudentIdViaOAuth();

      // Reload profile to get updated student information
      final currentUser = state.user;
      if (currentUser != null) {
        await _loadCompleteProfile(currentUser.id);
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      final message = e.toString();
      // Treat user cancellation as a benign outcome
      if (message.contains('User cancelled flow') ||
          message.contains('USER_CANCELLED') ||
          message.contains('FlutterAppAuthUserCancelledException')) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(error: message, isLoading: false);
    }
  }

  /// Check and update membership status using proper membership verification
  Future<void> checkMembershipStatus() async {
    final studentRecord = state.studentRecord;
    if (studentRecord == null || !studentRecord.isVerified) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final membershipVerification = await _membershipService.verifyMembership(
        studentRecord.studentNumber,
      );
      state = state.copyWith(
        membershipVerification: membershipVerification,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Remove student ID
  Future<void> removeStudentId() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.removeStudentId();

      state = state.copyWith(studentRecord: null, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  /// Launch membership purchase page
  Future<void> launchMembershipPurchase() async {
    try {
      await _authService.launchMembershipPurchase();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }
}

// Helper providers for simplified access
final currentUserProvider = Provider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isAuthenticated;
});

final hasProfileProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.hasProfile;
});

final isProfileCompleteProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isProfileComplete;
});

final hasStudentIdProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.hasStudentId;
});

final studentNumberProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.studentNumber;
});

final needsOnboardingProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.needsOnboarding;
});

// Student-related providers
final studentRecordProvider = Provider<StudentIdModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.studentRecord;
});

final isStudentVerifiedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isStudentVerified;
});

final isStudentMemberProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isStudentMember;
});

final hasValidMembershipProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.hasValidMembership;
});

final membershipStatusProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.membershipStatus;
});
