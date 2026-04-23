import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/membership_model.dart';
import '../../data/services/membership_service.dart';

class MembershipState {
  final MembershipModel? membership;
  final bool isLoading;
  final String? error;
  final bool isVerified;
  final MembershipVerificationResult? verificationResult;

  const MembershipState({
    this.membership,
    this.isLoading = false,
    this.error,
    this.isVerified = false,
    this.verificationResult,
  });

  MembershipState copyWith({
    MembershipModel? membership,
    bool? isLoading,
    String? error,
    bool? isVerified,
    MembershipVerificationResult? verificationResult,
  }) {
    return MembershipState(
      membership: membership ?? this.membership,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isVerified: isVerified ?? this.isVerified,
      verificationResult: verificationResult ?? this.verificationResult,
    );
  }
}

class MembershipNotifier extends StateNotifier<MembershipState> {
  final MembershipService _membershipService;
  RealtimeSubscription? _membershipSubscription;
  RealtimeSubscription? _studentIdSubscription;

  MembershipNotifier(this._membershipService) : super(const MembershipState());

  /// Verifies membership status for a given student ID
  Future<void> verifyMembership(String studentId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final verificationResult = await _membershipService.verifyMembership(
        studentId,
      );

      state = state.copyWith(
        isLoading: false,
        isVerified: verificationResult.isMember,
        verificationResult: verificationResult,
        membership: verificationResult.membership,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        isVerified: false,
      );
    }
  }

  /// Loads user's membership from the database
  Future<void> loadUserMembership(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final membership = await _membershipService.getUserMembership(userId);

      state = state.copyWith(
        isLoading: false,
        membership: membership,
        isVerified: membership?.isActive == true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Gets available membership options
  Future<List<MembershipPurchaseOption>> getAvailableMemberships() async {
    try {
      return await _membershipService.getAvailableMemberships();
    } catch (e) {
      throw Exception('Failed to load memberships: $e');
    }
  }

  /// Initiates membership purchase
  Future<void> purchaseMembership({
    required String membershipId,
    required String membershipName,
    required int amount,
    required String paymentMethod,
    String? phoneNumber,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final checkoutUrl = await _membershipService.initiateMembershipCheckout(
        membershipId: membershipId,
        membershipName: membershipName,
        amount: amount,
        description: 'BISO Membership: $membershipName',
        returnUrl: 'com.biso.no://payment/success', // Your app's return URL
        phoneNumber: phoneNumber,
        paymentMethod: paymentMethod,
      );

      if (checkoutUrl != null) {
        // Launch checkout URL
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          state = state.copyWith(isLoading: false, error: null);
        } else {
          throw Exception('Could not launch checkout URL');
        }
      } else {
        throw Exception('No checkout URL received');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Subscribes to real-time student ID updates
  void _subscribeToStudentIdUpdates(String userId) {
    _studentIdSubscription?.close();
    _studentIdSubscription = _membershipService.subscribeToStudentIdUpdates(
      userId,
      (message) {
        final payload = message.payload;
        final studentNumber = payload['student_number'] as String?;

        if (studentNumber != null) {
          verifyMembership(studentNumber);
        }
      },
    );
  }

  /// Subscribes to real-time membership updates
  void _subscribeToMembershipUpdates(String userId) {
    _membershipSubscription?.close();
    _membershipSubscription = _membershipService.subscribeToMembershipUpdates(
      userId,
      (_) {
        loadUserMembership(userId);
      },
    );
  }

  /// Starts subscriptions for both student ID and membership updates
  void startSubscriptions(String userId) {
    _subscribeToStudentIdUpdates(userId);
    _subscribeToMembershipUpdates(userId);
  }

  /// Stops all subscriptions
  void stopSubscriptions() {
    _studentIdSubscription?.close();
    _membershipSubscription?.close();
    _studentIdSubscription = null;
    _membershipSubscription = null;
  }

  @override
  void dispose() {
    stopSubscriptions();
    super.dispose();
  }
}

// Providers
final membershipServiceProvider = Provider<MembershipService>((ref) {
  return MembershipService();
});

final membershipProvider =
    StateNotifierProvider<MembershipNotifier, MembershipState>((ref) {
      final membershipService = ref.read(membershipServiceProvider);
      return MembershipNotifier(membershipService);
    });

// Helper provider to combine membership state with student verification
final membershipStatusProvider =
    Provider<({bool hasStudentId, bool isMember, MembershipModel? membership})>(
      (ref) {
        final membershipState = ref.watch(membershipProvider);

        // You might want to also watch a student ID provider if you have one
        // For now, we'll determine hasStudentId from the verification result
        final hasStudentId = membershipState.verificationResult != null;

        return (
          hasStudentId: hasStudentId,
          isMember: membershipState.isVerified,
          membership: membershipState.membership,
        );
      },
    );
