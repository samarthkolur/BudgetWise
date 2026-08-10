import 'package:budgetwise_server/budgetwise_server.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Dev login is a real authentication bypass, so its guards are tested rather
/// than trusted. Each case here is the difference between "runs offline" and
/// "hands out sessions to anyone who can reach the port".
void main() {
  group('the local-database guard', () {
    Env build(Map<String, String> overrides) => Env.fromPlatform({
      'MONGO_URI': 'mongodb://localhost:27017',
      'JWT_SECRET': 'a-secret-that-is-long-enough-to-be-accepted-000',
      ...overrides,
    });

    test('refuses dev login against Atlas', () {
      expect(
        () => build({
          'ALLOW_DEV_LOGIN': 'true',
          'MONGO_URI': 'mongodb+srv://user:pw@cluster0.abc.mongodb.net',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('refuses dev login against any remote host', () {
      expect(
        () => build({
          'ALLOW_DEV_LOGIN': 'true',
          'MONGO_URI': 'mongodb://db.production.internal:27017',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('allows it against loopback', () {
      final env = build({'ALLOW_DEV_LOGIN': 'true'});
      expect(env.allowDevLogin, isTrue);
    });

    test('is off unless explicitly enabled', () {
      // Absent, empty, and anything that is not exactly "true".
      for (final value in ['', 'false', '1', 'yes', 'TRUE ']) {
        final env = build({
          'ALLOW_DEV_LOGIN': value,
          'GOOGLE_WEB_CLIENT_ID': 'x.apps.googleusercontent.com',
        });
        expect(env.allowDevLogin, isFalse, reason: 'value "$value" enabled it');
      }
    });

    test('accepts "TRUE" case-insensitively', () {
      expect(build({'ALLOW_DEV_LOGIN': 'TRUE'}).allowDevLogin, isTrue);
    });

    /// Google config stops being mandatory only because dev login replaces it.
    /// Without this, running offline would still demand a cloud OAuth client.
    test(
      'Google client id is required without dev login, optional with it',
      () {
        expect(
          () => build({'ALLOW_DEV_LOGIN': 'false'}),
          throwsA(isA<ConfigException>()),
        );
        expect(build({'ALLOW_DEV_LOGIN': 'true'}).googleWebClientId, isEmpty);
      },
    );
  });

  group('the route', () {
    test(
      '404s when disabled, and issues a working session when enabled',
      () async {
        final harness = await Harness.start();
        addTearDown(harness.stop);

        // The default harness has dev login off.
        final disabled = await harness.post('/v1/auth/dev/login', {
          'email': 'dev@budgetwise.local',
        });
        // 401, not 404: with the route unmounted the request falls through to
        // the authenticated /v1 pipeline, which rejects it before routing.
        // That is the desired property — the response is identical to any other
        // unknown /v1 path, so it does not reveal that a dev login exists. It
        // is emphatically not 200.
        expect(disabled.statusCode, 401);

        final enabled = await Harness.start(allowDevLogin: true);
        addTearDown(enabled.stop);

        final response = await enabled.post('/v1/auth/dev/login', {
          'email': 'dev@budgetwise.local',
        });
        expect(response.statusCode, 200);

        final body = await jsonBody<Map<String, dynamic>>(response);
        final token = body['accessToken'] as String;

        // The session it hands out is completely ordinary — same signing, same
        // scoping. It is a way in, not a way around.
        final me = await enabled.get('/v1/me', token: token);
        expect(me.statusCode, 200);
      },
    );

    test('the same email returns the same account', () async {
      final harness = await Harness.start(allowDevLogin: true);
      addTearDown(harness.stop);

      Future<String> signIn() async {
        final body = await jsonBody<Map<String, dynamic>>(
          await harness.post('/v1/auth/dev/login', {'email': 'a@local'}),
        );
        return (body['user'] as Map<String, dynamic>)['id'] as String;
      }

      expect(await signIn(), await signIn());
    });

    test('different emails are different users, and stay isolated', () async {
      final harness = await Harness.start(allowDevLogin: true);
      addTearDown(harness.stop);

      Future<Session> signIn(String email) async {
        final body = await jsonBody<Map<String, dynamic>>(
          await harness.post('/v1/auth/dev/login', {'email': email}),
        );
        return Session(
          accessToken: body['accessToken'] as String,
          refreshToken: body['refreshToken'] as String,
          userId: (body['user'] as Map<String, dynamic>)['id'] as String,
          harness: harness,
        );
      }

      final one = await signIn('one@local');
      final two = await signIn('two@local');
      expect(one.userId, isNot(two.userId));

      await one.post('/v1/goals', {'title': 'Mine', 'targetMinor': 100000});

      // Dev accounts get no special treatment: the same ownership scoping
      // applies, so one cannot see the other's data.
      expect(
        await jsonBody<List<dynamic>>(await two.get('/v1/goals')),
        isEmpty,
      );
      expect(
        await jsonBody<List<dynamic>>(await one.get('/v1/goals')),
        hasLength(1),
      );
    });
  });
}
