-- BudgetWise initial schema.
--
-- Conventions enforced throughout:
--   * Money is bigint in MINOR UNITS (paise). Never numeric, never float.
--     A budget is a sum of parts that must equal a whole; floating point
--     cannot promise that, and `numeric` invites a rounding policy per query.
--   * A month is `period date`, normalised to the first of the month by a
--     check constraint. Not a string, not YYYY-MM, not a year/month pair.
--   * Ownership is denormalised onto every user table so each RLS policy is
--     the single comparison `user_id = (select auth.uid())`, and is pinned by
--     COMPOSITE FOREIGN KEYS: every parent carries `unique (id, user_id)` and
--     every child references `(parent_id, user_id)`. A denormalised user_id on
--     its own would let a caller attach a row to someone else's budget while
--     honestly claiming to own the row itself. The composite key makes that
--     unrepresentable rather than merely policed.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                      uuid primary key references auth.users (id) on delete cascade,
  display_name            text,
  avatar_url              text,
  currency                text        not null default 'INR',
  locale                  text        not null default 'en_IN',
  onboarding_completed_at timestamptz,
  investing_unlocked_at   timestamptz,
  notification_prefs      jsonb       not null default '{}'::jsonb,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Created by trigger rather than by the client after first sign-in, so the app
-- never has to race an insert against its own first read.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- monthly_budgets
-- ---------------------------------------------------------------------------

create table public.monthly_budgets (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid        not null references auth.users (id) on delete cascade,
  period                  date        not null,
  income_minor            bigint      not null default 0 check (income_minor >= 0),
  savings_mode            text        not null default 'percent' check (savings_mode in ('fixed', 'percent')),
  savings_percent         numeric(5,2) check (savings_percent is null or (savings_percent >= 0 and savings_percent <= 100)),
  savings_target_minor    bigint      not null default 0 check (savings_target_minor >= 0),
  -- Null until investing is unlocked. Zero would claim a target of nothing was
  -- set, which is a different statement from "this user has no investing yet".
  investment_target_minor bigint      check (investment_target_minor is null or investment_target_minor >= 0),
  -- Drives the PRD's savings reminder card: pending until the user confirms
  -- the transfer, then a success indicator. No bank integration involved; the
  -- point is the habit of consciously moving the money first.
  savings_confirmed_at    timestamptz,
  status                  text        not null default 'active' check (status in ('draft', 'active', 'archived')),
  carried_from_period     date,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint monthly_budgets_period_is_month_start check (period = date_trunc('month', period)::date),
  constraint monthly_budgets_carried_is_month_start check (
    carried_from_period is null or carried_from_period = date_trunc('month', carried_from_period)::date
  ),
  constraint monthly_budgets_savings_within_income check (savings_target_minor <= income_minor),
  constraint monthly_budgets_one_per_month unique (user_id, period),
  -- Referenced by children as (budget_id, user_id).
  constraint monthly_budgets_id_user unique (id, user_id)
);

create index monthly_budgets_user_period_idx on public.monthly_budgets (user_id, period desc);

create trigger monthly_budgets_set_updated_at
  before update on public.monthly_budgets
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- budget_categories
-- ---------------------------------------------------------------------------

create table public.budget_categories (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users (id) on delete cascade,
  budget_id         uuid        not null,
  -- One of the nine defaults, or 'custom:<slug>'. Text rather than an enum so a
  -- user-defined category does not require a migration to exist.
  category_key      text        not null,
  display_name      text        not null,
  icon              text,
  allocated_minor   bigint      not null default 0 check (allocated_minor >= 0),
  allocated_percent numeric(5,2) not null default 0 check (allocated_percent >= 0 and allocated_percent <= 100),
  sort_order        int         not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint budget_categories_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade,
  constraint budget_categories_one_per_budget unique (budget_id, category_key),
  constraint budget_categories_id_user unique (id, user_id)
);

create index budget_categories_budget_idx on public.budget_categories (budget_id, sort_order);

create trigger budget_categories_set_updated_at
  before update on public.budget_categories
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- expenses
-- ---------------------------------------------------------------------------

create table public.expenses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid        not null references auth.users (id) on delete cascade,
  budget_id      uuid        not null,
  category_id    uuid        not null,
  amount_minor   bigint      not null check (amount_minor > 0),
  spent_on       date        not null default current_date,
  note           text,
  payment_method text        not null default 'upi'
                   check (payment_method in ('cash', 'upi', 'card', 'netbanking', 'other')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint expenses_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade,
  constraint expenses_category_fk
    foreign key (category_id, user_id)
    references public.budget_categories (id, user_id)
    on delete cascade
);

create index expenses_user_date_idx on public.expenses (user_id, spent_on desc);
create index expenses_category_idx on public.expenses (category_id);
create index expenses_budget_idx on public.expenses (budget_id);

create trigger expenses_set_updated_at
  before update on public.expenses
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- goals
-- ---------------------------------------------------------------------------

