import 'package:budgetwise_server/src/auth/google_verifier.dart';
import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/http/errors.dart';
import 'package:budgetwise_server/src/http/middleware.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Sign-in, refresh, sign-out and account deletion.
///
/// These are the only routes reachable without a session, which is why they are
/// mounted outside the [requireAuth] pipeline and why each one is explicit
/// about what it trusts.
class AuthRoutes {
  AuthRoutes({
    required this.mongo,
    required this.verifier,
    required this.tokens,
  });

  final Mongo mongo;
  final GoogleVerifier verifier;
  final TokenService tokens;

  Router get router {
    final router = Router()
      ..post('/google', _signInWithGoogle)
      ..post('/refresh', _refresh)
      ..post('/sign-out', _signOut);
    return router;
  }

  /// Exchanges a Google ID token for our own session.
  ///
  /// The client proves who it is with a token Google signed; from here on it
  /// carries a token *we* signed. Nothing in the request body is trusted except
  /// the ID token itself — the account is keyed on Google's `sub`, not on any
  /// email or id the caller supplied.
  Future<Response> _signInWithGoogle(Request request) async {
    final body = await readJson(request);
    final idToken = body['idToken'] as String?;
    if (idToken == null || idToken.isEmpty) {
      throw const ApiException.badRequest('No sign-in token supplied.');
    }

    final identity = await verifier.verify(idToken);
    final users = mongo.collection(Col.users);
    final now = DateTime.now().toUtc();

    // Upsert on the Google subject. This is what makes a returning user the
    // same user: their email may change, their subject does not.
    await users.updateOne(
      where.eq('googleSub', identity.subject),
      {
        r'$set': {
          'email': identity.email,
          'displayName': identity.name,
          'avatarUrl': identity.pictureUrl,
          'lastSignInAt': now,
        },
        r'$setOnInsert': {
          'googleSub': identity.subject,
          'currency': 'INR',
          'locale': 'en_IN',
          'onboardingCompletedAt': null,
          'investingUnlockedAt': null,
          'createdAt': now,
        },
      },
      upsert: true,
    );

    final user = await users.findOne(where.eq('googleSub', identity.subject));
    if (user == null) {
      throw const ApiException(
        500,
        'internal',
        'Could not create your account.',
      );
    }

    final pair = await tokens.issue(
      ownerId: user['_id'] as ObjectId,
      email: identity.email,
    );

    return jsonResponse({...pair.toJson(), 'user': _publicUser(user)});
  }

  Future<Response> _refresh(Request request) async {
    final body = await readJson(request);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException.badRequest('No refresh token supplied.');
    }

    // The email on the new token comes from the stored user, never from the
    // request — otherwise a caller could rewrite their own identity on refresh.
    final pair = await tokens.refresh(refreshToken, email: '');
    final user = await mongo
        .collection(Col.users)
        .findOne(where.id(tokens.verifyAccessToken(pair.accessToken).ownerId));

    if (user == null) {
      throw const ApiException.unauthorized('Account not found.');
    }

    final withEmail = await tokens.issue(
      ownerId: user['_id'] as ObjectId,
      email: user['email'] as String? ?? '',
    );
    await tokens.revoke(pair.refreshToken);

    return jsonResponse({...withEmail.toJson(), 'user': _publicUser(user)});
  }

  Future<Response> _signOut(Request request) async {
    final body = await readJson(request);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await tokens.revoke(refreshToken);
    }
    // Always 204: whether the token existed is not the caller's business, and
    // signing out must never fail in a way that strands someone signed in.
    return Response(204);
  }
}

Map<String, dynamic> publicUser(Map<String, dynamic> user) => _publicUser(user);

Map<String, dynamic> _publicUser(Map<String, dynamic> user) => {
  'id': (user['_id'] as ObjectId).oid,
  'email': user['email'],
  'displayName': user['displayName'],
  'avatarUrl': user['avatarUrl'],
  'currency': user['currency'] ?? 'INR',
  'locale': user['locale'] ?? 'en_IN',
  'onboardingCompletedAt': (user['onboardingCompletedAt'] as DateTime?)
      ?.toUtc()
      .toIso8601String(),
  'investingUnlockedAt': (user['investingUnlockedAt'] as DateTime?)
      ?.toUtc()
      .toIso8601String(),
};
