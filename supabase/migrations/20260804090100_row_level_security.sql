-- Row Level Security.
--
-- RLS is the authorization layer for this project. There is no API tier between
-- the Flutter client and Postgres, so a missing policy is not a missing feature
-- — it is the whole boundary.
--
-- `force row level security` is set alongside `enable`, so the table owner is
-- subject to its own policies too. Without it, anything connecting as the owner
-- role silently bypasses every rule below.
--
-- Ownership is compared as `(select auth.uid())` rather than bare `auth.uid()`.
-- The subquery form is evaluated once per statement instead of once per row,
-- which is the difference between an index scan and a per-row function call on
-- a month with a few hundred expenses.

-- ---------------------------------------------------------------------------
-- profiles — a user may read and update their own row, but never insert or
-- delete it. Creation is the on_auth_user_created trigger's job; deletion
-- happens by cascade when the auth user is removed. Leaving those verbs
-- unpoliced means a client cannot orphan or duplicate a profile.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

create policy profiles_select on public.profiles
  for select using ((select auth.uid()) = id);

create policy profiles_update on public.profiles
  for update using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- ---------------------------------------------------------------------------
-- monthly_budgets
-- ---------------------------------------------------------------------------

alter table public.monthly_budgets enable row level security;
alter table public.monthly_budgets force row level security;

create policy monthly_budgets_select on public.monthly_budgets
  for select using ((select auth.uid()) = user_id);

create policy monthly_budgets_insert on public.monthly_budgets
  for insert with check ((select auth.uid()) = user_id);

create policy monthly_budgets_update on public.monthly_budgets
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy monthly_budgets_delete on public.monthly_budgets
  for delete using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Child tables.
--
-- Each policy is the same single comparison as its parent's. That is sound here
-- only because the composite foreign keys in the initial migration make it
-- impossible for a row to name one user's parent while claiming another user as
-- its owner — the FK (budget_id, user_id) -> monthly_budgets (id, user_id)
-- rejects the mismatch before any policy is consulted.
-- ---------------------------------------------------------------------------

alter table public.budget_categories enable row level security;
alter table public.budget_categories force row level security;

create policy budget_categories_select on public.budget_categories
  for select using ((select auth.uid()) = user_id);
create policy budget_categories_insert on public.budget_categories
  for insert with check ((select auth.uid()) = user_id);
create policy budget_categories_update on public.budget_categories
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy budget_categories_delete on public.budget_categories
  for delete using ((select auth.uid()) = user_id);

alter table public.expenses enable row level security;
alter table public.expenses force row level security;

create policy expenses_select on public.expenses
  for select using ((select auth.uid()) = user_id);
create policy expenses_insert on public.expenses
  for insert with check ((select auth.uid()) = user_id);
create policy expenses_update on public.expenses
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy expenses_delete on public.expenses
  for delete using ((select auth.uid()) = user_id);

alter table public.goals enable row level security;
alter table public.goals force row level security;

create policy goals_select on public.goals
  for select using ((select auth.uid()) = user_id);
create policy goals_insert on public.goals
  for insert with check ((select auth.uid()) = user_id);
create policy goals_update on public.goals
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy goals_delete on public.goals
  for delete using ((select auth.uid()) = user_id);

alter table public.savings_entries enable row level security;
alter table public.savings_entries force row level security;

create policy savings_entries_select on public.savings_entries
  for select using ((select auth.uid()) = user_id);
create policy savings_entries_insert on public.savings_entries
  for insert with check ((select auth.uid()) = user_id);
create policy savings_entries_update on public.savings_entries
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy savings_entries_delete on public.savings_entries
  for delete using ((select auth.uid()) = user_id);

alter table public.goal_contributions enable row level security;
alter table public.goal_contributions force row level security;

create policy goal_contributions_select on public.goal_contributions
  for select using ((select auth.uid()) = user_id);
create policy goal_contributions_insert on public.goal_contributions
  for insert with check ((select auth.uid()) = user_id);
create policy goal_contributions_update on public.goal_contributions
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy goal_contributions_delete on public.goal_contributions
  for delete using ((select auth.uid()) = user_id);

alter table public.investments enable row level security;
alter table public.investments force row level security;

-- Investing is gated on behaviour, not on the client's opinion of it. The
-- insert policy calls the same function the UI does, so hiding the module and
-- refusing the write are the same decision made in one place.
create policy investments_select on public.investments
  for select using ((select auth.uid()) = user_id);
create policy investments_insert on public.investments
  for insert with check (
    (select auth.uid()) = user_id
    and public.fn_investing_unlocked((select auth.uid()))
  );
create policy investments_update on public.investments
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy investments_delete on public.investments
  for delete using ((select auth.uid()) = user_id);

alter table public.insights enable row level security;
alter table public.insights force row level security;

create policy insights_select on public.insights
  for select using ((select auth.uid()) = user_id);
create policy insights_insert on public.insights
  for insert with check ((select auth.uid()) = user_id);
-- Update is limited to marking an insight seen; delete is allowed so a user can
-- clear advisory noise.
create policy insights_update on public.insights
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy insights_delete on public.insights
  for delete using ((select auth.uid()) = user_id);

alter table public.notifications_queue enable row level security;
alter table public.notifications_queue force row level security;

create policy notifications_queue_select on public.notifications_queue
  for select using ((select auth.uid()) = user_id);
create policy notifications_queue_insert on public.notifications_queue
  for insert with check ((select auth.uid()) = user_id);
create policy notifications_queue_delete on public.notifications_queue
  for delete using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- health_scores — readable by its owner, writable by nobody.
--
-- The score is the product's judgement of the user's discipline. If the client
-- could write it, it would be a number the user sets about themselves, which is
-- not a score. Rows are created by fn_record_health_score(), a security definer
-- function that computes the value server-side from data the user cannot forge.
-- ---------------------------------------------------------------------------

alter table public.health_scores enable row level security;
alter table public.health_scores force row level security;

create policy health_scores_select on public.health_scores
  for select using ((select auth.uid()) = user_id);
