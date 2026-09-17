/// The member a pass code belongs to, so one person holding their pass up
/// is one scan. Mirrors the web `scan-repeat.ts`.
///
/// `v1.<id>.<slot>.<sig>` and `a1.<id>.<date>.<sig>` drop the last two parts;
/// `g1.<id>.<totp>` drops the last one. Ids may contain dots. Anything else
/// is its own key.
String memberKey(String code) {
  final parts = code.split('.');
  switch (parts.first) {
    case 'v1' || 'a1' when parts.length >= 4:
      return parts.sublist(1, parts.length - 2).join('.');
    case 'g1' when parts.length >= 3:
      return parts.sublist(1, parts.length - 1).join('.');
  }
  return code;
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
