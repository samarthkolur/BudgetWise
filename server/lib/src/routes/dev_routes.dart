import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/config/env.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/http/errors.dart';
import 'package:budgetwise_server/src/http/middleware.dart';
import 'package:budgetwise_server/src/routes/auth_routes.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Sign-in without Google, for running the whole stack offline.
///
/// **This is a real authentication bypass.** Anyone who can reach the endpoint
/// becomes the named user, with no credential at all. It exists because the
/// alternative — requiring a Google Cloud OAuth client before the app can be
/// run once — makes local development depend on a cloud service that the rest
/// of the stack deliberately does not need.
///
/// Three guards keep it from ever being reachable in production, and they are
/// deliberately belt-and-braces because the cost of one failing silently is
/// total:
///
/// 1. **Off unless `ALLOW_DEV_LOGIN=true`.** Not a default, not a fallback.
/// 2. **Refused when the database is not local.** [Env.isLocalDatabase] rejects
///    `mongodb+srv://` and any host that is not loopback, so pointing a
///    dev-login server at Atlas fails at startup rather than quietly exposing
///    production data. This is the guard that matters: the flag can be set by
///    accident, but the flag *and* a local database together cannot describe a
///    production deployment.
/// 3. **The route is not mounted at all when disabled** — it 404s exactly as if
///    it had never been written, rather than returning a 403 that advertises
///    its existence.
///
/// The session it issues is otherwise completely ordinary: the same signed
/// token, the same owner scoping, the same isolation. It is a way in, not a way
/// around — everything downstream still treats the caller as a normal user.
class DevRoutes {
  DevRoutes({required this.mongo, required this.tokens});

  final Mongo mongo;
  final TokenService tokens;

  Router get router => Router()..post('/login', _login);

  Future<Response> _login(Request request) async {
    final body = await readJson(request);
    final email = (body['email'] as String? ?? 'dev@budgetwise.local')
        .trim()
        .toLowerCase();
    if (email.isEmpty) {
      throw const ApiException.badRequest('An email is required.');
    }

    // Keyed on a synthetic subject so a dev user can never collide with a real
    // Google account, and so switching to real sign-in later does not silently
    // adopt this account.
    final subject = 'dev|$email';
    final users = mongo.collection(Col.users);
    final now = DateTime.now().toUtc();

    await users.updateOne(
      where.eq('googleSub', subject),
      {
        r'$set': {'email': email, 'lastSignInAt': now},
        r'$setOnInsert': {
          'googleSub': subject,
          'displayName': body['displayName'] as String? ?? 'Dev User',
          'avatarUrl': null,
          'currency': 'INR',
          'locale': 'en_IN',
          'onboardingCompletedAt': null,
          'investingUnlockedAt': null,
          'isDevAccount': true,
          'createdAt': now,
        },
      },
      upsert: true,
    );

    final user = await users.findOne(where.eq('googleSub', subject));
    if (user == null) {
      throw const ApiException(
        500,
        'internal',
        'Could not create the account.',
      );
    }

    final pair = await tokens.issue(
      ownerId: user['_id'] as ObjectId,
      email: email,
    );

    return jsonResponse({...pair.toJson(), 'user': publicUser(user)});
  }
}
