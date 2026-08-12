-- Favourites: foods someone marked, so the results list can show which ones
-- they already know they want.
--
-- Only the reference is stored, not a copy of the food. Unlike a journal entry,
-- a favourite is not a record of something that happened — it points at whatever
-- that food is now, so a USDA revision should reach it.

create table public.favourites (
  user_id uuid not null references auth.users (id) on delete cascade,
  fdc_id integer not null,
  created_at timestamptz not null default now(),

  -- Composite key rather than a surrogate: one row per person per food is the
  -- whole constraint, and a second star must not create a duplicate. It also
  -- gives the user_id-leading index the policies below need, for free.
  primary key (user_id, fdc_id)
);

alter table public.favourites enable row level security;

-- `(select auth.uid())` so it is evaluated once per statement, not per row.
-- Scoped to `authenticated`, which is what an anonymous sign-in is.
create policy "favourites are readable by their owner"
  on public.favourites for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "favourites are insertable by their owner"
  on public.favourites for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "favourites are deletable by their owner"
  on public.favourites for delete to authenticated
  using ((select auth.uid()) = user_id);

-- No update policy. A favourite is on or off, which is an insert or a delete.
