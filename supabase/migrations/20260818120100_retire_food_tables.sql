-- Retire the food schema.
--
-- Food Pad became Taper. The domain, the backend and the product are different,
-- and nothing in `journal_entries` or `favourites` is reusable as nicotine
-- data — a logged almond is not a partial check-in. Leaving them would put two
-- unrelated products' tables in one project, and every later migration and
-- security review would have to reason about tables nothing reads.
--
-- ⚠️ This deletes real rows and cannot be undone. Every user in this project is
-- anonymous, so the rows cannot be reconstructed from anywhere else, and that
-- includes the entries on Graem's phone. Retiring them is a deliberate decision
-- taken as part of the pivot, not a cleanup. If any of it is wanted, dump it
-- before applying:
--
--   supabase db dump --data-only \
--     -x public.journal_entries -x public.favourites > food-data.sql
--
-- Applying this while a Food Pad build is installed will make that build fail
-- on every journal read. That is expected during the pivot rather than a fault
-- to diagnose — the client is being replaced, not repaired.
--
-- `if exists` so the migration is safe to re-run against a database where it
-- has already been applied. Policies and indexes are owned by the tables and go
-- with them; there is nothing left behind to drop separately.

drop table if exists public.favourites;

drop table if exists public.journal_entries;
