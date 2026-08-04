-- Cross-user isolation suite.
--
-- This is the test that matters most in the whole project. There is no API tier
-- between the Flutter client and Postgres, so RLS is the entire authorization
-- boundary; a gap here is not a bug in a feature, it is every user's financial
-- history readable by every other user.
--
-- Structure: two real users with real data, then every table checked from the
-- other user's session. Assertions raise, so a failure aborts with a message
-- naming the table rather than printing a diff nobody reads.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Fixtures. Created as the owner (RLS off for setup) so the test is arranging
-- data, not testing the arrangement.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"full_name":"Alice"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local',   '{"full_name":"Bob"}'::jsonb);

do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  a_budget uuid;
  b_budget uuid;
  a_cat uuid;
  b_cat uuid;
  a_goal uuid;
begin
  insert into public.monthly_budgets (user_id, period, income_minor, savings_mode, savings_percent, savings_target_minor)
  values (alice, date_trunc('month', current_date)::date, 5000000, 'percent', 20, 1000000)
  returning id into a_budget;

  insert into public.monthly_budgets (user_id, period, income_minor, savings_mode, savings_percent, savings_target_minor)
  values (bob, date_trunc('month', current_date)::date, 3000000, 'percent', 10, 300000)
  returning id into b_budget;

  insert into public.budget_categories (user_id, budget_id, category_key, display_name, allocated_minor, allocated_percent, sort_order)
  values (alice, a_budget, 'food', 'Food', 1500000, 37.5, 0) returning id into a_cat;

  insert into public.budget_categories (user_id, budget_id, category_key, display_name, allocated_minor, allocated_percent, sort_order)
  values (bob, b_budget, 'food', 'Food', 1000000, 37.0, 0) returning id into b_cat;

  insert into public.expenses (user_id, budget_id, category_id, amount_minor, spent_on, note)
  values (alice, a_budget, a_cat, 25000, current_date, 'alice lunch');

  insert into public.expenses (user_id, budget_id, category_id, amount_minor, spent_on, note)
  values (bob, b_budget, b_cat, 18000, current_date, 'bob lunch');

  insert into public.savings_entries (user_id, budget_id, amount_minor, saved_on)
  values (alice, a_budget, 1000000, current_date);

  insert into public.goals (user_id, title, target_minor, target_date)
  values (alice, 'Laptop', 8000000, (current_date + 180)) returning id into a_goal;

  insert into public.goal_contributions (user_id, goal_id, budget_id, amount_minor)
  values (alice, a_goal, a_budget, 500000);

  insert into public.insights (user_id, budget_id, kind, title, body)
  values (alice, a_budget, 'budget_warning', 'Food is at 80%', 'You have 12 days left.');

  insert into public.health_scores (user_id, budget_id, score, components)
  values (alice, a_budget, 87, '[]'::jsonb);

  insert into public.notifications_queue (user_id, kind, scheduled_for)
  values (alice, 'savings_reminder', now() + interval '1 day');
end
$$;

-- ---------------------------------------------------------------------------
-- 1. Every user table is readable by its owner and invisible to the other user.
-- ---------------------------------------------------------------------------

do $$
declare
  tbl text;
  owner_rows int;
  other_rows int;
  user_tables text[] := array[
    'monthly_budgets', 'budget_categories', 'expenses', 'savings_entries',
    'goals', 'goal_contributions', 'insights', 'health_scores', 'notifications_queue'
  ];
begin
  foreach tbl in array user_tables loop
    -- Alice's session.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
    execute format('select count(*) from public.%I', tbl) into owner_rows;

    -- Bob's session, same table.
    perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
    execute format('select count(*) from public.%I where user_id = %L', tbl,
                   '11111111-1111-1111-1111-111111111111') into other_rows;
    reset role;

    if owner_rows < 1 then
      raise exception 'RLS: alice cannot read her own public.% (got % rows)', tbl, owner_rows;
    end if;
    if other_rows <> 0 then
      raise exception 'RLS LEAK: bob can read % of alice''s rows in public.%', other_rows, tbl;
    end if;
  end loop;

  raise notice 'PASS  cross-user reads blocked on % tables', array_length(user_tables, 1);
end
$$;

-- ---------------------------------------------------------------------------
-- 2. A user cannot write a row owned by someone else.
-- ---------------------------------------------------------------------------

do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  blocked boolean := false;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  begin
    insert into public.monthly_budgets (user_id, period, income_minor)
    values (alice, (date_trunc('month', current_date) + interval '1 month')::date, 100000);
  exception when insufficient_privilege then
    blocked := true;
  end;

  reset role;

  if not blocked then
    raise exception 'RLS LEAK: bob inserted a monthly_budgets row owned by alice';
  end if;
  raise notice 'PASS  cross-user insert rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- 3. The composite foreign key stops the subtler attack: a row Bob legitimately
--    owns, attached to Alice's budget. The user_id column is honest, so a naive
--    `user_id = auth.uid()` policy alone would allow it.
-- ---------------------------------------------------------------------------

do $$
declare
  a_budget uuid;
  a_cat uuid;
  blocked boolean := false;
