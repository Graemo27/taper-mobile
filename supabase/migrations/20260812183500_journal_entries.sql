-- The journal: one row per food logged, per day.
--
-- Entries are a snapshot, not a reference. FDC revises its data, and a record
-- of what someone ate on a Tuesday must not change afterwards because the USDA
-- restated a figure. That is also why the Journal can render without a lookup.

create table public.journal_entries (
  -- Identity rather than a random uuid: these insert in time order, and a v4
  -- uuid would scatter them across the index for no benefit here.
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- The reader's local date, supplied by the client. Deriving it here would
  -- use the server's clock, and "today" in UTC is yesterday for a good part of
  -- the world — logging dinner in California would land on tomorrow's page.
  eaten_on date not null,
  created_at timestamptz not null default now(),

  -- What was eaten. `fdc_id` is kept for provenance, not for re-fetching.
  fdc_id integer not null,
  name text not null,
  serving_label text,
  servings smallint not null check (servings between 1 and 20),
  grams numeric(10, 2),

  -- Nulls are FDC gaps, never zeroes, exactly as in the app.
  kcal integer,
  protein_g numeric(10, 1),
  fibre_g numeric(10, 1)
);

-- Covers the RLS predicate and the Journal's own query, which reads one
-- person's entries newest day first.
create index journal_entries_user_day_idx
  on public.journal_entries (user_id, eaten_on desc);

alter table public.journal_entries enable row level security;

-- `(select auth.uid())` rather than a bare call: the subquery is evaluated once
-- per statement instead of once per row.
--
-- Scoped to `authenticated`, which includes anonymous sign-ins — they are real
-- users in auth.users carrying an is_anonymous claim, so they own their rows on
-- the same terms as anyone else.
create policy "journal entries are readable by their owner"
  on public.journal_entries for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "journal entries are insertable by their owner"
  on public.journal_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "journal entries are deletable by their owner"
  on public.journal_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

-- No update policy. Nothing in the app edits an entry — the Journal removes and
-- re-adds — so the privilege is left ungranted rather than written and unused.
