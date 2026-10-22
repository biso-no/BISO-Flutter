/// A `major.minor.patch` app version.
///
/// Only that exact shape parses. Build numbers (`2.4.0+93`), pre-release tags
/// (`2.2.9-beta`) and anything else yield `null`, because a version we cannot
/// read must never be the reason someone is told to update.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  /// Parses [value], or returns `null` if it is not `major.minor.patch`.
  static AppVersion? tryParse(String? value) {
    if (value == null) return null;

    final match = _pattern.firstMatch(value);
    if (match == null) return null;

    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    final patch = int.tryParse(match[3]!);
    if (major == null || minor == null || patch == null) return null;

    return AppVersion._(major, minor, patch);
  }

  /// Segments compare numerically, so 2.10.0 is above 2.9.0.
  @override
  int compareTo(AppVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) return byMajor;

    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) return byMinor;

    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
