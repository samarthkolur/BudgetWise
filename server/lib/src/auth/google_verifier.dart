import 'dart:convert';

import 'package:http/http.dart' as http;

/// The identity Google asserts about a signed-in user.
class GoogleIdentity {
  const GoogleIdentity({
    required this.subject,
    required this.email,
    this.name,
    this.pictureUrl,
    this.emailVerified = false,
  });

  /// Google's stable user id. The account key — **not** the email, which a user
  /// can change and which can be reassigned within a Workspace domain.
  final String subject;

  final String email;
  final String? name;
  final String? pictureUrl;
  final bool emailVerified;
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => 'GoogleAuthException: $message';
}

/// Verifies Google ID tokens.
///
/// With a hosted auth vendor this is the platform’s job. Here it is ours, and it is the
/// single most security-sensitive function in the codebase: it is the only thing
/// deciding whether a caller is who they claim to be.
///
/// It uses Google's **tokeninfo** endpoint rather than verifying the RS256
/// signature locally against the JWKS. That is a deliberate trade:
///
///   * Correct signature verification means fetching and caching the JWKS,
///     matching `kid`, handling key rotation, and validating `iss`/`aud`/`exp`
///     by hand — several places to get subtly wrong, and a wrong one here is a
///     total authentication bypass rather than a bug.
///   * tokeninfo is Google's own validator, so the cryptography is theirs.
///
/// The cost is one outbound request per sign-in — not per API call, because the
/// client then holds *our* token. If that ever becomes a bottleneck, replace
/// this with local JWKS verification and keep the audience check below intact.
class GoogleVerifier {
  GoogleVerifier({
    required this.allowedAudiences,
    http.Client? httpClient,
    Uri? tokenInfoEndpoint,
  }) : _http = httpClient ?? http.Client(),
       _endpoint =
           tokenInfoEndpoint ??
           Uri.parse('https://oauth2.googleapis.com/tokeninfo');

  /// Client IDs permitted in the token's `aud`.
  ///
  /// **Checking this is not optional.** Any Google account can obtain a valid ID
  /// token for any app; what makes a token ours is that Google minted it for our
  /// client. Skipping the audience check would accept a token issued to an
  /// unrelated application and let its holder sign in as that user here.
  final Set<String> allowedAudiences;

  final http.Client _http;
  final Uri _endpoint;

  static const _issuers = {
    'accounts.google.com',
    'https://accounts.google.com',
  };

  Future<GoogleIdentity> verify(String idToken) async {
    if (idToken.trim().isEmpty) {
      throw const GoogleAuthException('No ID token supplied');
    }

    final http.Response response;
    try {
      response = await _http
          .get(_endpoint.replace(queryParameters: {'id_token': idToken}))
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      throw GoogleAuthException(
        'Could not reach Google to verify sign-in: $error',
      );
    }

    if (response.statusCode != 200) {
      throw const GoogleAuthException('Google rejected the sign-in token');
    }

    final claims = jsonDecode(response.body) as Map<String, dynamic>;

    final audience = claims['aud'] as String?;
    if (audience == null || !allowedAudiences.contains(audience)) {
      throw const GoogleAuthException('That token was not issued for this app');
    }

    final issuer = claims['iss'] as String?;
    if (issuer == null || !_issuers.contains(issuer)) {
      throw const GoogleAuthException('Unexpected token issuer');
    }

    // tokeninfo rejects expired tokens itself, but `exp` is checked again here
    // so a change of endpoint cannot silently remove the expiry check.
    final expiry = int.tryParse('${claims['exp']}');
    if (expiry == null ||
        DateTime.fromMillisecondsSinceEpoch(
          expiry * 1000,
        ).isBefore(DateTime.now())) {
      throw const GoogleAuthException('That sign-in token has expired');
    }

    final subject = claims['sub'] as String?;
    if (subject == null || subject.isEmpty) {
      throw const GoogleAuthException('Token carried no user id');
    }

    return GoogleIdentity(
      subject: subject,
      email: (claims['email'] as String? ?? '').toLowerCase(),
      name: claims['name'] as String?,
      pictureUrl: claims['picture'] as String?,
      emailVerified: '${claims['email_verified']}' == 'true',
    );
  }

  void close() => _http.close();
}
