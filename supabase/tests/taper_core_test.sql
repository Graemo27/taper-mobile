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
select plan(75);

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

-- Every pairing the client can produce, checked against the table that decides.
-- `PadForm.ledger` in the app is this constraint restated in Swift, and the two
-- have no mechanical link: a case put on the wrong side there compiles, passes
-- its own unit tests, and fails as a rejected insert on somebody's phone — the
-- one place this check cannot be read.

create function pg_temp.accepts(p_ledger text, p_form text) returns boolean as $$
begin
  insert into public.pad_keys (user_id, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', p_ledger, 'probe', p_form, 1);
  return true;
exception when check_violation then
  return false;
end;
$$ language plpgsql;

select is(
  (select bool_and(pg_temp.accepts(ledger, form)) from (values
    ('treatment', 'patch'), ('treatment', 'lozenge'), ('treatment', 'gum'),
    ('treatment', 'inhaler'), ('treatment', 'spray'),
    ('source', 'pouch'), ('source', 'vape'), ('source', 'cigarette'),
    ('source', 'dip'), ('source', 'other')
  ) as f(ledger, form)),
  true,
  'every form the app files is one the table accepts in that ledger'
);

select is(
  (select bool_or(pg_temp.accepts(ledger, form)) from (values
    ('source', 'patch'), ('source', 'lozenge'), ('source', 'gum'),
    ('source', 'inhaler'), ('source', 'spray'),
    ('treatment', 'pouch'), ('treatment', 'vape'), ('treatment', 'cigarette'),
    ('treatment', 'dip'), ('treatment', 'other')
  ) as f(ledger, form)),
  false,
  'no form may be filed in the ledger it does not belong to'
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

-- MARK: the log, and what must outlive the pad it was logged from

select throws_ok(
  $$insert into public.check_ins (user_id, logged_on, ledger, label, form, mg, quantity)
    values ('11111111-1111-1111-1111-111111111111', current_date, 'source', 'Pouch', 'pouch', 6, 21)$$,
  '23514',
  null,
  'a quantity past the column''s ceiling is refused'
);

select throws_ok(
  $$insert into public.check_ins (user_id, logged_on, ledger, label, form, mg, quantity)
    values ('11111111-1111-1111-1111-111111111111', current_date, 'source', 'Pouch', 'pouch', 6, 0)$$,
  '23514',
  null,
  'a quantity of none is refused too — logging nothing is not a check-in'
);

-- The snapshot's whole purpose, checked where it is actually enforced. Removing
-- a key from the pad must not remove the record of having used it: deleting
-- "Pouch, 6 mg" cannot be allowed to rewrite last month's totals.
create function pg_temp.entry_outliving_its_key() returns bigint as $$
declare
  key_id bigint;
  entry_id bigint;
begin
  insert into public.pad_keys (user_id, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', 'source', 'Doomed', 'pouch', 6)
  returning id into key_id;

  insert into public.check_ins (user_id, pad_key_id, logged_on, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', key_id, current_date, 'source', 'Doomed', 'pouch', 6)
  returning id into entry_id;

  delete from public.pad_keys where id = key_id;
  return entry_id;
end;
$$ language plpgsql;

create temporary table orphaned as select pg_temp.entry_outliving_its_key() as id;

select is(
  (select count(*)::int from public.check_ins c join orphaned o on c.id = o.id),
  1,
  'deleting a key leaves the history of having used it'
);

select is(
  (select c.pad_key_id from public.check_ins c join orphaned o on c.id = o.id),
  null::bigint,
  'only the provenance is cleared, and the snapshot stands on its own'
);

-- The row surviving is half the claim. What makes it a snapshot is that its
-- own four columns are untouched by the key going away — a row that survived
-- with its label or strength cleared would render last month as blanks.
select is(
  (select c.label || '/' || c.form || '/' || c.ledger || '/' || c.mg::text
     from public.check_ins c join orphaned o on c.id = o.id),
  'Doomed/pouch/source/6.00',
  'the snapshot itself is untouched by the key being deleted'
);

-- RLS on the log itself. The client filters by user_id as well, but a mutation
-- dropping that filter still passes every client-side test — the policy is
-- what is actually holding, and this is the only place that can be shown.

select is(
  pg_temp.as_user('11111111-1111-1111-1111-111111111111',
                  'select * from public.check_ins'),
  1,
  'a user reads their own log'
);

select is(
  pg_temp.as_user('22222222-2222-2222-2222-222222222222',
                  'select * from public.check_ins'),
  0,
  'a stranger reads none of it'
);

select throws_ok(
  $$select pg_temp.as_user('22222222-2222-2222-2222-222222222222',
      $q$insert into public.check_ins (user_id, logged_on, ledger, label, form, mg)
         values ('11111111-1111-1111-1111-111111111111', current_date, 'source', 'X', 'pouch', 6)$q$)$$,
  '42501',
  null,
  'a stranger cannot log on somebody else''s behalf'
);

-- MARK: an urge that passed — a check-in worth nothing
--
-- This replaces a test that asserted the opposite, and named its own
-- obsolescence while doing it: "an entry worth nothing is refused — which the
-- board's own zero-mg key will hit". It did. `mg > 0` was right while every row
-- was a thing taken; the craving screen's "It passed — count it" is the first
-- row that is not.
--
-- Placed after the reads above rather than beside them, because those count the
-- log and an extra row would move their answers.
-- `form` stays a word this build already knows. The column has no check
-- constraint, but `StoredCheckIn.form` decodes into a closed enum, and the read
-- decodes an *array* — so one unfamiliar value there made a whole day
-- unreadable. What the craving screen calls an urge is its decision to make;
-- this migration only has to let the row exist.
create function pg_temp.records_mg(
  amount numeric, key bigint default null, name text default 'Urge passed'
) returns boolean as $$
begin
  insert into public.check_ins
    (user_id, pad_key_id, logged_on, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', key, current_date,
          'treatment', name, 'other', amount);
  return true;
exception when check_violation then
  return false;
end;
$$ language plpgsql;

select ok(pg_temp.records_mg(0), 'an urge that passed is a check-in at zero');
select ok(not pg_temp.records_mg(-1), 'a negative dose is still refused');

-- The other half of the relaxation: zero is for a row that tapped nothing, and
-- a product logged at nought milligrams is still not an event.
create temporary table a_real_key as
with inserted as (
  insert into public.pad_keys (user_id, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', 'source', 'Pouches', 'pouch', 6)
  returning id
)
select id from inserted;

select ok(
  not pg_temp.records_mg(0, (select id from a_real_key)),
  'zero of something on the pad is still refused'
);

-- Labelled apart, or it would land in the sum below that asks what urges cost.
select ok(
  pg_temp.records_mg(6, (select id from a_real_key), 'Pouches'),
  'and a real dose against that same key still goes in'
);

-- It needs nothing on the pad to point at: `pad_key_id` is provenance, and
-- nullable, so an urge can be recorded against no key at all.
select is(
  (select count(*)::int from public.check_ins
    where label = 'Urge passed' and pad_key_id is null),
  1,
  'an urge is recorded without a pad key'
);

-- And it costs the day nothing, which is the whole point of letting it through.
select is(
  (select coalesce(sum(mg * quantity), 0)::numeric from public.check_ins
    where label = 'Urge passed'),
  0::numeric,
  'a day of urges adds nothing to what was used'
);

-- MARK: plan versions — what a past day is measured against

select has_table('public', 'taper_plan_versions', 'the plan is versioned');

-- The backfill, re-run rather than observed. `db reset` applies the migration
-- to an empty database, so the historical run had no plans to copy and there is
-- nothing left behind to assert on. What can be checked is the statement: given
-- a plan with no version, it makes one — which is the property anyone who
-- onboarded before today depends on, since otherwise their log has no ceiling
-- for any day before their next save.
select lives_ok(
  $$insert into public.taper_plan_versions (
      user_id, effective_from, starting_cap_mg, current_cap_mg,
      quit_date, first_use_minutes, sick_in_bed
    )
    select user_id, cap_effective_from, starting_cap_mg, current_cap_mg,
           quit_date, first_use_minutes, sick_in_bed
    from public.taper_plans
    on conflict (user_id, effective_from) do nothing$$,
  'the backfill runs against the plans that exist'
);

select is(
  (select count(*)::int from public.taper_plan_versions v
    join public.taper_plans p
      on p.user_id = v.user_id and p.cap_effective_from = v.effective_from),
  (select count(*)::int from public.taper_plans),
  'every plan has a version dated from the cap it is living under'
);

select is(
  pg_temp.as_user('11111111-1111-1111-1111-111111111111',
    $q$insert into public.taper_plan_versions
         (user_id, effective_from, starting_cap_mg, current_cap_mg, quit_date,
          first_use_minutes, sick_in_bed)
       values ('11111111-1111-1111-1111-111111111111', current_date - 30, 24, 24,
               null, 20, true)$q$),
  1,
  'a version can be recorded for a day in the past'
);

-- The whole point of the table: a second version, later, that does not disturb
-- the first. A day before the change still has the plan it was lived under.
select is(
  pg_temp.as_user('11111111-1111-1111-1111-111111111111',
    $q$insert into public.taper_plan_versions
         (user_id, effective_from, starting_cap_mg, current_cap_mg, quit_date,
          first_use_minutes, sick_in_bed)
       values ('11111111-1111-1111-1111-111111111111', current_date - 10, 24, 18,
               null, 20, true)$q$),
  1,
  'a later version sits beside the earlier one rather than replacing it'
);

select is(
  (select current_cap_mg::numeric from public.taper_plan_versions
    where user_id = '11111111-1111-1111-1111-111111111111'
      and effective_from <= current_date - 20
    order by effective_from desc limit 1),
  24::numeric,
  'a day twenty days ago still reads the cap it was lived under'
);

select is(
  (select current_cap_mg::numeric from public.taper_plan_versions
    where user_id = '11111111-1111-1111-1111-111111111111'
      and effective_from <= current_date - 5
    order by effective_from desc limit 1),
  18::numeric,
  'a day five days ago reads the version that started ten days ago'
);

-- Saving twice in an afternoon is a correction, not a second version.
select throws_ok(
  $$select pg_temp.as_user('11111111-1111-1111-1111-111111111111',
      $q$insert into public.taper_plan_versions
           (user_id, effective_from, starting_cap_mg, current_cap_mg, first_use_minutes)
         values ('11111111-1111-1111-1111-111111111111', current_date - 10, 24, 12, 20)$q$)$$,
  '23505',
  null,
  'two versions cannot share a start date'
);

select is(
  pg_temp.as_user('11111111-1111-1111-1111-111111111111',
    $q$update public.taper_plan_versions set current_cap_mg = 12
       where effective_from = current_date - 10$q$),
  1,
  'the day''s version can be corrected in place instead'
);

-- The two rules no client-side test can reach.
select is(
  pg_temp.as_user('22222222-2222-2222-2222-222222222222',
                  'select * from public.taper_plan_versions'),
  0,
  'a stranger reads none of it'
);

select throws_ok(
  $$select pg_temp.as_user('22222222-2222-2222-2222-222222222222',
      $q$insert into public.taper_plan_versions
           (user_id, effective_from, starting_cap_mg, current_cap_mg, first_use_minutes)
         values ('11111111-1111-1111-1111-111111111111', current_date - 1, 24, 18, 20)$q$)$$,
  '42501',
  null,
  'a stranger cannot version somebody else''s plan'
);

-- Removing a key is the one write in this app that cannot be undone, so the
-- rule that it is *yours* to remove is worth stating here rather than trusting
-- to a client filter. The app filters by user id as well, but a query that is
-- only safe because of a policy breaks silently the day the policy is loosened.
--
-- The probe below is deliberately unqualified, and the assertion before it is
-- what makes that safe. Naming the row instead is the obvious move and it
-- costs the test its point: a `delete ... where id = N` has to *read* the row,
-- so the select policy hides it and the delete answers 0 whatever the delete
-- policy says. Driven both ways — with the delete policy loosened to
-- `using (true)`, the unqualified probe fails and the id-scoped one passes.
--
-- What the unqualified form risks is answering 0 because user 2 simply owns
-- nothing, which would be a silent pass for the wrong reason the day this file
-- gives user 2 a pad. So that precondition is asserted rather than assumed: if
-- it stops holding, this fails loudly and names why.
select is(
  (select count(*)::int from public.pad_keys
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'the stranger owns no keys, so a refused delete is the only way to answer none'
);

create temporary table doomed_key as
with inserted as (
  insert into public.pad_keys (user_id, ledger, label, form, mg)
  values ('11111111-1111-1111-1111-111111111111', 'source', 'Not yours', 'pouch', 6)
  returning id
)
select id from inserted;

select is(
  pg_temp.as_user('22222222-2222-2222-2222-222222222222',
                  $$delete from public.pad_keys$$),
  0,
  'a stranger removes none of somebody else''s keys'
);

select is(
  (select count(*)::int from public.pad_keys where id = (select id from doomed_key)),
  1,
  'the key a stranger tried to remove is still there'
);

select is(
  pg_temp.as_user(
    '11111111-1111-1111-1111-111111111111',
    format('delete from public.pad_keys where id = %s', (select id from doomed_key))
  ),
  1,
  'its owner can remove it'
);

-- Grants, asserted as an exact set rather than a floor.
--
-- The privileges a table holds are not what its migration granted: Supabase's
-- default privileges hand `arwdDxtm` to both client roles before any migration
-- runs, and a `grant` cannot take that back. Local and hosted had drifted apart
-- because of it — hosted granted `authenticated` delete on every table, local
-- never did — and the suite could not see the difference, because it only ever
-- ran against local.
--
-- So these compare the whole set. `has_table_privilege` would pass on a table
-- holding every privilege in Postgres; what matters here is what is *absent*,
-- and truncate above all: RLS does not govern it, so the privilege alone empties
-- every user's rows at once.
create or replace function pg_temp.privs(tbl text, role_name text)
returns text language sql as $$
  select coalesce(string_agg(privilege_type, ',' order by privilege_type), 'none')
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = tbl and grantee = role_name;
$$;

select is(pg_temp.privs('taper_plans', 'authenticated'), 'INSERT,SELECT,UPDATE',
          'a plan is corrected in place, never deleted or truncated');
select is(pg_temp.privs('taper_plan_versions', 'authenticated'), 'INSERT,SELECT,UPDATE',
          'a version is what a past day was measured against, so it cannot be removed');
select is(pg_temp.privs('pad_keys', 'authenticated'), 'DELETE,INSERT,SELECT,UPDATE',
          'a key can be taken off the pad, but the table cannot be emptied');
select is(pg_temp.privs('check_ins', 'authenticated'), 'DELETE,INSERT,SELECT,UPDATE',
          'a check-in can be taken back, but the table cannot be emptied');

-- `anon` is the role before a sign-in. No policy on these tables names it, and
-- it kept truncate for as long as it kept anything.
select is(pg_temp.privs('taper_plans', 'anon'), 'none', 'anon holds nothing on plans');
select is(pg_temp.privs('taper_plan_versions', 'anon'), 'none', 'anon holds nothing on versions');
select is(pg_temp.privs('pad_keys', 'anon'), 'none', 'anon holds nothing on pad keys');
select is(pg_temp.privs('check_ins', 'anon'), 'none', 'anon holds nothing on check-ins');

-- The daily check-in table, driven the same four ways.

select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  insert into public.craving_ratings (user_id, logged_on, rating)
  values ('11111111-1111-1111-1111-111111111111', '2026-08-26', 'rough')
$$), 1, 'a user can rate their own day');

select throws_like(
  $$ select pg_temp.as_user('11111111-1111-1111-1111-111111111111', $q$
       insert into public.craving_ratings (user_id, logged_on, rating)
       values ('11111111-1111-1111-1111-111111111111', '2026-08-26', 'fine')
     $q$) $$,
  '%craving_ratings_rating_check%',
  'the rating vocabulary is closed: easy, so_so, rough and nothing else');

select throws_like(
  $$ select pg_temp.as_user('11111111-1111-1111-1111-111111111111', $q$
       insert into public.craving_ratings (user_id, logged_on, rating)
       values ('11111111-1111-1111-1111-111111111111', '2026-08-26', 'easy')
     $q$) $$,
  '%craving_ratings_user_id_logged_on_key%',
  'one judgement per day: a second answer is an update, never a second row');

select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  insert into public.craving_ratings (user_id, logged_on, rating)
  values ('11111111-1111-1111-1111-111111111111', '2026-08-26', 'easy')
  on conflict (user_id, logged_on)
  do update set rating = excluded.rating
$$), 1, 'the upsert path lands a changed mind on the same row');

select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  select * from public.craving_ratings where rating = 'easy'
$$), 1, 'and what is stored afterwards is the changed mind, not the first answer');

