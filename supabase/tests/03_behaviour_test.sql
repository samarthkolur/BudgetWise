-- Behaviour of the schema's own logic: constraints, triggers, views and the
-- functions the app calls as RPCs.
--
-- Runs after the RLS suite, in the same database, so it inherits Alice and Bob.
-- Fixtures here use fresh users to keep the streak arithmetic clean.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1. The period check constraint refuses anything but a month start.
-- ---------------------------------------------------------------------------

do $$
declare
  blocked boolean := false;
begin
  insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'carol@test.local');

  begin
    insert into public.monthly_budgets (user_id, period, income_minor)
    values ('33333333-3333-3333-3333-333333333333', date_trunc('month', current_date)::date + 15, 100000);
  exception when check_violation then
    blocked := true;
  end;

  if not blocked then
    raise exception 'a mid-month period was accepted; the month key is not normalised';
  end if;
  raise notice 'PASS  period must be the first of the month';
end
$$;

-- ---------------------------------------------------------------------------
-- 2. One budget per user per month.
-- ---------------------------------------------------------------------------

do $$
declare
  blocked boolean := false;
  p date := (date_trunc('month', current_date) + interval '1 month')::date;
begin
  insert into public.monthly_budgets (user_id, period, income_minor)
  values ('33333333-3333-3333-3333-333333333333', p, 100000);

  begin
    insert into public.monthly_budgets (user_id, period, income_minor)
    values ('33333333-3333-3333-3333-333333333333', p, 200000);
  exception when unique_violation then
    blocked := true;
  end;

  if not blocked then
    raise exception 'a second budget was created for the same month';
  end if;
  raise notice 'PASS  one budget per user per month';
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Savings cannot exceed income.
-- ---------------------------------------------------------------------------

do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.monthly_budgets (user_id, period, income_minor, savings_target_minor)
    values ('33333333-3333-3333-3333-333333333333',
            (date_trunc('month', current_date) + interval '2 months')::date, 100000, 500000);
  exception when check_violation then
    blocked := true;
  end;

  if not blocked then
    raise exception 'a savings target above income was accepted';
  end if;
  raise notice 'PASS  savings target cannot exceed income';
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Money columns reject negatives and zero-amount expenses.
-- ---------------------------------------------------------------------------

do $$
declare
  b uuid;
  c uuid;
  negative_blocked boolean := false;
  zero_blocked boolean := false;
begin
  select id into b from public.monthly_budgets
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;
  select id into c from public.budget_categories
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;

  begin
    insert into public.expenses (user_id, budget_id, category_id, amount_minor)
    values ('11111111-1111-1111-1111-111111111111', b, c, -500);
  exception when check_violation then negative_blocked := true;
  end;

  begin
    insert into public.expenses (user_id, budget_id, category_id, amount_minor)
    values ('11111111-1111-1111-1111-111111111111', b, c, 0);
  exception when check_violation then zero_blocked := true;
  end;

  if not negative_blocked then
    raise exception 'a negative expense was accepted';
  end if;
  if not zero_blocked then
    raise exception 'a zero expense was accepted';
  end if;
  raise notice 'PASS  expense amounts must be positive';
end
$$;

-- ---------------------------------------------------------------------------
-- 5. v_category_spend states overspend separately from remaining, and never
--    reports a negative remainder.
-- ---------------------------------------------------------------------------

do $$
declare
  b uuid;
  c uuid;
  r record;
begin
  insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444', 'dave@test.local');

  insert into public.monthly_budgets (user_id, period, income_minor, savings_target_minor)
  values ('44444444-4444-4444-4444-444444444444', date_trunc('month', current_date)::date, 5000000, 1000000)
  returning id into b;

  insert into public.budget_categories (user_id, budget_id, category_key, display_name, allocated_minor, allocated_percent)
  values ('44444444-4444-4444-4444-444444444444', b, 'food', 'Food', 500000, 12.5)
  returning id into c;

  insert into public.expenses (user_id, budget_id, category_id, amount_minor)
  values ('44444444-4444-4444-4444-444444444444', b, c, 620000);

  select * into r from public.v_category_spend where category_id = c;

  if r.spent_minor <> 620000 then
    raise exception 'expected spent 620000, got %', r.spent_minor;
  end if;
  if r.remaining_minor <> 0 then
    raise exception 'overspent category reported remaining %, expected 0', r.remaining_minor;
  end if;
  if r.overspend_minor <> 120000 then
    raise exception 'expected overspend 120000, got %', r.overspend_minor;
  end if;
  if round(r.pct_used, 2) <> 1.24 then
    raise exception 'expected pct_used 1.24, got %', r.pct_used;
  end if;
  raise notice 'PASS  v_category_spend separates overspend from remaining';
end
$$;

-- ---------------------------------------------------------------------------
-- 6. An unallocated category is not 100% spent. Division by zero here would
--    render a full red bar on a category nobody budgeted for.
-- ---------------------------------------------------------------------------

do $$
declare
  b uuid;
  c uuid;
  used numeric;
