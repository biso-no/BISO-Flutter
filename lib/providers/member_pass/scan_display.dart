import 'package:equatable/equatable.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';

enum ScanTone { green, orange, amber, red, grey }

enum ScanMessage {
  valid,
  duplicate,
  checkId,
  badCode,
  stale,
  expired,
  notMember,
  notLinked,
  notValid,
  unavailable,
  rateLimited,
}

enum ScannerCloseReason { noAccess, signedOut }

/// What the scanner screen shows.
sealed class ScannerDisplay extends Equatable {
  const ScannerDisplay();

  @override
  List<Object?> get props => [];
}

class ScannerIdle extends ScannerDisplay {
  const ScannerIdle();
}

class ScannerChecking extends ScannerDisplay {
  const ScannerChecking();
}

class ScannerResult extends ScannerDisplay {
  const ScannerResult({
    required this.tone,
    required this.message,
    this.name,
    this.membershipName,
    this.expiryDate,
    this.secondsSincePrevious,
  });

  final ScanTone tone;
  final ScanMessage message;
  final String? name;
  final String? membershipName;
  final DateTime? expiryDate;
  final int? secondsSincePrevious;

  @override
  List<Object?> get props => [
    tone,
    message,
    name,
    membershipName,
    expiryDate,
    secondsSincePrevious,
  ];
}

/// The scanner must close: the grant is gone or the session ended.
class ScannerClosed extends ScannerDisplay {
  const ScannerClosed(this.reason);

  final ScannerCloseReason reason;

  @override
  List<Object?> get props => [reason];
}

/// The API refuses longer bodies, so longer reads are not BISO passes.
const maxScanCodeLength = 256;

const overlongCodeResult = ScannerResult(
  tone: ScanTone.red,
  message: ScanMessage.badCode,
);

const _unavailable = ScannerResult(
  tone: ScanTone.grey,
  message: ScanMessage.unavailable,
);

ScannerResult mapScanOutcome(ScanOutcome outcome) => switch (outcome.result) {
  ScanResult.valid => ScannerResult(
    tone: ScanTone.green,
    message: ScanMessage.valid,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
  ),
  ScanResult.duplicate => ScannerResult(
    tone: ScanTone.orange,
    message: ScanMessage.duplicate,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
    secondsSincePrevious: outcome.secondsSincePrevious,
  ),
  ScanResult.checkId => ScannerResult(
    tone: ScanTone.amber,
    message: ScanMessage.checkId,
    name: outcome.name,
    membershipName: outcome.membershipName,
    expiryDate: outcome.expiryDate,
  ),
  ScanResult.denied => ScannerResult(
    tone: ScanTone.red,
    message: switch (outcome.reason) {
      DenyReason.badCode => ScanMessage.badCode,
      DenyReason.stale => ScanMessage.stale,
      DenyReason.expired => ScanMessage.expired,
      DenyReason.notMember => ScanMessage.notMember,
      DenyReason.notLinked => ScanMessage.notLinked,
      DenyReason.other || null => ScanMessage.notValid,
    },
  ),
  ScanResult.unavailable => _unavailable,
};

ScannerDisplay mapScanError(Object error) {
  if (error is MemberPassApiException) {
    if (error.isUnauthorized) {
      return const ScannerClosed(ScannerCloseReason.signedOut);
    }
    if (error.isForbidden) {
      return const ScannerClosed(ScannerCloseReason.noAccess);
    }
    if (error.isRateLimited) {
      return const ScannerResult(
        tone: ScanTone.grey,
        message: ScanMessage.rateLimited,
      );
    }
    // The body was refused, so what the camera read was not a pass.
    if (error.isBadRequest) return overlongCodeResult;
  }
  return _unavailable;
}
