import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import jwt from 'jsonwebtoken';
import { Harness, Session } from './support/harness';

/**
 * Cross-user isolation. Ported from server/test/isolation_test.dart.
 *
 * **This is the most important suite in the project.** Postgres foreign keys
 * stop an orphaned parent id, but nothing in the schema stops "this budgetId
 * is real but belongs to someone else" — that depends entirely on every
 * repository scoping its queries by userId and calling `assertOwnsBudget` /
 * `assertOwnsGoal` before a cross-parent write. These tests are the only
 * thing standing between two users' data.
 */
describe('isolation', () => {
  let harness: Harness;
  let alice: Session;
  let bob: Session;
  let aliceBudgetId: string;
  let aliceExpenseId: string;
  let aliceGoalId: string;

  beforeAll(async () => {
    harness = await Harness.start();
    await harness.reset();

    alice = await harness.signUp({ email: 'alice@test.local', password: 'password123' });
    bob = await harness.signUp({ email: 'bob@test.local', password: 'password123' });

    // Alice: 50,000 income, 10,000 savings => 40,000 spendable.
    const budget = await alice.post('/v1/budgets', {
      period: '2026-08-01',
      incomeMinor: 5000000,
      savingsMode: 'percent',
      savingsPercent: 20.0,
      savingsTargetMinor: 1000000,
    });
    aliceBudgetId = budget.body.id;

    const expense = await alice.post('/v1/expenses', {
      budgetId: aliceBudgetId,
      amountMinor: 25000,
      spentOn: '2026-08-04',
      note: 'alice lunch',
    });
    aliceExpenseId = expense.body.id;

    const goal = await alice.post('/v1/goals', { title: 'Laptop', targetMinor: 8000000 });
    aliceGoalId = goal.body.id;
  });

  afterAll(async () => {
    await harness.stop();
  });

  describe('reads', () => {
    it("bob sees none of alice's budgets, goals or summaries", async () => {
      expect((await bob.get('/v1/budgets')).body).toEqual([]);
      expect((await bob.get('/v1/goals')).body).toEqual([]);
      expect((await bob.get('/v1/summaries')).body).toEqual([]);

      // And alice still sees her own — a suite that passes because
      // everything is empty proves nothing.
      expect((await alice.get('/v1/budgets')).body).toHaveLength(1);
    });

    it("bob cannot list expenses on alice's budget", async () => {
      const response = await bob.get(`/v1/budgets/${aliceBudgetId}/expenses`);
      expect(response.status).toBe(404);
    });
  });

  describe('writes', () => {
    it("bob cannot attach an expense he owns to alice's budget", async () => {
      const response = await bob.post('/v1/expenses', {
        budgetId: aliceBudgetId,
        amountMinor: 5000,
        spentOn: '2026-08-04',
      });
      expect(response.status).toBe(404);

      // And nothing was written.
      const expenses = await alice.get(`/v1/budgets/${aliceBudgetId}/expenses`);
      expect(expenses.body).toHaveLength(1);
    });

    it("bob cannot contribute to alice's goal", async () => {
      const response = await bob.post(`/v1/goals/${aliceGoalId}/contribute`, { amountMinor: 100000 });
      expect(response.status).toBe(404);
    });

    it("bob cannot update or delete alice's expense", async () => {
      const update = await bob.patch(`/v1/expenses/${aliceExpenseId}`, {
        amountMinor: 1,
        spentOn: '2026-08-04',
      });
      expect(update.status).toBe(404);

      const del = await bob.delete(`/v1/expenses/${aliceExpenseId}`);
      expect(del.status).toBe(404);

      // Alice's expense is untouched.
      const expenses = await alice.get(`/v1/budgets/${aliceBudgetId}/expenses`);
      expect(expenses.body).toHaveLength(1);
      expect(expenses.body[0].amountMinor).toBe(25000);
    });

    it('a forged userId in the request body is ignored', async () => {
      const response = await bob.post('/v1/goals', {
        title: 'Injected',
        targetMinor: 100000,
        userId: alice.userId,
        ownerId: alice.userId,
      });
      expect(response.status).toBe(201);

      const aliceGoals = await alice.get('/v1/goals');
      expect(aliceGoals.body.map((g: { title: string }) => g.title)).not.toContain('Injected');

      const bobGoals = await bob.get('/v1/goals');
      expect(bobGoals.body.map((g: { title: string }) => g.title)).toContain('Injected');
    });
  });

  describe('authentication', () => {
    it('no token is rejected', async () => {
      expect((await harness.get('/v1/budgets')).status).toBe(401);
    });

    it('a garbage token is rejected', async () => {
      expect((await harness.get('/v1/budgets', 'not-a-jwt')).status).toBe(401);
    });

    it('a token signed with the wrong secret is rejected', async () => {
      const forged = jwt.sign({ email: 'alice@test.local' }, 'a-completely-different-secret-of-sufficient-length', {
        subject: alice.userId,
        issuer: 'budgetwise-api',
        expiresIn: '1h',
      });
      const response = await harness.get('/v1/budgets', forged);
      expect(response.status).toBe(401);
    });
  });

  describe('account deletion', () => {
    it('deleting an account leaves nothing behind in any table', async () => {
      const carol = await harness.signUp({ email: 'carol@test.local', password: 'password123' });

      const budget = await carol.post('/v1/budgets', {
        period: '2026-08-01',
        incomeMinor: 1000000,
        savingsMode: 'percent',
        savingsPercent: 10.0,
        savingsTargetMinor: 100000,
      });
      await carol.post('/v1/goals', { title: 'Trip', targetMinor: 500000 });

      expect((await carol.delete('/v1/me')).status).toBe(204);

      const carolId = carol.userId;
      expect(await harness.prisma.user.count({ where: { id: carolId } })).toBe(0);
      expect(await harness.prisma.budget.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.goal.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.expense.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.savingsEntry.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.investment.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.goalContribution.count({ where: { userId: carolId } })).toBe(0);
      expect(await harness.prisma.refreshToken.count({ where: { userId: carolId } })).toBe(0);

      // Alice is untouched.
      expect((await alice.get('/v1/budgets')).body).toHaveLength(1);
      expect(budget.body.id).toBeTruthy();
    });
  });
});
