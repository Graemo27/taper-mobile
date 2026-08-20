-- Drives the taper schema against a real Postgres.
--
-- Run it with three commands, in this order:
--
--   supabase start
--   supabase db reset --local
--   supabase test db
--
-- The reset is not optional and `test db` is not a substitute for it. `test db`
-- runs pg_prove against whatever is already in the local database; it applies
-- no migrations of its own. Run alone it tests the previous run's leftovers,
-- which is how the first draft of this file failed — on rows a throwaway
-- session had committed hours earlier.
--
-- `--local` is spelled out because `--linked` is the sibling flag on the same
-- command, and it resets the hosted project. Nothing here touches that.
--
-- This exists because the three taper migrations have never been pushed, and
-- "it will probably apply" is not something anyone should be asked to
-- authorise. The two rules worth the most are the ones no client-side test can
-- reach: RLS actually isolating one anonymous user from another, and the
-- NRT-only rule as a constraint rather than as an intention. Both are enforced
-- by the database or not at all.
--
-- The schema's own history is the argument for the constraint checks.
-- `current_cap_mg` shipped as `> 0`, which would have failed to persist every
-- dated plan on the one week that matters — the quit week, where the cap is
-- zero. That is now a test rather than a memory.

begin;
select plan(21);

-- Two anonymous users, which is what every user in this project is.
insert into auth.users (id, instance_id, aud, role, created_at, updated_at, is_anonymous)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', now(), now(), true),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', now(), now(), true)
on conflict (id) do nothing;

-- Runs a statement as a signed-in user and reports rows affected, resetting the
-- role either way. RLS filters rather than errors on select and update, so the
-- row count is the assertion — an isolation failure looks like a successful
-- query returning someone else's data.
create function pg_temp.as_user(uid text, stmt text) returns int as $$
declare n int;
begin
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L',
                 json_build_object('sub', uid, 'role', 'authenticated')::text);
  execute stmt;
  get diagnostics n = row_count;
  execute 'reset role';
  return n;
exception when others then
  execute 'reset role';
  raise;
end $$ language plpgsql;

-- MARK: the tables the pivot created, and the ones it retired

select has_table('public', 'taper_plans', 'taper_plans exists');
select has_table('public', 'pad_keys', 'pad_keys exists');
select has_table('public', 'check_ins', 'check_ins exists');
select hasnt_table('public', 'journal_entries', 'the food journal is retired');
select hasnt_table('public', 'favourites', 'food favourites are retired');

-- MARK: the cap constraints

select lives_ok(
  $$insert into public.taper_plans
      (user_id, starting_cap_mg, current_cap_mg, cap_effective_from, quit_date,
       first_use_minutes, sick_in_bed)
    values ('11111111-1111-1111-1111-111111111111', 18, 18, current_date,
            current_date + 56, 20, true)$$,
  'a dated plan is accepted'
);

select lives_ok(
  $$update public.taper_plans set current_cap_mg = 0
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  'the cap may reach zero, which is the quit week'
);

select throws_ok(
  $$update public.taper_plans set current_cap_mg = -1
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  '23514',
  null,
  'the cap may not go below zero'
);

select throws_ok(
  $$insert into public.taper_plans
      (user_id, starting_cap_mg, current_cap_mg, cap_effective_from,
       first_use_minutes, sick_in_bed)
    values ('22222222-2222-2222-2222-222222222222', 0, 0, current_date, 20, true)$$,
  '23514',
  null,
  'a plan starting at zero has nothing to taper and is refused'
);

select lives_ok(
  $$update public.taper_plans set quit_date = null
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  'a run holding where it is may have no quit date'
);

select throws_ok(
  $$update public.taper_plans set quit_date = cap_effective_from - 1
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  '23514',
  null,
  'a quit date before the plan began is refused'
);

select throws_ok(
  $$update public.taper_plans set first_use_minutes = 2000
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  '23514',
  null,
  'minutes to the first use stay inside a day'
);

select throws_ok(
  $$insert into public.taper_plans
      (user_id, starting_cap_mg, current_cap_mg, cap_effective_from,
       first_use_minutes, sick_in_bed)
    values ('11111111-1111-1111-1111-111111111111', 20, 20, current_date, 20, true)$$,
  '23505',
  null,
  'one plan per person, so "the cap" is never ambiguous'
);

-- MARK: the NRT-only rule, as the database states it
--
-- The app must never help anyone shop for nicotine it is not licensed to
-- recommend. That rule is written in three places on purpose — the Edge
-- Function, the client, and here — because a client writing straight to the
-- table would walk past the first two.

select throws_ok(
  $$insert into public.pad_keys (user_id, ledger, label, form, mg, ndc)
    values ('11111111-1111-1111-1111-111111111111', 'source', 'Zyn', 'pouch', 6, '12345-678-90')$$,
  '23514',
  null,
  'a pouch cannot carry a drug code, because it is not a drug'
);

select throws_ok(
  $$insert into public.pad_keys (user_id, ledger, label, form, mg)
    values ('11111111-1111-1111-1111-111111111111', 'treatment', 'Zyn', 'pouch', 6)$$,
  '23514',
  null,
  'a pouch cannot be filed as a treatment'
);

select lives_ok(
  $$insert into public.pad_keys (user_id, ledger, label, form, mg, ndc)
    values ('11111111-1111-1111-1111-111111111111', 'treatment', 'Nicorette', 'lozenge', 2, '12345-678-90')$$,
  'a licensed lozenge is a treatment and may carry its code'
);

-- MARK: isolation between two anonymous strangers

select is(
  pg_temp.as_user('11111111-1111-1111-1111-111111111111',
                  'select * from public.taper_plans'),
  1,
  'a user reads their own plan'
);

select is(
  pg_temp.as_user('22222222-2222-2222-2222-222222222222',
                  'select * from public.taper_plans'),
  0,
  'a stranger reads none of it'
);

select is(
  pg_temp.as_user('22222222-2222-2222-2222-222222222222',
                  $$update public.taper_plans set current_cap_mg = 99
                     where user_id = '11111111-1111-1111-1111-111111111111'$$),
  0,
  'a stranger cannot move someone else''s cap'
);

select throws_ok(
  $$select pg_temp.as_user('22222222-2222-2222-2222-222222222222',
      $q$insert into public.taper_plans
          (user_id, starting_cap_mg, current_cap_mg, cap_effective_from,
           first_use_minutes, sick_in_bed)
         values ('11111111-1111-1111-1111-111111111111', 5, 5, current_date, 20, false)$q$)$$,
  '42501',
  null,
  'a stranger cannot write a plan on someone else''s behalf'
);

select throws_ok(
  $$select pg_temp.as_user('11111111-1111-1111-1111-111111111111',
      $q$delete from public.taper_plans
          where user_id = '11111111-1111-1111-1111-111111111111'$q$)$$,
  '42501',
  null,
  'nobody deletes a plan, because no delete policy was ever granted'
);

select * from finish();
rollback;
