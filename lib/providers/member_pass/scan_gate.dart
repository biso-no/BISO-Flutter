/// The member a pass code belongs to, so one person holding their pass up
/// is one scan. Mirrors the web `scan-repeat.ts`.
///
/// The raw string is trimmed first. `v1.<id>.<slot>.<sig>` and
/// `a1.<id>.<date>.<sig>` drop the last two parts; `g1.<id>.<totp>` drops the
/// last one; either way the key is `member:` plus the id, which may itself
/// contain dots. When the prefix isn't recognised, or the computed id is
/// empty, the key is the whole trimmed string.
String memberKey(String code) {
  final trimmed = code.trim();
  final parts = trimmed.split('.');
  final id = switch (parts.first) {
    'v1' ||
    'a1' when parts.length >= 4 => parts.sublist(1, parts.length - 2).join('.'),
    'g1' when parts.length >= 3 => parts.sublist(1, parts.length - 1).join('.'),
    _ => null,
  };
  if (id == null || id.isEmpty) return trimmed;
  return 'member:$id';
}

/// Decides which camera reads become scans.
///
/// A member is ignored for [window] after they were last seen, and every
/// read restarts that window. While a scan is busy (in flight or its result
/// on screen) nothing is admitted, and only members already being tracked
/// are refreshed: a stranger glimpsed meanwhile can be scanned straight after.
class ScanGate {
  ScanGate({this.window = const Duration(seconds: 20)});

  final Duration window;
  final Map<String, int> _lastSeen = {};
  bool _busy = false;

  bool get busy => _busy;

  bool admit(String code, int nowMs) {
    _lastSeen.removeWhere(
      (_, seenAt) => nowMs - seenAt >= window.inMilliseconds,
    );
    final key = memberKey(code);
    final recent = _lastSeen.containsKey(key);
    if (_busy) {
      if (recent) _lastSeen[key] = nowMs;
      return false;
    }
    _lastSeen[key] = nowMs;
    if (recent) return false;
    _busy = true;
    return true;
  }

  void finish() => _busy = false;
}