begin
  select id into a_budget from public.monthly_budgets
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;
  select id into a_cat from public.budget_categories
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  begin
    insert into public.expenses (user_id, budget_id, category_id, amount_minor)
    values ('22222222-2222-2222-2222-222222222222', a_budget, a_cat, 5000);
  exception
    when foreign_key_violation then blocked := true;
    when insufficient_privilege then blocked := true;
  end;

  reset role;

  if not blocked then
    raise exception 'LEAK: bob attached an expense he owns to alice''s budget';
  end if;
  raise notice 'PASS  composite FK rejects cross-user parent';
end
$$;

-- ---------------------------------------------------------------------------
-- 4. A user cannot update or delete another user's row.
-- ---------------------------------------------------------------------------

do $$
declare
  affected int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  update public.expenses set amount_minor = 1 where note = 'alice lunch';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'RLS LEAK: bob updated % of alice''s expenses', affected;
  end if;

  delete from public.expenses where note = 'alice lunch';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'RLS LEAK: bob deleted % of alice''s expenses', affected;
  end if;

  reset role;
  raise notice 'PASS  cross-user update and delete affect nothing';
end
$$;

-- ---------------------------------------------------------------------------
-- 5. health_scores is read-only to its owner. A score the user can set about
--    themselves is not a score.
-- ---------------------------------------------------------------------------

do $$
declare
  a_budget uuid;
  blocked boolean := false;
begin
  select id into a_budget from public.monthly_budgets
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  begin
    insert into public.health_scores (user_id, budget_id, score)
    values ('11111111-1111-1111-1111-111111111111', a_budget, 100);
  exception when insufficient_privilege then
    blocked := true;
  end;

  reset role;

  if not blocked then
    raise exception 'LEAK: alice wrote her own health score directly';
  end if;
  raise notice 'PASS  health_scores rejects direct client writes';
end
$$;

-- ---------------------------------------------------------------------------
-- 6. fn_record_health_score refuses a budget the caller does not own.
--    security definer bypasses RLS, so the ownership check inside the function
--    is the only thing standing between Bob and Alice's score.
-- ---------------------------------------------------------------------------

do $$
declare
  a_budget uuid;
  blocked boolean := false;
begin
  select id into a_budget from public.monthly_budgets
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  begin
    perform public.fn_record_health_score(a_budget, 5, '[]'::jsonb);
  exception when others then
    blocked := true;
  end;

  reset role;

  if not blocked then
    raise exception 'LEAK: bob scored alice''s budget through fn_record_health_score';
  end if;
  raise notice 'PASS  fn_record_health_score checks ownership';
end
$$;

-- ---------------------------------------------------------------------------
-- 7. Investing is locked for a user with no history, and the insert policy —
--    not just the UI — is what enforces it.
-- ---------------------------------------------------------------------------

do $$
declare
  b_budget uuid;
  blocked boolean := false;
begin
  select id into b_budget from public.monthly_budgets
   where user_id = '22222222-2222-2222-2222-222222222222' limit 1;

  if public.fn_investing_unlocked('22222222-2222-2222-2222-222222222222') then
    raise exception 'bob has no savings history but investing reads as unlocked';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  begin
    insert into public.investments (user_id, budget_id, amount_minor, instrument)
    values ('22222222-2222-2222-2222-222222222222', b_budget, 100000, 'mutual_fund');
  exception when insufficient_privilege then
    blocked := true;
  end;

  reset role;

  if not blocked then
    raise exception 'LEAK: locked user inserted an investment';
  end if;
  raise notice 'PASS  investments insert is gated on fn_investing_unlocked';
end
$$;

-- ---------------------------------------------------------------------------
-- 8. Every table in `public` has RLS enabled AND forced.
--    Catches the failure mode this suite could not otherwise see: a table added
--    in a later migration that nobody remembered to protect.
-- ---------------------------------------------------------------------------

do $$
declare
  unprotected text;
begin
  select string_agg(c.relname, ', ')
    into unprotected
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and (c.relrowsecurity = false or c.relforcerowsecurity = false);

  if unprotected is not null then
    raise exception 'tables without enabled+forced RLS: %', unprotected;
  end if;
  raise notice 'PASS  every public table has RLS enabled and forced';
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Views are security_invoker. A view without it runs as its owner and reads
--    straight through every policy above.
-- ---------------------------------------------------------------------------

do $$
declare
  leaky text;
begin
  select string_agg(c.relname, ', ')
    into leaky
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'v'
     and coalesce(
           (select option_value from pg_options_to_table(c.reloptions)
             where option_name = 'security_invoker'), 'false') <> 'true';

  if leaky is not null then
    raise exception 'views not marked security_invoker: %', leaky;
  end if;
  raise notice 'PASS  every view is security_invoker';
end
$$;

-- ---------------------------------------------------------------------------
-- 10. The views respect RLS in practice, not just in configuration.
-- ---------------------------------------------------------------------------

do $$
declare
  rows_seen int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  select count(*) into rows_seen from public.v_budget_summary
   where user_id = '11111111-1111-1111-1111-111111111111';
  if rows_seen <> 0 then
    raise exception 'RLS LEAK: v_budget_summary exposed % of alice''s rows to bob', rows_seen;
  end if;

  select count(*) into rows_seen from public.v_category_spend
   where user_id = '11111111-1111-1111-1111-111111111111';
  if rows_seen <> 0 then
    raise exception 'RLS LEAK: v_category_spend exposed % of alice''s rows to bob', rows_seen;
  end if;

  reset role;
  raise notice 'PASS  views enforce RLS at query time';
end
$$;
