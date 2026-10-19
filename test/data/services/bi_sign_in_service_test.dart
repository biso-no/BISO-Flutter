import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the session calls a BI sign-in makes, in order, into [log].
class _FakeAccount extends Fake implements Account {
  _FakeAccount(this.log, {this.deleteFails = false, this.createFails = false});

  final List<String> log;
  final bool deleteFails;
  final bool createFails;

  @override
  Future deleteSession({required String sessionId}) async {
    log.add('deleteSession:$sessionId');
    if (deleteFails) throw AppwriteException('no session', 401);
  }

  @override
  Future<models.Session> createSession({
    required String userId,
    required String secret,
  }) async {
    log.add('createSession:$userId:$secret');
    if (createFails) throw AppwriteException('Invalid token', 401);
    return models.Session.fromMap({
      r'$id': 'session-1',
      'userId': userId,
      'current': true,
    });
  }
}

class _FakeSync extends BiSyncApiClient {
  _FakeSync(this.log, this.result);

  final List<String> log;
  final BiSyncResult result;

  @override
  Future<BiSyncResult> sync() async {
    log.add('sync');
    return result;
  }
}

const _synced = BiSyncResult(
  success: true,
  studentId: 's1234567',
  campusHint: 'oslo',
);

const _successUrl =
    'appwrite-callback-biso://bi-sign-in/success?userId=user-1&secret=s3cret';

String _failureUrl(String type) => Uri(
  scheme: 'appwrite-callback-biso',
  host: 'bi-sign-in',
  path: '/failure',
  queryParameters: {
    'error': jsonEncode({'message': 'Nope', 'type': type, 'code': 400}),
  },
).toString();

void main() {
  late List<String> log;
  late String? openedUrl;
  late String? openedScheme;
  late bool? openedEphemeral;

  BiSignInService service({
    required Future<String> Function() browser,
    bool deleteFails = false,
    bool createFails = false,
  }) {
    return BiSignInService(
      authenticate:
          ({
            required String url,
            required String callbackUrlScheme,
            required bool preferEphemeral,
          }) {
            log.add('authenticate');
            openedUrl = url;
            openedScheme = callbackUrlScheme;
            openedEphemeral = preferEphemeral;
            return browser();
          },
      account: _FakeAccount(
        log,
        deleteFails: deleteFails,
        createFails: createFails,
      ),
      syncApi: _FakeSync(log, _synced),
    );
  }

  /// Signs in, recording when the old session is about to end.
  Future<BiSignInOutcome> signIn(BiSignInService service) => service.signIn(
    beforeSessionSwitch: () async => log.add('beforeSessionSwitch'),
  );

  setUp(() {
    log = [];
    openedUrl = null;
    openedScheme = null;
    openedEphemeral = null;
  });

  test('startBiSignIn uses an ephemeral browser and keeps the current session '
      'until BI answers', () async {
    await signIn(
      service(
        browser: () async =>
            throw PlatformException(code: 'CANCELED', message: 'User canceled'),
      ),
    );

    expect(log, ['authenticate']);
    expect(openedEphemeral, isTrue);
    expect(openedScheme, 'appwrite-callback-biso');

    final url = Uri.parse(openedUrl!);
    expect(url.origin, 'https://appwrite.biso.no');
    expect(url.path, '/v1/account/tokens/oauth2/oidc');
    expect(url.queryParameters['project'], 'biso');
    expect(
      url.queryParameters['success'],
      'appwrite-callback-biso://bi-sign-in/success',
    );
    expect(
      url.queryParameters['failure'],
      'appwrite-callback-biso://bi-sign-in/failure',
    );
    expect(url.queryParametersAll['scopes[]'], ['openid', 'email', 'profile']);
  });

  test('ends the current session only after the callback, then creates the '
      'session from its credentials and syncs', () async {
    final outcome = await signIn(
      service(
        browser: () async => _successUrl,
        // A student with no session to end still signs in.
        deleteFails: true,
      ),
    );

    expect(log, [
      'authenticate',
      'beforeSessionSwitch',
      'deleteSession:current',
      'createSession:user-1:s3cret',
      'sync',
    ]);
    expect(outcome, isA<BiSignedIn>());
    expect((outcome as BiSignedIn).sync.studentId, 's1234567');
  });

  test('a cancelled BI sign-in is silent', () async {
    final outcome = await signIn(
      service(
        browser: () async =>
            throw PlatformException(code: 'CANCELED', message: 'User canceled'),
      ),
    );

    expect(outcome, isA<BiSignInCancelled>());
    // Nothing touched the session the student already had.
    expect(log, ['authenticate']);
  });

  test('general_bad_request is existingAccount', () async {
    final outcome = await signIn(
      service(browser: () async => _failureUrl('general_bad_request')),
    );

    expect(
      outcome,
      isA<BiSignInFailed>().having(
        (f) => f.reason,
        'reason',
        BiSignInFailure.existingAccount,
      ),
    );
    expect(log, ['authenticate']);
  });

  test('any other failure is failed', () async {
    final failures = <String, Future<String> Function()>{
      'another Appwrite error': () async => _failureUrl('user_oauth_failed'),
      'an error that is not JSON': () async =>
          'appwrite-callback-biso://bi-sign-in/failure?error=oops',
      'a success without a secret': () async =>
          'appwrite-callback-biso://bi-sign-in/success?userId=user-1',
      'a browser that broke': () async =>
          throw PlatformException(code: 'EUNKNOWN'),
    };
    for (final MapEntry(key: name, value: browser) in failures.entries) {
      log = [];
      final outcome = await signIn(service(browser: browser));

      expect(
        outcome,
        isA<BiSignInFailed>().having(
          (f) => f.reason,
          'reason',
          BiSignInFailure.failed,
        ),
        reason: name,
      );
      expect(log, ['authenticate'], reason: name);
    }
  });

  test('a session that cannot be created after the switch is failed', () async {
    final outcome = await signIn(
      service(browser: () async => _successUrl, createFails: true),
    );

    expect(
      outcome,
      isA<BiSignInFailed>().having(
        (f) => f.reason,
        'reason',
        BiSignInFailure.failed,
      ),
    );
    expect(log, [
      'authenticate',
      'beforeSessionSwitch',
      'deleteSession:current',
      'createSession:user-1:s3cret',
    ]);
  });

  test('syncOnly asks the server without opening a browser', () async {
    final result = await service(
      browser: () async => fail('no browser expected'),
    ).syncOnly();

    expect(result.success, isTrue);
    expect(log, ['sync']);
  });

  group('parseBiCallback', () {
    test('reads the credentials from the success URL', () {
      final callback = parseBiCallback(
        Uri.parse(
          'appwrite-callback-biso://bi-sign-in/success?userId=u1&secret=s1',
        ),
      );

      expect(
        callback,
        isA<BiCallbackSuccess>()
            .having((c) => c.userId, 'userId', 'u1')
            .having((c) => c.secret, 'secret', 's1'),
      );
    });

    test('an unknown URL is a failure', () {
      expect(
        parseBiCallback(Uri.parse('https://biso.no/?userId=u1&secret=s1')),
        isA<BiCallbackError>().having(
          (c) => c.reason,
          'reason',
          BiSignInFailure.failed,
        ),
      );
    });
  });
}
