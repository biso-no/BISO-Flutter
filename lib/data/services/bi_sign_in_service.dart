import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/constants/app_constants.dart';
import 'api_auth.dart';
import 'appwrite_service.dart' as appwrite;
import 'bi_sync_api_client.dart';

/// Opens [url] in a browser sheet and returns the URL it ends on once that
/// URL has the scheme [callbackUrlScheme].
typedef WebAuthenticate =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
      required bool preferEphemeral,
    });

/// The scheme Appwrite accepts as a redirect for this project's apps.
const biCallbackScheme = 'appwrite-callback-biso';
const biSuccessUrl = '$biCallbackScheme://bi-sign-in/success';
const biFailureUrl = '$biCallbackScheme://bi-sign-in/failure';

/// BI's tenant is reachable only through Appwrite's OIDC provider.
const _biProvider = 'oidc';
const _biScopes = ['openid', 'email', 'profile'];

/// Appwrite's error type when the BI identity's email already belongs to an
/// account it would not merge into.
const _existingAccountErrorType = 'general_bad_request';

/// How a BI sign-in ended.
sealed class BiSignInOutcome {
  const BiSignInOutcome();
}

/// Signed in, with what the server's BI sync answered.
final class BiSignedIn extends BiSignInOutcome {
  const BiSignedIn(this.sync);

  final BiSyncResult sync;
}

/// The student closed the browser sheet.
final class BiSignInCancelled extends BiSignInOutcome {
  const BiSignInCancelled();
}

final class BiSignInFailed extends BiSignInOutcome {
  const BiSignInFailed(this.reason);

  final BiSignInFailure reason;
}

enum BiSignInFailure {
  failed,

  /// BI could not sign into the BISO account that already holds the BI
  /// email; a login link to that email still works.
  existingAccount,
}

/// What the BI sign-in browser came back with.
sealed class BiCallback {
  const BiCallback();
}

final class BiCallbackSuccess extends BiCallback {
  const BiCallbackSuccess({required this.userId, required this.secret});

  final String userId;
  final String secret;
}

final class BiCallbackError extends BiCallback {
  const BiCallbackError(this.reason);

  final BiSignInFailure reason;
}

/// Reads the URL Appwrite redirected the browser to: [biSuccessUrl] with a
/// token's `userId` and `secret`, or [biFailureUrl] with an `error` JSON
/// object (`message`, `type`, `code`).
@visibleForTesting
BiCallback parseBiCallback(Uri uri) {
  const failed = BiCallbackError(BiSignInFailure.failed);
  if (uri.scheme != biCallbackScheme || uri.host != 'bi-sign-in') {
    return failed;
  }
  switch (uri.path) {
    case '/success':
      final userId = uri.queryParameters['userId'] ?? '';
      final secret = uri.queryParameters['secret'] ?? '';
      if (userId.isEmpty || secret.isEmpty) return failed;
      return BiCallbackSuccess(userId: userId, secret: secret);
    case '/failure':
      try {
        final error = jsonDecode(uri.queryParameters['error'] ?? '');
        if (error is Map && error['type'] == _existingAccountErrorType) {
          return const BiCallbackError(BiSignInFailure.existingAccount);
        }
      } on FormatException {
        // Not Appwrite's JSON: an ordinary failure.
      }
      return failed;
    default:
      return failed;
  }
}

Future<String> _flutterWebAuthenticate({
  required String url,
  required String callbackUrlScheme,
  required bool preferEphemeral,
}) => FlutterWebAuth2.authenticate(
  url: url,
  callbackUrlScheme: callbackUrlScheme,
  options: FlutterWebAuth2Options(preferEphemeral: preferEphemeral),
);

/// Signs a student in with their BI account through Appwrite's OIDC
/// provider, then has the server copy their student number.
///
/// The browser is ephemeral and the app's own session is ended first, so a
/// BI identity can never attach to a session left behind in Safari or
/// Chrome, or in the app.
class BiSignInService {
  BiSignInService({
    WebAuthenticate? authenticate,
    Account? account,
    BiSyncApiClient? syncApi,
  }) : _authenticate = authenticate ?? _flutterWebAuthenticate,
       _accountOverride = account,
       _syncApi = syncApi ?? BiSyncApiClient();

  final WebAuthenticate _authenticate;
  final Account? _accountOverride;
  final BiSyncApiClient _syncApi;

  /// Resolved on use, so building the service never builds the global
  /// Appwrite client.
  Account get _account => _accountOverride ?? appwrite.account;

  /// The Appwrite URL that starts a BI sign-in and ends on [biSuccessUrl] or
  /// [biFailureUrl].
  static String get _startUrl {
    final query = [
      'project=${Uri.encodeComponent(AppConstants.appwriteProjectId)}',
      'success=${Uri.encodeComponent(biSuccessUrl)}',
      'failure=${Uri.encodeComponent(biFailureUrl)}',
      for (final scope in _biScopes)
        '${Uri.encodeComponent('scopes[]')}=${Uri.encodeComponent(scope)}',
    ].join('&');
    return '${AppConstants.appwriteEndpoint}/account/tokens/oauth2/'
        '$_biProvider?$query';
  }

  /// Never throws: every way it can end is a [BiSignInOutcome].
  Future<BiSignInOutcome> signIn() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {
      // No session to end.
    }
    clearAppwriteJwtCache();

    final BiCallback callback;
    try {
      final result = await _authenticate(
        url: _startUrl,
        callbackUrlScheme: biCallbackScheme,
        preferEphemeral: true,
      );
      callback = parseBiCallback(Uri.parse(result));
    } on PlatformException catch (e) {
      return e.code == 'CANCELED'
          ? const BiSignInCancelled()
          : const BiSignInFailed(BiSignInFailure.failed);
    } catch (_) {
      return const BiSignInFailed(BiSignInFailure.failed);
    }

    switch (callback) {
      case BiCallbackError(:final reason):
        return BiSignInFailed(reason);
      case BiCallbackSuccess(:final userId, :final secret):
        try {
          await _account.createSession(userId: userId, secret: secret);
        } catch (_) {
          return const BiSignInFailed(BiSignInFailure.failed);
        }
        clearAppwriteJwtCache();
        return BiSignedIn(await _syncApi.sync());
    }
  }

  /// Asks the server to copy the student number again, for a student who is
  /// already signed in (with BI, or not, which [BiSyncError.noBiIdentity]
  /// then says).
  Future<BiSyncResult> syncOnly() => _syncApi.sync();
}