select throws_like(
  $$ select pg_temp.as_user('22222222-2222-2222-2222-222222222222', $q$
       insert into public.craving_ratings (user_id, logged_on, rating)
       values ('11111111-1111-1111-1111-111111111111', '2026-08-26', 'easy')
     $q$) $$,
  '%row-level security%',
  'nobody can rate a day on someone else''s behalf');

select is(pg_temp.as_user('22222222-2222-2222-2222-222222222222', $$
  select * from public.craving_ratings
$$), 0, 'one user''s ratings are invisible to another');

select is(pg_temp.as_user('22222222-2222-2222-2222-222222222222', $$
  delete from public.craving_ratings
$$), 0, 'and undeletable by them — the probe is unqualified so the DELETE policy answers');

select is(pg_temp.privs('craving_ratings', 'authenticated'), 'DELETE,INSERT,SELECT,UPDATE',
          'skip freely includes un-answering, but the table cannot be emptied');
select is(pg_temp.privs('craving_ratings', 'anon'), 'none', 'anon holds nothing on ratings');

-- `request_id`: the duplicate no client can close.

select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  insert into public.check_ins
    (user_id, pad_key_id, logged_on, ledger, label, form, mg, quantity, request_id)
  values ('11111111-1111-1111-1111-111111111111', null, '2026-08-27',
          'treatment', 'Lozenge', 'lozenge', 4, 1,
          '33333333-3333-3333-3333-333333333333')
