-- Versions of the plan, so a past day can be read against the plan that was in
-- force on it rather than the one in force now.
--
-- `taper_plans` holds one row per person and is upserted. That is right for
-- "what am I living under today" and wrong for every question about a day that
-- has already happened: the log draws each past day's meter against that day's
-- ceiling, and recomputing it from the current row would restate last week
-- under this week's answers. `check_ins` already refuses to do that — it keeps
-- a snapshot rather than a reference, so correcting a key's strength cannot
-- rewrite last Tuesday. This is the same rule applied to the cap.
--
-- **A period is not a cap.** The ceiling steps down every week without any row
-- changing, because the schedule is derived rather than stored. So a version
-- freezes the whole set of inputs the planner reads, and any day's cap is
-- recomputed from the version covering it. Storing the realised daily number
-- instead would need something to write a row a day, and a tracker that
-- silently stops writing them is a cap that lies.
create table public.taper_plan_versions (
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- The day this version took effect, in the reader's own local date — the
  -- same convention `check_ins.logged_on` uses, and for the same reason: a
  -- plan saved at 11pm in California belongs to that day, not to tomorrow.
  effective_from date not null,

  -- The inputs the planner needs, frozen. Names match `taper_plans` so the two
  -- can be read side by side without a translation table in someone's head.
  starting_cap_mg numeric(6, 2) not null check (starting_cap_mg > 0),
  -- `>= 0`, matching what `taper_plans` was corrected to and not what it was
  -- created with. Zero is the number the whole plan descends toward — the quit
  -- week is exactly when the cap is zero — so a strict check here would refuse
  -- to version the plan of anyone who reached their goal. That is the defect
  -- `allow_zero_current_cap` fixed on the other table, reintroduced here by
  -- copying the original definition rather than the current one, and caught by
  -- driving the migration rather than by reading it.
  current_cap_mg numeric(6, 2) not null check (current_cap_mg >= 0),
  quit_date date,
  first_use_minutes integer,
  sick_in_bed boolean,

  created_at timestamptz not null default now(),

  -- One version per person per day. Saving twice in an afternoon is a
  -- correction, not a second version — and two versions sharing a start date
  -- would make "which plan was in force" unanswerable on exactly the day
  -- somebody was fiddling with it.
  constraint taper_plan_versions_one_per_day unique (user_id, effective_from),

  constraint taper_plan_versions_quit_date_after_start
    check (quit_date is null or quit_date >= effective_from)
);

-- The read is always "the latest version at or before this date", for one
-- user. Descending so that read is an index scan stopping at the first row.
create index taper_plan_versions_by_day
  on public.taper_plan_versions (user_id, effective_from desc);

alter table public.taper_plan_versions enable row level security;

-- `(select auth.uid())` so it is evaluated once per statement rather than once
-- per row, and scoped to `authenticated`, which is what an anonymous sign-in
-- is — every user in this project is one.
create policy "plan versions are readable by their owner"
  on public.taper_plan_versions for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "plan versions are insertable by their owner"
  on public.taper_plan_versions for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Updatable so that saving twice on one day corrects that day's version rather
-- than being refused by the unique constraint above.
create policy "plan versions are updatable by their owner"
  on public.taper_plan_versions for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Deliberately no delete policy. A version is what a past day was measured
-- against; removing one would leave days in the log with no ceiling to draw
-- against, and the row is small enough that keeping it costs nothing. The
-- cascade on `user_id` still removes everything if the account goes.

-- Table privileges, which RLS does not confer — the same trap `taper_core`
-- documents and this migration fell into anyway on its first run: correct
-- policies with no grant answer every query with "permission denied".
--
-- Granted to match the policies above: no delete, because there is no delete
-- policy.
grant select, insert, update on public.taper_plan_versions to authenticated;

-- Every plan that already exists becomes its own first version, dated from the
-- cap it is currently living under. Without this, anyone who onboarded before
-- today would have a log with no ceiling for any day before their next save.
insert into public.taper_plan_versions (
  user_id, effective_from, starting_cap_mg, current_cap_mg,
  quit_date, first_use_minutes, sick_in_bed
)
select
  user_id, cap_effective_from, starting_cap_mg, current_cap_mg,
  quit_date, first_use_minutes, sick_in_bed
from public.taper_plans
on conflict (user_id, effective_from) do nothing;
