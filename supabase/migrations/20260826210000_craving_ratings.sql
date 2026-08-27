-- The daily check-in: "How were cravings today?"
--
-- One word per user per day — easy, so_so or rough — and its own table rather
-- than a column on `check_ins`, because the two answer different questions.
-- A check-in is an event with a timestamp and a dose; this is a judgement
-- about the whole day, and hanging it on any one row would tie it to an event
-- that might be deleted, or not exist at all on the day that was rough
-- *because* nothing was logged.
--
-- The board's card says "Optional — skip freely", so absence is the default
-- state and means nothing. No row is "skipped"; there is no word for skipped,
-- because recording the absence of an answer would turn skipping into a thing
-- the user did.
create table public.craving_ratings (
  id bigint generated always as identity primary key,

  user_id uuid not null references auth.users (id) on delete cascade,

  -- The reader's local date, for `check_ins.logged_on`'s reason: "today" in
  -- UTC is yesterday for a good part of the world.
  logged_on date not null,
  created_at timestamptz not null default now(),

  -- The board's three words. `so_so` rather than "so-so" because this is a
  -- wire token, not copy — the hyphen belongs to the screen that draws it.
  rating text not null check (rating in ('easy', 'so_so', 'rough')),

  -- One judgement per day. Changing your mind is an update, not a second row —
  -- the client upserts on this — and two answers about one day is exactly the
  -- shape this constraint exists to refuse.
  unique (user_id, logged_on)
);

-- The unique constraint above already indexes (user_id, logged_on), which is
-- also the RLS predicate and the only read: no second index needed.

alter table public.craving_ratings enable row level security;

create policy "craving ratings are readable by their owner"
  on public.craving_ratings for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "craving ratings are insertable by their owner"
  on public.craving_ratings for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Update, because the upsert path is how a changed mind lands.
create policy "craving ratings are updatable by their owner"
  on public.craving_ratings for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Delete, because "skip freely" has to include un-answering: an optional
-- question whose answer cannot be taken back is not optional.
create policy "craving ratings are deletable by their owner"
  on public.craving_ratings for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Stated the way narrow_table_grants states every table's: revoke the
-- defaults, then grant exactly what the policies cover. Nothing to `anon` —
-- the public key must not read anyone's log.
revoke all on public.craving_ratings from anon, authenticated;
grant select, insert, update, delete on public.craving_ratings to authenticated;