$$), 1, 'a write can name the intent it belongs to');

select throws_like(
  $$ select pg_temp.as_user('11111111-1111-1111-1111-111111111111', $q$
       insert into public.check_ins
         (user_id, pad_key_id, logged_on, ledger, label, form, mg, quantity, request_id)
       values ('11111111-1111-1111-1111-111111111111', null, '2026-08-27',
               'treatment', 'Lozenge', 'lozenge', 4, 1,
               '33333333-3333-3333-3333-333333333333')
     $q$) $$,
  '%check_ins_user_request_idx%',
  'the same intent cannot be written twice — the commit that lost its response');

-- Rows that predate the column still work: nulls are distinct in a unique
-- index, so any number of rows may name no intent. Two of them here — a
-- `not null` unique would have refused the second. This is also why the index
-- needs no `where` predicate, and it must not have one: `on conflict` cannot
-- infer a partial index without repeating it, which is a thing only a live
-- write can discover. These inserts would pass either way.
select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  insert into public.check_ins
    (user_id, pad_key_id, logged_on, ledger, label, form, mg, quantity)
  values ('11111111-1111-1111-1111-111111111111', null, '2026-08-27',
          'treatment', 'Lozenge', 'lozenge', 4, 1),
         ('11111111-1111-1111-1111-111111111111', null, '2026-08-27',
          'treatment', 'Lozenge', 'lozenge', 4, 1)
$$), 2, 'rows naming no intent are not made to name a distinct one');

-- Scoped by user: the constraint says an intent belongs to whoever formed it.
select is(pg_temp.as_user('22222222-2222-2222-2222-222222222222', $$
  insert into public.check_ins
    (user_id, pad_key_id, logged_on, ledger, label, form, mg, quantity, request_id)
  values ('22222222-2222-2222-2222-222222222222', null, '2026-08-27',
          'source', 'Pouches', 'pouch', 6, 1,
          '33333333-3333-3333-3333-333333333333')
$$), 1, 'one user''s intent id does not collide with another''s');

select is(pg_temp.as_user('11111111-1111-1111-1111-111111111111', $$
  select * from public.check_ins where request_id is not null
$$), 1, 'and neither user can see the other''s');

select * from finish();
rollback;