create table public.goals (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid        not null references auth.users (id) on delete cascade,
  title                     text        not null,
  icon                      text,
  target_minor              bigint      not null check (target_minor > 0),
  -- Maintained by trigger from goal_contributions. Denormalised because every
  -- goal card shows it and recomputing per render is a join the UI does not
  -- need; the trigger is what keeps it honest.
  saved_minor               bigint      not null default 0 check (saved_minor >= 0),
  target_date               date,
  monthly_contribution_minor bigint     check (monthly_contribution_minor is null or monthly_contribution_minor >= 0),
  status                    text        not null default 'active' check (status in ('active', 'achieved', 'abandoned')),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint goals_id_user unique (id, user_id)
);

create index goals_user_status_idx on public.goals (user_id, status);

create trigger goals_set_updated_at
  before update on public.goals
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- savings_entries
-- ---------------------------------------------------------------------------

create table public.savings_entries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users (id) on delete cascade,
  budget_id    uuid        not null,
  goal_id      uuid,
  amount_minor bigint      not null check (amount_minor > 0),
  saved_on     date        not null default current_date,
  destination  text        not null default 'bank'
                 check (destination in ('bank', 'fd', 'rd', 'cash', 'other')),
  note         text,
  created_at   timestamptz not null default now(),

  constraint savings_entries_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade,
  constraint savings_entries_goal_fk
    foreign key (goal_id, user_id)
    references public.goals (id, user_id)
    on delete set null
);

create index savings_entries_budget_idx on public.savings_entries (budget_id);
create index savings_entries_user_date_idx on public.savings_entries (user_id, saved_on desc);

-- ---------------------------------------------------------------------------
-- goal_contributions
-- ---------------------------------------------------------------------------

create table public.goal_contributions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid        not null references auth.users (id) on delete cascade,
  goal_id        uuid        not null,
  budget_id      uuid,
  amount_minor   bigint      not null check (amount_minor > 0),
  contributed_on date        not null default current_date,
  created_at     timestamptz not null default now(),

  constraint goal_contributions_goal_fk
    foreign key (goal_id, user_id)
    references public.goals (id, user_id)
    on delete cascade,
  constraint goal_contributions_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete set null
);

create index goal_contributions_goal_idx on public.goal_contributions (goal_id);

-- Keeps goals.saved_minor in step with its contributions. Recomputed as a sum
-- rather than incremented, so an edit or a delete cannot drift the total.
create or replace function public.sync_goal_saved()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_goal uuid := coalesce(new.goal_id, old.goal_id);
begin
  update public.goals g
     set saved_minor = coalesce((
           select sum(c.amount_minor)
             from public.goal_contributions c
            where c.goal_id = target_goal
         ), 0),
         status = case
           when g.status = 'abandoned' then 'abandoned'
           when coalesce((
             select sum(c.amount_minor)
               from public.goal_contributions c
              where c.goal_id = target_goal
           ), 0) >= g.target_minor then 'achieved'
           else 'active'
         end
   where g.id = target_goal;
  return null;
end;
$$;

create trigger goal_contributions_sync
  after insert or update or delete on public.goal_contributions
  for each row execute function public.sync_goal_saved();

-- ---------------------------------------------------------------------------
-- investments
-- ---------------------------------------------------------------------------

create table public.investments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users (id) on delete cascade,
  budget_id    uuid        not null,
  amount_minor bigint      not null check (amount_minor > 0),
  instrument   text        not null default 'other'
                 check (instrument in ('mutual_fund', 'stocks', 'ppf', 'nps', 'gold', 'fd', 'other')),
  invested_on  date        not null default current_date,
  note         text,
  created_at   timestamptz not null default now(),

  constraint investments_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade
);

create index investments_budget_idx on public.investments (budget_id);

-- ---------------------------------------------------------------------------
-- health_scores
-- ---------------------------------------------------------------------------

-- A snapshot, deliberately. The score is a pure function of a month's
-- behaviour, but a past month's grade must not silently change because the
-- weighting was tuned later.
create table public.health_scores (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users (id) on delete cascade,
  budget_id   uuid        not null,
  score       int         not null check (score between 0 and 100),
  components  jsonb       not null default '[]'::jsonb,
  computed_at timestamptz not null default now(),

  constraint health_scores_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade,
  constraint health_scores_one_per_budget unique (budget_id)
);

-- ---------------------------------------------------------------------------
-- insights
-- ---------------------------------------------------------------------------

create table public.insights (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users (id) on delete cascade,
  budget_id   uuid        not null,
  kind        text        not null,
  severity    text        not null default 'info' check (severity in ('info', 'warning', 'celebration')),
  title       text        not null,
  body        text        not null,
  payload     jsonb       not null default '{}'::jsonb,
  seen_at     timestamptz,
  valid_until timestamptz,
  created_at  timestamptz not null default now(),

  constraint insights_budget_fk
    foreign key (budget_id, user_id)
    references public.monthly_budgets (id, user_id)
    on delete cascade
);

create index insights_budget_idx on public.insights (budget_id, created_at desc);

-- ---------------------------------------------------------------------------
-- notifications_queue
-- ---------------------------------------------------------------------------

create table public.notifications_queue (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid        not null references auth.users (id) on delete cascade,
  kind          text        not null,
  scheduled_for timestamptz not null,
  payload       jsonb       not null default '{}'::jsonb,
  sent_at       timestamptz,
  created_at    timestamptz not null default now()
);

create index notifications_queue_pending_idx
  on public.notifications_queue (scheduled_for)
  where sent_at is null;
