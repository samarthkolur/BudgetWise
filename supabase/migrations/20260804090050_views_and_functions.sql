-- Derived reads and server-side decisions.
--
-- Ordered before the RLS migration because the investments insert policy calls
-- fn_investing_unlocked(): a policy cannot reference a function that does not
-- exist yet.
--
-- Views are `security_invoker`, so they run with the querying user's
-- permissions and the underlying tables' RLS still applies. A view without it
-- runs as its owner and is a hole straight through every policy in the next
-- migration.

-- ---------------------------------------------------------------------------
-- v_category_spend — what every category card is drawn from.
--
-- The dashboard reads this rather than summing expenses client-side. Two places
-- computing the same total is how the category cards and the remaining balance
-- start disagreeing by a few rupees and nobody can say which is right.
-- ---------------------------------------------------------------------------

create view public.v_category_spend
with (security_invoker = true) as
select
  c.id                as category_id,
  c.user_id,
  c.budget_id,
  c.category_key,
  c.display_name,
  c.icon,
  c.sort_order,
  c.allocated_minor,
  c.allocated_percent,
  coalesce(sum(e.amount_minor), 0)::bigint as spent_minor,
  greatest(c.allocated_minor - coalesce(sum(e.amount_minor), 0), 0)::bigint as remaining_minor,
  greatest(coalesce(sum(e.amount_minor), 0) - c.allocated_minor, 0)::bigint as overspend_minor,
  case
    when c.allocated_minor = 0 then 0::numeric
    else round(coalesce(sum(e.amount_minor), 0)::numeric / c.allocated_minor, 4)
  end as pct_used,
  count(e.id)::int as expense_count
from public.budget_categories c
left join public.expenses e on e.category_id = c.id
group by c.id;

-- ---------------------------------------------------------------------------
-- v_budget_summary — the dashboard header, in one row.
-- ---------------------------------------------------------------------------

create view public.v_budget_summary
with (security_invoker = true) as
with spend as (
  select budget_id, coalesce(sum(amount_minor), 0)::bigint as spent_minor, count(*)::int as expense_count
    from public.expenses group by budget_id
),
allocated as (
  select budget_id, coalesce(sum(allocated_minor), 0)::bigint as allocated_minor, count(*)::int as category_count
    from public.budget_categories group by budget_id
),
saved as (
  select budget_id, coalesce(sum(amount_minor), 0)::bigint as saved_minor
    from public.savings_entries group by budget_id
),
invested as (
  select budget_id, coalesce(sum(amount_minor), 0)::bigint as invested_minor
    from public.investments group by budget_id
),
logged_days as (
  select budget_id, count(distinct spent_on)::int as days_with_expenses
    from public.expenses group by budget_id
)
select
  b.id as budget_id,
  b.user_id,
  b.period,
  b.status,
  b.income_minor,
  b.savings_mode,
  b.savings_percent,
  b.savings_target_minor,
  b.investment_target_minor,
  b.savings_confirmed_at,
  coalesce(a.allocated_minor, 0) as allocated_minor,
  coalesce(a.category_count, 0)  as category_count,
  coalesce(s.spent_minor, 0)     as spent_minor,
  coalesce(s.expense_count, 0)   as expense_count,
  coalesce(sv.saved_minor, 0)    as saved_minor,
  coalesce(iv.invested_minor, 0) as invested_minor,
  coalesce(ld.days_with_expenses, 0) as days_with_expenses,
  -- Spendable is income less savings and investment: the Earn → Save → Invest →
  -- Spend order expressed as arithmetic.
  greatest(
    b.income_minor - b.savings_target_minor - coalesce(b.investment_target_minor, 0), 0
  )::bigint as spendable_minor,
  greatest(
    b.income_minor - b.savings_target_minor - coalesce(b.investment_target_minor, 0)
      - coalesce(s.spent_minor, 0), 0
  )::bigint as remaining_minor,
  (date_trunc('month', b.period) + interval '1 month - 1 day')::date as last_day,
  extract(day from (date_trunc('month', b.period) + interval '1 month - 1 day'))::int as total_days
