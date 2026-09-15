import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/board_member_model.dart';
import '../../data/services/leadership_service.dart';

final leadershipServiceProvider = Provider<LeadershipService>(
  (ref) => LeadershipService(),
);

// Board members for a campus: the campus's own management board.
final boardMembersProvider =
    FutureProvider.family<BoardMembersResponse, String>((ref, campusId) {
      return ref
          .watch(leadershipServiceProvider)
          .getBoardMembers(campusId: campusId);
    });

// Board members for a department, filtered to the campus it belongs to.
final boardMembersWithDepartmentProvider =
    FutureProvider.family<BoardMembersResponse, BoardMembersParams>((
      ref,
      params,
    ) {
      return ref
          .watch(leadershipServiceProvider)
          .getBoardMembers(
            campusId: params.campusId,
            departmentId: params.departmentId,
          );
    });

// Helper class for parameters
class BoardMembersParams {
  final String campusId;
  final String? departmentId;

  const BoardMembersParams({required this.campusId, this.departmentId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardMembersParams &&
          runtimeType == other.runtimeType &&
          campusId == other.campusId &&
          departmentId == other.departmentId;

  @override
  int get hashCode => campusId.hashCode ^ departmentId.hashCode;
}
