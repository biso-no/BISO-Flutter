import 'package:equatable/equatable.dart';

/// The app versions BISO asks of one platform, as `GET /api/config` reports
/// them: a `minimum` the app must meet and a `recommended` one it should.
///
/// Both are raw server strings — parsing and comparing them is not this
/// class's job. A missing value means that check is off, and anything the
/// server sent that we cannot read is treated the same way: failing open is
/// the only safe answer when the alternative is locking someone out.
class UpdatePolicy extends Equatable {
  const UpdatePolicy({this.minimum, this.recommended});

  /// No policy: neither check is on.
  static const none = UpdatePolicy();

  final String? minimum;
  final String? recommended;

  factory UpdatePolicy.fromJson(Object? json) {
    if (json is! Map) return none;

    final minimum = json['minimum'];
    final recommended = json['recommended'];
    return UpdatePolicy(
      minimum: minimum is String ? minimum : null,
      recommended: recommended is String ? recommended : null,
    );
  }

  @override
  List<Object?> get props => [minimum, recommended];
}
