-- The taper: what someone is quitting, what they are treating it with, and the
-- plan connecting the two.
--
-- The two ledgers are the whole point of this schema. Licensed NRT is the
-- treatment; a pouch is the thing being quit. The trial closest to this
-- product's mechanic found that reduction *without* pre-quit nicotine bought
-- nothing at any timepoint, while reduction *with* it beat usual care — so a
-- schema that collapsed both into one number would make the distinction the
-- evidence turns on unrepresentable. `ledger` is a column, never a convention.

create table public.taper_plans (
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- Where the person started, in label milligrams a day. Written once from
  -- onboarding and then left alone: it is the baseline every later figure is
  -- read against, and a moving baseline would make progress unfalsifiable.
  starting_cap_mg numeric(6, 2) not null check (starting_cap_mg > 0),

  -- Today's ceiling, pinned rather than derived. The rest of the schedule is
  -- recomputed from the columns in this table, but the number someone is
  -- currently living under must not shift beneath them when the plan stretches
  -- or a dependence answer is corrected.
  current_cap_mg numeric(6, 2) not null check (current_cap_mg > 0),
  cap_effective_from date not null,

  -- Nullable deliberately. Most nicotine users are not ready to quit, and a
  -- required quit date would make the product unusable by the population it is
  -- trying to reach. Reduction with no terminal date is a supported state, not
  -- an incomplete one.
  quit_date date,

  -- The two dependence questions. Minutes to the first use of the day is the
  -- strongest single item, and both feed the dose the plan recommends: 4 mg
  -- gum beats 2 mg for dependent users and shows no clear benefit for light
  -- ones, so the recommendation cannot be one number for everybody.
  first_use_minutes smallint check (first_use_minutes between 0 and 1440),
  sick_in_bed boolean,

  created_at timestamptz not null default now(),

  -- A quit date before the plan began is a data-entry error, not a taper.
  constraint taper_plans_quit_date_after_start
    check (quit_date is null or quit_date >= cap_effective_from)
);

-- One plan per person: a second would make "the cap" ambiguous on every screen
-- that shows it. Doubles as the index the RLS predicate needs.
create unique index taper_plans_user_idx on public.taper_plans (user_id);

alter table public.taper_plans enable row level security;

-- `(select auth.uid())` so it is evaluated once per statement rather than once
-- per row, and scoped to `authenticated`, which is what an anonymous sign-in
-- is — every user in this project is one.
create policy "taper plans are readable by their owner"
  on public.taper_plans for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "taper plans are insertable by their owner"
  on public.taper_plans for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Update is granted here, unlike the food tables. The plan is meant to change:
-- being given a schedule and failing it was associated with worse outcomes than
-- never receiving one, which makes "the plan stretches with you" a clinical
-- requirement rather than a nicety, and stretching is an update.
create policy "taper plans are updatable by their owner"
  on public.taper_plans for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- No delete policy. A plan is edited or abandoned in place; nothing in the
-- design removes one, so the privilege is left ungranted rather than written
-- and unused.

-- Table privileges, which RLS does not confer.
--
-- A policy filters rows a role may already touch; it does not grant the touch.
-- Default privileges for a table created by `postgres` give `authenticated`
-- only TRUNCATE/REFERENCES/TRIGGER/MAINTAIN — no select, insert, update or
-- delete — so a table with correct policies and no grant answers every query
-- with "permission denied", which is exactly what happened the first time this
-- migration was driven. Granted explicitly rather than left to defaults,
-- because those defaults vary by project age and by who runs the migration,
-- and an ambient grant is one nobody reviews.
--
-- Granted per table to match the policies above: no delete here, because there
-- is no delete policy.
grant select, insert, update on public.taper_plans to authenticated;

-- The pad: the keys someone taps to log. Both ledgers live here, separated by a
-- column rather than by two tables, because the pad is one surface and every
-- read of it would otherwise be a union.

