import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Harness } from './support/harness';

describe('auth', () => {
  let harness: Harness;

  beforeAll(async () => {
    harness = await Harness.start();
  });

  afterAll(async () => {
    await harness.stop();
  });

  beforeEach(async () => {
    await harness.reset();
  });

  it('signup succeeds and returns a usable token', async () => {
    const signup = await harness.post('/v1/auth/signup', {
      email: 'new@test.local',
      password: 'correct-horse',
      displayName: 'New User',
    });
    expect(signup.status).toBe(201);
    expect(signup.body.accessToken).toBeTypeOf('string');
    expect(signup.body.refreshToken).toBeTypeOf('string');
    expect(signup.body.user.email).toBe('new@test.local');
    expect(signup.body.user.passwordHash).toBeUndefined();

    const me = await harness.get('/v1/me', signup.body.accessToken);
    expect(me.status).toBe(200);
    expect(me.body.email).toBe('new@test.local');
  });

  it('rejects a password shorter than 8 characters', async () => {
    const signup = await harness.post('/v1/auth/signup', {
      email: 'short@test.local',
      password: 'short',
    });
    expect(signup.status).toBe(400);
  });

  it('duplicate-email signup is rejected 409', async () => {
    await harness.post('/v1/auth/signup', { email: 'dupe@test.local', password: 'password123' });
    const second = await harness.post('/v1/auth/signup', {
      email: 'dupe@test.local',
      password: 'password123',
    });
    expect(second.status).toBe(409);
  });

  it('login with wrong password is rejected with a generic message', async () => {
    await harness.post('/v1/auth/signup', { email: 'victim@test.local', password: 'password123' });
    const attempt = await harness.post('/v1/auth/login', {
      email: 'victim@test.local',
      password: 'wrong-password',
    });
    expect(attempt.status).toBe(401);
    expect(attempt.body.message).toBe('Incorrect email or password.');
  });

  it('login with unknown email gets the same generic message', async () => {
    const attempt = await harness.post('/v1/auth/login', {
      email: 'nobody@test.local',
      password: 'whatever123',
    });
    expect(attempt.status).toBe(401);
    expect(attempt.body.message).toBe('Incorrect email or password.');
  });

  it('refresh rotates the token — the old refresh token fails the second time', async () => {
    const signup = await harness.post('/v1/auth/signup', {
      email: 'rotator@test.local',
      password: 'password123',
    });
    const oldRefreshToken = signup.body.refreshToken;

    const first = await harness.post('/v1/auth/refresh', { refreshToken: oldRefreshToken });
    expect(first.status).toBe(200);
    expect(first.body.refreshToken).not.toBe(oldRefreshToken);

    const second = await harness.post('/v1/auth/refresh', { refreshToken: oldRefreshToken });
    expect(second.status).toBe(401);

    // The new token from the first refresh still works.
    const me = await harness.get('/v1/me', first.body.accessToken);
    expect(me.status).toBe(200);
  });

  it('sign-out always returns 204, even for a bogus token', async () => {
    const response = await harness.post('/v1/auth/sign-out', { refreshToken: 'not-a-real-token' });
    expect(response.status).toBe(204);

    const noBody = await harness.post('/v1/auth/sign-out', {});
    expect(noBody.status).toBe(204);
  });

  it('GET /health reports ok', async () => {
    const response = await harness.get('/health');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: 'ok' });
  });
});