begin
  select id into b from public.monthly_budgets
   where user_id = '44444444-4444-4444-4444-444444444444' limit 1;

  insert into public.budget_categories (user_id, budget_id, category_key, display_name, allocated_minor, allocated_percent)
  values ('44444444-4444-4444-4444-444444444444', b, 'misc', 'Miscellaneous', 0, 0)
  returning id into c;

  select pct_used into used from public.v_category_spend where category_id = c;
  if used <> 0 then
    raise exception 'a zero-allocation category reported pct_used %', used;
  end if;
  raise notice 'PASS  zero-allocation category reads as 0%% used';
end
$$;

-- ---------------------------------------------------------------------------
-- 7. v_budget_summary computes spendable and remaining in the PRD's order.
-- ---------------------------------------------------------------------------

do $$
declare
  r record;
begin
  select * into r from public.v_budget_summary
   where user_id = '44444444-4444-4444-4444-444444444444';

  -- income 50,000.00, savings 10,000.00 => spendable 40,000.00
  if r.spendable_minor <> 4000000 then
    raise exception 'expected spendable 4000000, got %', r.spendable_minor;
  end if;
  -- spent 6,200.00 => remaining 33,800.00
  if r.remaining_minor <> 3380000 then
    raise exception 'expected remaining 3380000, got %', r.remaining_minor;
  end if;
  if r.category_count <> 2 then
    raise exception 'expected 2 categories, got %', r.category_count;
  end if;
  raise notice 'PASS  v_budget_summary takes savings off the top';
end
$$;

-- ---------------------------------------------------------------------------
-- 8. goals.saved_minor tracks its contributions, and recomputes on delete
--    rather than incrementing.
-- ---------------------------------------------------------------------------

do $$
declare
  g uuid;
  saved bigint;
  st text;
begin
  insert into public.goals (user_id, title, target_minor)
  values ('44444444-4444-4444-4444-444444444444', 'Emergency fund', 1000000)
  returning id into g;

  insert into public.goal_contributions (user_id, goal_id, amount_minor)
  values ('44444444-4444-4444-4444-444444444444', g, 300000);
  insert into public.goal_contributions (user_id, goal_id, amount_minor)
  values ('44444444-4444-4444-4444-444444444444', g, 200000);

  select saved_minor into saved from public.goals where id = g;
  if saved <> 500000 then
    raise exception 'expected saved 500000, got %', saved;
  end if;

  delete from public.goal_contributions where goal_id = g and amount_minor = 200000;
  select saved_minor into saved from public.goals where id = g;
  if saved <> 300000 then
    raise exception 'after delete expected saved 300000, got %', saved;
  end if;

  insert into public.goal_contributions (user_id, goal_id, amount_minor)
  values ('44444444-4444-4444-4444-444444444444', g, 700000);
  select saved_minor, status into saved, st from public.goals where id = g;
  if saved <> 1000000 or st <> 'achieved' then
    raise exception 'goal should be achieved at %, status %', saved, st;
  end if;
  raise notice 'PASS  goal totals recompute and flip to achieved';
end
$$;

-- ---------------------------------------------------------------------------
-- 9. fn_savings_streak counts completed months only, and breaks on a miss.
--
--    Six successful completed months is the PRD's unlock threshold, so this
--    fixture is the one that proves the gate opens for the right reason.
-- ---------------------------------------------------------------------------

do $$
declare
  uid uuid := '55555555-5555-5555-5555-555555555555';
  b uuid;
  p date;
  i int;
  streak int;
begin
  insert into auth.users (id, email) values (uid, 'erin@test.local');

  -- Seven completed months, all successful, plus the current (in-progress) one.
  for i in 1..7 loop
    p := (date_trunc('month', current_date) - (i || ' months')::interval)::date;
    insert into public.monthly_budgets (user_id, period, income_minor, savings_target_minor)
    values (uid, p, 5000000, 1000000) returning id into b;
    insert into public.savings_entries (user_id, budget_id, amount_minor, saved_on)
    values (uid, b, 1000000, p);
  end loop;

  insert into public.monthly_budgets (user_id, period, income_minor, savings_target_minor)
  values (uid, date_trunc('month', current_date)::date, 5000000, 1000000);

  streak := public.fn_savings_streak(uid);
  if streak <> 7 then
    raise exception 'expected a 7-month streak, got %', streak;
  end if;

  if not public.fn_investing_unlocked(uid) then
    raise exception 'a 7-month streak did not unlock investing';
  end if;
  raise notice 'PASS  a 7-month streak unlocks investing';
end
$$;

do $$
declare
  uid uuid := '66666666-6666-6666-6666-666666666666';
  b uuid;
  p date;
  i int;
  streak int;
begin
  insert into auth.users (id, email) values (uid, 'frank@test.local');

  -- Two good months, then a missed one, then three more good ones. The streak
  -- must stop at the miss rather than counting around it.
  for i in 1..6 loop
    p := (date_trunc('month', current_date) - (i || ' months')::interval)::date;
    insert into public.monthly_budgets (user_id, period, income_minor, savings_target_minor)
    values (uid, p, 5000000, 1000000) returning id into b;

    if i <> 3 then
      insert into public.savings_entries (user_id, budget_id, amount_minor, saved_on)
      values (uid, b, 1000000, p);
    else
      insert into public.savings_entries (user_id, budget_id, amount_minor, saved_on)
      values (uid, b, 200000, p);
    end if;
  end loop;

  streak := public.fn_savings_streak(uid);
  if streak <> 2 then
    raise exception 'expected the streak to break at 2, got %', streak;
  end if;
  if public.fn_investing_unlocked(uid) then
    raise exception 'a broken streak unlocked investing';
  end if;
  raise notice 'PASS  the streak breaks on a missed month';