create table public.pad_keys (
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- 'treatment' is licensed NRT; 'source' is what the user is quitting.
  -- text with a check rather than a Postgres enum: the values are stable, and
  -- altering an enum later is a migration that cannot be cleanly reversed.
  ledger text not null check (ledger in ('treatment', 'source')),

  label text not null check (length(btrim(label)) between 1 and 60),
  form text not null,

  -- Label milligrams per unit — per piece, or per 24h for a patch. This is the
  -- number on the box, not what the body absorbs: measured extraction from
  -- commercial pouches ran 38%, 24% and 52%, so no honest conversion exists.
  mg numeric(6, 2) not null check (mg > 0),

  -- National Drug Code, from the openFDA lookup.
  ndc text check (ndc is null or length(btrim(ndc)) > 0),

  -- Pad order. Ties are broken by id, so a duplicate position is untidy rather
  -- than broken, which is why this is not unique.
  position smallint not null default 0,

  created_at timestamptz not null default now(),

  -- The NRT-only rule, expressed as a constraint rather than trusted to the
  -- API. NDCs are issued to drugs, and pouches and vapes are regulated as
  -- tobacco products, so a source key structurally cannot carry one. See the
  -- standing constraint in AGENTS.md.
  constraint pad_keys_only_treatment_has_ndc
    check (ledger = 'treatment' or ndc is null),

  -- Which forms each ledger may take. The treatment list is the same allowlist
  -- the Edge Function enforces, restated here so that a client writing directly
  -- to the table still cannot file a pouch as treatment. Two independent
  -- statements of one rule is the point, not duplication to be tidied away.
  constraint pad_keys_form_matches_ledger check (
    (ledger = 'treatment' and form in ('gum', 'lozenge', 'patch', 'inhaler', 'spray'))
    or (ledger = 'source' and form in ('pouch', 'vape', 'cigarette', 'dip', 'other'))
  )
);

-- Covers the RLS predicate and the pad's own read, which fetches one person's
-- keys grouped by ledger in display order.
create index pad_keys_user_ledger_idx on public.pad_keys (user_id, ledger, position);

alter table public.pad_keys enable row level security;

create policy "pad keys are readable by their owner"
  on public.pad_keys for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "pad keys are insertable by their owner"
  on public.pad_keys for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Editing a key — renaming it, correcting its mg, dragging it to reorder — is
-- the whole of the edit-pad screen.
create policy "pad keys are updatable by their owner"
  on public.pad_keys for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "pad keys are deletable by their owner"
  on public.pad_keys for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.pad_keys to authenticated;

-- The log: one row per check-in.

create table public.check_ins (
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- Provenance only, never read for display. Nullable and `set null` because
  -- removing a key from the pad must not remove the history of having used it —
  -- deleting "Pouch · 6 mg" should not rewrite last month's totals.
  pad_key_id bigint references public.pad_keys (id) on delete set null,

  -- The reader's local date, supplied by the client. Deriving it here would use
  -- the server's clock, and "today" in UTC is yesterday for a good part of the
  -- world: a check-in at 9pm in California would land on tomorrow's page.
  logged_on date not null,
  created_at timestamptz not null default now(),

  -- A snapshot, not a reference — the same rule the food journal followed, for
  -- the same reason. Correcting a key's strength must not silently rewrite what
  -- someone recorded last Tuesday, and the log must render without a join.
  ledger text not null check (ledger in ('treatment', 'source')),
  label text not null,
  form text not null,
  mg numeric(6, 2) not null check (mg > 0),
  quantity smallint not null default 1 check (quantity between 1 and 20)
);

-- Covers the RLS predicate and the two reads that matter: today's total, and
-- the history newest day first.
create index check_ins_user_day_idx on public.check_ins (user_id, logged_on desc);

-- Postgres does not index a foreign key automatically, and this one is walked
-- by the `on delete set null` above — without it, removing a pad key scans
-- every check-in the user has ever made.
create index check_ins_pad_key_idx on public.check_ins (pad_key_id);

alter table public.check_ins enable row level security;

create policy "check ins are readable by their owner"
  on public.check_ins for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "check ins are insertable by their owner"
  on public.check_ins for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Update is granted because the app has an edit-check-in screen. Being able to
-- correct a mis-tap matters more here than it did for food: an uncorrectable
-- log is one people stop trusting, and a log people stop trusting is one they
-- stop keeping.
create policy "check ins are updatable by their owner"
  on public.check_ins for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "check ins are deletable by their owner"
  on public.check_ins for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.check_ins to authenticated;

-- Nothing is granted to `anon`. Every user in this project is a real, if
-- anonymous, account carrying `role: "authenticated"`, so the `anon` role is
-- only ever the app's public key — and the public key must not be able to read
-- anyone's nicotine log.