from public.monthly_budgets b
left join allocated a  on a.budget_id  = b.id
left join spend s      on s.budget_id  = b.id
left join saved sv     on sv.budget_id = b.id
left join invested iv  on iv.budget_id = b.id
left join logged_days ld on ld.budget_id = b.id;

-- ---------------------------------------------------------------------------
-- fn_savings_streak
--
-- Consecutive months, ending at the most recent COMPLETED month, in which the
-- user saved at least what they set out to save.
--
-- The current month is excluded on purpose: it is still in progress, and a
-- streak that counted an unfinished month would break every time the user
-- opened the app on the 2nd. A target of zero does not count — skipping the
-- commitment is not the same as keeping it.
--
-- Mirrored in Dart (core/budget/investing_unlock.dart) for display. This copy
-- is the authoritative one, because it is the copy the insert policy consults.
-- ---------------------------------------------------------------------------

create or replace function public.fn_savings_streak(uid uuid)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  cursor_period date := (date_trunc('month', current_date) - interval '1 month')::date;
  streak int := 0;
  met boolean;
begin
  loop
    select b.savings_target_minor > 0
             and coalesce((
                   select sum(s.amount_minor) from public.savings_entries s
                    where s.budget_id = b.id
                 ), 0) >= b.savings_target_minor
      into met
      from public.monthly_budgets b
     where b.user_id = uid and b.period = cursor_period;

    if met is null or met = false then
      exit;
    end if;

    streak := streak + 1;
    cursor_period := (cursor_period - interval '1 month')::date;
  end loop;

  return streak;
end;
$$;

-- ---------------------------------------------------------------------------
-- fn_emergency_fund_ratio
--
-- Lifetime savings against three months of average essential spend. Essentials
-- are bills, food, healthcare and transport — the categories a person cannot
-- simply stop paying.
--
-- Returns 0 when there is no essential-spend history: an unknown denominator
-- must not read as a satisfied cushion.
-- ---------------------------------------------------------------------------