end
$$;

-- ---------------------------------------------------------------------------
-- 10. Unlocking is permanent. Erin above earned it; stamp it, wipe the reason,
--     and it must still read as unlocked.
-- ---------------------------------------------------------------------------

do $$
declare
  uid uuid := '55555555-5555-5555-5555-555555555555';
begin
  update public.profiles set investing_unlocked_at = now() where id = uid;
  delete from public.savings_entries where user_id = uid;

  if public.fn_savings_streak(uid) <> 0 then
    raise exception 'fixture error: the streak should now be zero';
  end if;
  if not public.fn_investing_unlocked(uid) then
    raise exception 'investing re-locked after the streak was broken';
  end if;
  raise notice 'PASS  unlocking is permanent';
end
$$;

-- ---------------------------------------------------------------------------
-- 11. fn_create_month_budget is atomic and refuses an allocation that does not
--     sum to spendable income.
-- ---------------------------------------------------------------------------

do $$
declare
  uid uuid := '77777777-7777-7777-7777-777777777777';
  p date := (date_trunc('month', current_date) + interval '3 months')::date;
  new_id uuid;
  blocked boolean := false;
  cat_count int;
  budget_count int;
begin
  insert into auth.users (id, email) values (uid, 'grace@test.local');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', uid::text, true);

  -- Income 50,000.00, savings 10,000.00 => spendable 40,000.00.
  -- These allocations sum to 39,000.00 and must be refused.
  begin
    perform public.fn_create_month_budget(
      p, 5000000, 'percent', 20, 1000000,
      '[{"category_key":"food","display_name":"Food","allocated_minor":2000000,"allocated_percent":50},
        {"category_key":"bills","display_name":"Bills","allocated_minor":1900000,"allocated_percent":47.5}]'::jsonb
    );
  exception when others then
    blocked := true;
  end;

  if not blocked then
    raise exception 'an allocation that does not sum to spendable income was accepted';
  end if;

  -- Nothing may survive the refusal.
  select count(*) into budget_count from public.monthly_budgets where user_id = uid and period = p;
  if budget_count <> 0 then
    raise exception 'a refused budget left % row(s) behind', budget_count;
  end if;

  -- The correct total is accepted, budget and categories together.
  new_id := public.fn_create_month_budget(
    p, 5000000, 'percent', 20, 1000000,
    '[{"category_key":"food","display_name":"Food","allocated_minor":2000000,"allocated_percent":50},
      {"category_key":"bills","display_name":"Bills","allocated_minor":2000000,"allocated_percent":50}]'::jsonb
  );

  select count(*) into cat_count from public.budget_categories where budget_id = new_id;
  reset role;

  if cat_count <> 2 then
    raise exception 'expected 2 categories, got %', cat_count;
  end if;
  raise notice 'PASS  fn_create_month_budget is atomic and validates the total';
end
$$;

-- ---------------------------------------------------------------------------
-- 12. A new auth user gets a profile without the client asking for one.
-- ---------------------------------------------------------------------------

do $$
declare
  n int;
  name text;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values ('88888888-8888-8888-8888-888888888888', 'heidi@test.local',
          '{"full_name":"Heidi","avatar_url":"https://example.test/h.png"}'::jsonb);

  select count(*), max(display_name) into n, name
    from public.profiles where id = '88888888-8888-8888-8888-888888888888';

  if n <> 1 then
    raise exception 'expected exactly 1 profile row, got %', n;
  end if;
  if name <> 'Heidi' then
    raise exception 'expected display_name Heidi, got %', name;
  end if;
  raise notice 'PASS  profile is created by trigger on sign-up';
end
$$;

-- ---------------------------------------------------------------------------
-- 13. Deleting the auth user removes every trace of them.
-- ---------------------------------------------------------------------------

do $$
declare
  leftovers int;
begin
  delete from auth.users where id = '44444444-4444-4444-4444-444444444444';

  select (select count(*) from public.profiles where id = '44444444-4444-4444-4444-444444444444')
       + (select count(*) from public.monthly_budgets where user_id = '44444444-4444-4444-4444-444444444444')
       + (select count(*) from public.budget_categories where user_id = '44444444-4444-4444-4444-444444444444')
       + (select count(*) from public.expenses where user_id = '44444444-4444-4444-4444-444444444444')
       + (select count(*) from public.goals where user_id = '44444444-4444-4444-4444-444444444444')
    into leftovers;

  if leftovers <> 0 then
    raise exception 'account deletion left % row(s) behind', leftovers;
  end if;
  raise notice 'PASS  deleting the auth user cascades everywhere';
end
$$;
