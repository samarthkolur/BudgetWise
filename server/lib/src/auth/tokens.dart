import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// A verified caller. Everything downstream scopes its queries to [ownerId].
class Principal {
  const Principal({required this.ownerId, required this.email});

  final ObjectId ownerId;
  final String email;
}

class TokenException implements Exception {
  const TokenException(this.message);
  final String message;

  @override
  String toString() => 'TokenException: $message';
}

/// A freshly issued pair.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

/// Issues and verifies the server's own session tokens.
///
/// Short-lived access token, long-lived refresh token:
///
/// * The **access token** is a signed JWT carrying the owner id. It is not
///   stored anywhere — it is verifiable from the signature alone, which is what
///   keeps ordinary requests to a single database round trip for their data and
///   none for auth.
/// * The **refresh token** is opaque random bytes. Only its SHA-256 hash is
///   stored, so a dump of the tokens collection does not let the reader
///   impersonate anyone — the same reason passwords are hashed.
///
/// Refresh tokens rotate on use: redeeming one deletes it and issues another.
/// A stolen refresh token therefore works at most once, and the theft surfaces
/// as the real user being logged out rather than as silent parallel access.
class TokenService {
  TokenService({
    required this.secret,
    required this.accessTtl,
    required this.refreshTtl,
    required DbCollection refreshTokens,
    Random? random,
  }) : _refreshTokens = refreshTokens,
       _random = random ?? Random.secure();

  final String secret;
  final Duration accessTtl;
  final Duration refreshTtl;
  final DbCollection _refreshTokens;
  final Random _random;

  static const _issuer = 'budgetwise-api';

  Future<TokenPair> issue({
    required ObjectId ownerId,
    required String email,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(accessTtl);

    final jwt = JWT(
      {'email': email},
      subject: ownerId.oid,
      issuer: _issuer,
    );
    final accessToken = jwt.sign(
      SecretKey(secret),
      expiresIn: accessTtl,
    );

    final refreshToken = _randomToken();
    await _refreshTokens.insertOne({
      'ownerId': ownerId,
      'tokenHash': _hash(refreshToken),
      'createdAt': now,
      'expiresAt': now.add(refreshTtl),
    });

    return TokenPair(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }

  /// Verifies an access token and returns who it belongs to.
  Principal verifyAccessToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(secret), issuer: _issuer);
      final subject = jwt.subject;
      if (subject == null) {
        throw const TokenException('Token carried no subject');
      }
      return Principal(
        ownerId: ObjectId.fromHexString(subject),
        email: (jwt.payload as Map<String, dynamic>)['email'] as String? ?? '',
      );
    } on JWTExpiredException {
      throw const TokenException('Your session expired. Please sign in again.');
    } on JWTException {
      throw const TokenException('Invalid session token');
    } on FormatException {
      throw const TokenException('Invalid session token');
    }
  }

  /// Exchanges a refresh token for a new pair, rotating it in the process.
  Future<TokenPair> refresh(
    String refreshToken, {
    required String email,
  }) async {
    final record = await _refreshTokens.findOne(
      where.eq('tokenHash', _hash(refreshToken)),
    );
    if (record == null) {
      throw const TokenException('That session is no longer valid');
    }

    final expiresAt = record['expiresAt'] as DateTime?;
    if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
      await _refreshTokens.deleteOne(where.id(record['_id'] as ObjectId));
      throw const TokenException('That session has expired');
    }

    // Rotate: the presented token dies here whether or not the caller was the
    // legitimate holder.
    await _refreshTokens.deleteOne(where.id(record['_id'] as ObjectId));

    return issue(ownerId: record['ownerId'] as ObjectId, email: email);
  }

  /// Signs out one session.
  Future<void> revoke(String refreshToken) async {
    await _refreshTokens.deleteOne(where.eq('tokenHash', _hash(refreshToken)));
  }

  /// Signs out everywhere — used on account deletion.
  Future<void> revokeAllFor(ObjectId ownerId) async {
    await _refreshTokens.deleteMany(where.eq('ownerId', ownerId));
  }

  String _randomToken() {
    final bytes = List<int>.generate(48, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}