create or replace function public.fn_emergency_fund_ratio(uid uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  total_saved bigint;
  avg_essentials numeric;
begin
  select coalesce(sum(amount_minor), 0) into total_saved
    from public.savings_entries where user_id = uid;

  select avg(monthly_total) into avg_essentials
    from (
      select b.period, coalesce(sum(e.amount_minor), 0) as monthly_total
        from public.monthly_budgets b
        join public.budget_categories c on c.budget_id = b.id
        left join public.expenses e on e.category_id = c.id
       where b.user_id = uid
         and c.category_key in ('bills', 'food', 'healthcare', 'transport')
         and b.period < date_trunc('month', current_date)::date
       group by b.period
    ) monthly;

  if avg_essentials is null or avg_essentials = 0 then
    return 0;
  end if;

  return round(total_saved::numeric / (avg_essentials * 3), 4);
end;
$$;

-- ---------------------------------------------------------------------------
-- fn_investing_unlocked
--
-- Either route unlocks: six consecutive months of meeting the savings target,
-- or an emergency fund covering three months of essentials.
--
-- Unlocking is PERMANENT. profiles.investing_unlocked_at short-circuits the
-- whole calculation, so a user who later breaks a streak keeps access. The PRD
-- frames this as an achievement to celebrate; revoking it would make it a
-- punishment nobody was warned about.
-- ---------------------------------------------------------------------------

create or replace function public.fn_investing_unlocked(uid uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  already timestamptz;
begin
  select investing_unlocked_at into already from public.profiles where id = uid;
  if already is not null then
    return true;
  end if;

  return public.fn_savings_streak(uid) >= 6
      or public.fn_emergency_fund_ratio(uid) >= 1.0;
end;
$$;

-- ---------------------------------------------------------------------------
-- fn_claim_investing_unlock
--
-- Stamps the unlock once, and reports whether this call is the one that earned
-- it — which is what the celebration screen keys off. Called on app start.
-- ---------------------------------------------------------------------------

create or replace function public.fn_claim_investing_unlock()
returns table (is_unlocked boolean, newly_unlocked boolean, streak_months int, fund_ratio numeric)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  already timestamptz;
  streak int;
  ratio numeric;
  qualifies boolean;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select investing_unlocked_at into already from public.profiles where id = uid;
  streak := public.fn_savings_streak(uid);
  ratio  := public.fn_emergency_fund_ratio(uid);

  if already is not null then
    return query select true, false, streak, ratio;
    return;
  end if;

  qualifies := streak >= 6 or ratio >= 1.0;

  if qualifies then
    update public.profiles set investing_unlocked_at = now() where id = uid;
  end if;

  return query select qualifies, qualifies, streak, ratio;
end;
$$;

-- ---------------------------------------------------------------------------
-- fn_create_month_budget
--
-- Creates a month's plan and its categories in ONE transaction.
--
-- Onboarding writes a budget and nine categories. Done as separate client
-- calls, a dropped connection halfway leaves a budget with three categories and
-- no way for the user to tell — the dashboard would render a plan that silently
-- does not add up. As one RPC it either all exists or none of it does.
--
-- Category amounts are computed by the client's largest-remainder allocator and
-- passed in; this function verifies they sum to the spendable income rather than
-- recomputing them, so the two implementations cannot drift apart unnoticed.
-- ---------------------------------------------------------------------------

create or replace function public.fn_create_month_budget(
  p_period                  date,
  p_income_minor            bigint,
  p_savings_mode            text,
  p_savings_percent         numeric,
  p_savings_target_minor    bigint,
  p_categories              jsonb,
  p_carried_from_period     date default null,
  p_investment_target_minor bigint default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  new_budget_id uuid;
  allocated_total bigint;
  spendable bigint;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if p_period <> date_trunc('month', p_period)::date then
    raise exception 'period must be the first day of a month, got %', p_period;
  end if;

  spendable := greatest(p_income_minor - p_savings_target_minor - coalesce(p_investment_target_minor, 0), 0);

  select coalesce(sum((value ->> 'allocated_minor')::bigint), 0)
    into allocated_total
    from jsonb_array_elements(p_categories);

  if allocated_total <> spendable then
    raise exception
      'category allocations (%) do not sum to spendable income (%)', allocated_total, spendable;
  end if;

  insert into public.monthly_budgets (
    user_id, period, income_minor, savings_mode, savings_percent,
    savings_target_minor, investment_target_minor, carried_from_period, status
  )
  values (
    uid, p_period, p_income_minor, p_savings_mode, p_savings_percent,
    p_savings_target_minor, p_investment_target_minor, p_carried_from_period, 'active'
  )
  returning id into new_budget_id;

  insert into public.budget_categories (
    user_id, budget_id, category_key, display_name, icon,
    allocated_minor, allocated_percent, sort_order
  )
  select
    uid,
    new_budget_id,
    value ->> 'category_key',
    value ->> 'display_name',
    value ->> 'icon',
    (value ->> 'allocated_minor')::bigint,
    (value ->> 'allocated_percent')::numeric,
    coalesce((value ->> 'sort_order')::int, ordinality::int)
  from jsonb_array_elements(p_categories) with ordinality;

  return new_budget_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- fn_record_health_score
--
-- Writes the month's score. health_scores has no user INSERT policy: the score
-- is the product's judgement of the user's discipline, and a number the user
-- can set about themselves is not a score.
-- ---------------------------------------------------------------------------

create or replace function public.fn_record_health_score(
  p_budget_id  uuid,
  p_score      int,
  p_components jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  owns boolean;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- security definer bypasses RLS, so ownership is checked explicitly here.
  -- Without this, any authenticated user could score any budget by id.
  select exists (
    select 1 from public.monthly_budgets where id = p_budget_id and user_id = uid
  ) into owns;

  if not owns then
    raise exception 'budget not found';
  end if;

  insert into public.health_scores (user_id, budget_id, score, components)
  values (uid, p_budget_id, p_score, p_components)
  on conflict (budget_id)
  do update set score = excluded.score,
                components = excluded.components,
                computed_at = now();
end;
$$;
