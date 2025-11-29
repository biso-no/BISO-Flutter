import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'appwrite_service.dart';

class OAuthService {
  static final OAuthService _instance = OAuthService._internal();
  factory OAuthService() => _instance;
  OAuthService._internal();

  // Microsoft Azure AD configuration for BI
  static const String _authority =
      'https://login.microsoftonline.com/adee44b2-91fc-40f1-abdd-9cc29351b5fd';
  static const String _clientId = '09d8bb72-2cef-4b98-a1d3-2414a7a40873';
  static const String _scope = 'openid email';
  static const String _redirectUri = 'com.biso.no://oauth/callback';

  /// Generates PKCE code verifier and challenge for secure OAuth
  Map<String, String> _generatePKCE() {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();

    // Generate code verifier (43-128 characters)
    final codeVerifier = List.generate(
      128,
      (i) => charset[random.nextInt(charset.length)],
    ).join();

    // Generate code challenge (base64url-encoded SHA256 hash)
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    final codeChallenge = base64Url.encode(digest.bytes).replaceAll('=', '');

    return {'codeVerifier': codeVerifier, 'codeChallenge': codeChallenge};
  }

  /// Builds the Microsoft OAuth authorization URL
  String _buildAuthUrl(String codeChallenge, String state) {
    final params = {
      'client_id': _clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': _scope,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'response_mode': 'query',
      'prompt': 'select_account',
    };

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return '$_authority/oauth2/v2.0/authorize?$query';
  }

  /// Exchanges authorization code for access token
  Future<String?> _exchangeCodeForToken(
    String code,
    String codeVerifier,
  ) async {
    try {
      final body = {
        'client_id': _clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
      };

      final response = await http.post(
        Uri.parse('$_authority/oauth2/v2.0/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body.entries
            .map(
              (e) =>
                  '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
            )
            .join('&'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['access_token'] as String?;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to exchange code for token: $e');
    }
  }

  /// Fetches user info from Microsoft Graph
  Future<Map<String, dynamic>> _fetchUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/oidc/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to fetch user info: $e');
    }
  }

  /// Initiates the OAuth flow and returns the authorization URL
  Future<OAuthSession> initiateOAuth() async {
    final pkce = _generatePKCE();
    final state = _generateRandomString(32);
    final authUrl = _buildAuthUrl(pkce['codeChallenge']!, state);

    return OAuthSession(
      authUrl: authUrl,
      codeVerifier: pkce['codeVerifier']!,
      state: state,
    );
  }

  /// Processes the OAuth callback and extracts student ID
  Future<StudentIdExtractionResult> processOAuthCallback({
    required String callbackUrl,
    required String expectedState,
    required String codeVerifier,
  }) async {
    try {
      final uri = Uri.parse(callbackUrl);
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];

      // Check for errors
      if (error != null) {
        final errorDescription = uri.queryParameters['error_description'];
        throw Exception('OAuth error: $error - $errorDescription');
      }

      // Validate state parameter
      if (state != expectedState) {
        throw Exception('Invalid state parameter');
      }

      if (code == null) {
        throw Exception('No authorization code received');
      }

      // Exchange code for access token
      final accessToken = await _exchangeCodeForToken(code, codeVerifier);
      if (accessToken == null) {
        throw Exception('Failed to obtain access token');
      }

      // Fetch user info
      final userInfo = await _fetchUserInfo(accessToken);
      final email = userInfo['email'] as String?;

      if (email == null) {
        throw Exception('No email found in user info');
      }

      // Validate BI domain
      if (!email.endsWith('@bi.no') && !email.endsWith('@biso.no')) {
        throw Exception(
          'Please use a valid email address ending with @bi.no or @biso.no',
        );
      }

      // Extract student ID from email
      final studentId = email.replaceAll(RegExp(r'@bi\.no|@biso\.no'), '');

      return StudentIdExtractionResult(
        studentId: studentId,
        email: email,
        userInfo: userInfo,
      );
    } catch (e) {
      throw Exception('Failed to process OAuth callback: $e');
    }
  }

  /// Creates student ID document in Appwrite
  Future<void> createStudentIdDocument(String studentId, String userId) async {
    try {
      // Using global databases instance

      // Create student ID document
      await db.createRow(
        databaseId: 'app',
        tableId: 'student_id',
        rowId: studentId, // Use student ID as document ID
        data: {'student_id': studentId, 'user_id': userId},
      );
    } catch (e) {
      throw Exception('Failed to create student ID document: $e');
    }
  }

  /// Complete OAuth flow: launch browser, handle callback, create document
  Future<StudentIdRegistrationResult> registerStudentId(String userId) async {
    try {
      // Generate OAuth session
      final session = await initiateOAuth();

      // Launch browser for OAuth
      final uri = Uri.parse(session.authUrl);
      if (!await canLaunchUrl(uri)) {
        throw Exception('Cannot launch OAuth URL');
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);

      // Return session info for callback handling
      // Note: In a real implementation, you'd need to handle the callback
      // This could be done through deep links, custom URL schemes, or a web view
      return StudentIdRegistrationResult(
        success: true,
        session: session,
        message: 'OAuth flow initiated. Complete the login in your browser.',
      );
    } catch (e) {
      return StudentIdRegistrationResult(success: false, error: e.toString());
    }
  }

  String _generateRandomString(int length) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (i) => charset[random.nextInt(charset.length)],
    ).join();
  }
}

/// Represents an OAuth session with necessary parameters
class OAuthSession {
  final String authUrl;
  final String codeVerifier;
  final String state;

  const OAuthSession({
    required this.authUrl,
    required this.codeVerifier,
    required this.state,
  });
}

/// Result of student ID extraction from OAuth
class StudentIdExtractionResult {
  final String studentId;
  final String email;
  final Map<String, dynamic> userInfo;

  const StudentIdExtractionResult({
    required this.studentId,
    required this.email,
    required this.userInfo,
  });
}

/// Result of student ID registration process
class StudentIdRegistrationResult {
  final bool success;
  final String? error;
  final String? message;
  final OAuthSession? session;

  const StudentIdRegistrationResult({
    required this.success,
    this.error,
    this.message,
    this.session,
  });
}
