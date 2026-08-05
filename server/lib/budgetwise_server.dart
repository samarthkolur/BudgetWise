import 'dart:convert';

import 'package:budgetwise_server/src/auth/google_verifier.dart';
import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/config/env.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/http/errors.dart';
import 'package:budgetwise_server/src/http/middleware.dart';
import 'package:budgetwise_server/src/routes/api_routes.dart';
import 'package:budgetwise_server/src/routes/auth_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

export 'src/auth/google_verifier.dart';
export 'src/auth/tokens.dart';
export 'src/config/env.dart';
export 'src/db/mongo.dart';
export 'src/db/owned_collection.dart';
export 'src/domain_errors.dart';
export 'src/repositories/budget_repository.dart';
export 'src/repositories/expense_repository.dart';
export 'src/repositories/goal_repository.dart';
export 'src/repositories/investing_repository.dart';

/// Assembles the whole application: middleware, auth routes, guarded API.
///
/// Built as a function returning a [Handler] rather than as a running server so
/// the tests can exercise the real pipeline in-process — same middleware, same
/// ordering, same error mapping — without binding a port.
class BudgetWiseApi {
  BudgetWiseApi({
    required this.env,
    required this.mongo,
    GoogleVerifier? verifier,
  }) : verifier =
           verifier ?? GoogleVerifier(allowedAudiences: env.allowedAudiences),
       tokens = TokenService(
         secret: env.jwtSecret,
         accessTtl: env.accessTokenTtl,
         refreshTtl: env.refreshTokenTtl,
         refreshTokens: mongo.collection(Col.refreshTokens),
       );

  final Env env;
  final Mongo mongo;
  final GoogleVerifier verifier;
  final TokenService tokens;

  Handler get handler {
    final root = Router()
      ..get('/health', (Request _) => jsonResponse({'status': 'ok'}))
      // Auth is deliberately outside requireAuth — it is how a session begins.
      ..mount(
        '/v1/auth',
        AuthRoutes(
          mongo: mongo,
          verifier: verifier,
          tokens: tokens,
        ).router.call,
      )
      // Everything else is behind the guard. Mounting the API anywhere outside
      // this pipeline would hand out unscoped repositories.
      ..mount(
        '/v1',
        const Pipeline()
            .addMiddleware(requireAuth(tokens))
            .addHandler(ApiRoutes(mongo: mongo, tokens: tokens).router.call),
      );

    return const Pipeline()
        .addMiddleware(requestId())
        .addMiddleware(cors())
        .addMiddleware(bodyLimit())
        .addMiddleware(errorHandler(onError: _log))
        .addHandler(root.call);
  }

  static void _log(Object error, StackTrace stackTrace) {
    // Structured so a log aggregator can filter on it. The message reaches the
    // logs; the client only ever sees "something went wrong".
    // ignore: avoid_print
    print(
      jsonEncode({
        'level': 'error',
        'error': error.toString(),
        'stack': stackTrace.toString().split('\n').take(5).join(' | '),
      }),
    );
  }
}
