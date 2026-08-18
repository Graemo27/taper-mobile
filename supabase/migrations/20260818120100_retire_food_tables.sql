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
-- taken as part of the pivot, not a cleanup.
--
-- To keep the data, dump it *before* applying. Note `supabase db dump -x` is
-- the wrong tool: `-x` means exclude, so it would save everything except the
-- two tables you were trying to save. The CLI has no include-table flag, so
-- reach for pg_dump and name them:
--
--   pg_dump "postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres" \
--     --data-only --table public.journal_entries --table public.favourites \
--     -f food-data.sql
--
-- ⚠️ Order of operations, which is not optional. Every Food Pad client that
-- reads these tables must be retired first. The iOS app still reads and writes
-- both through JournalRepository, FavouritesRepository and RecentFoodsRepository,
-- so applying this while that build is installed breaks it on every journal
-- read — including on Graem's phone, where "retire the client" means shipping
-- the replacement, not editing a file. Push this only once losing the food
-- app's function is something you have decided to accept.
--
-- `supabase db push` is a production action and needs explicit authorisation
-- from Graem regardless.
--
-- `if exists` so the migration is safe to re-run against a database where it
-- has already been applied. Policies and indexes are owned by the tables and go
-- with them; there is nothing left behind to drop separately.

drop table if exists public.favourites;

drop table if exists public.journal_entries;
