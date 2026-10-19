import 'dart:io';

import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sign-in link's `secret` (and a typed OTP code) signs whoever holds it
/// in. Debug logs end up in shared bug reports, so they never carry one.
void main() {
  test('a logged link keeps its path and drops the query', () {
    expect(
      linkForLog(
        Uri.parse('https://biso.no/auth/verify?userId=u1&secret=s3cr3t#top'),
      ),
      'https://biso.no/auth/verify',
    );
    expect(
      linkForLog(Uri.parse('biso://auth/verify?userId=u1&secret=s3cr3t')),
      'biso://auth/verify',
    );
    expect(
      linkForLog('/auth/verify-magic-link?userId=u1&secret=s3cr3t'),
      '/auth/verify-magic-link',
    );
    expect(linkForLog(Uri.parse('biso://event?id=e1')), 'biso://event');
  });

  test('no log line in lib/ prints a sign-in secret or OTP code', () {
    final secret = RegExp(r'\$\{?(secret|_otpCode)\b');
    final problems = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.contains('/generated/')) continue;
      problems.addAll(_loggedMatches(file, secret));
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('deep links are logged without their query', () {
    // A whole link or its query; its path, host and scheme are fine, and so
    // are the query's keys.
    final wholeLink = RegExp(
      r'\$\{?(uri|initialUri|queryParams|location)\b'
      r'(?!\.(path|host|scheme|keys)\b)',
    );
    final problems = _loggedMatches(
      File('lib/data/services/deep_link_service.dart'),
      wholeLink,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

/// The lines of [file] inside a `logPrint(` call (whose message may start a
/// line or two below it) that match [pattern].
List<String> _loggedMatches(File file, RegExp pattern) {
  final lines = file.readAsLinesSync();
  return [
    for (var i = 0; i < lines.length; i++)
      if (lines
              .sublist(i < 2 ? 0 : i - 2, i + 1)
              .any((line) => line.contains('logPrint(')) &&
          pattern.hasMatch(lines[i]))
        '${file.path}:${i + 1}: ${lines[i].trim()}',
  ];
}
