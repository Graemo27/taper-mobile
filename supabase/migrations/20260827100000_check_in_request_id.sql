-- Close the duplicate no client can.
--
-- Every other double-write in this app is guarded on the client: a button that
-- refuses a second tap, a status that goes terminal, a screen that will not
-- dismiss mid-write. None of them can see the one that matters — an insert
-- that *commits* and then loses its response. The client is told the write
-- failed, because from where it stands the write did fail; the row exists
-- anyway. Retry, honestly, and the day has two of them.
--
-- So the identity of a write has to be decided by the writer, before it is
-- sent, and carried with it. `request_id` is that: the same intent retried
-- carries the same id, and the second arrival conflicts with the first
-- instead of joining it.
--
-- Nullable. Every row written before this migration has no id and never will;
-- a `not null` would need a backfill of invented ids, fabricating provenance
-- for rows whose write is long finished.
--
-- What makes that safe is Postgres treating nulls as distinct in a unique
-- index: any number of rows may name no intent.
--
-- Not partial, though a `where request_id is not null` would be the tidier
-- index and was the first draft. `on conflict` can only infer a partial index
-- if the statement repeats its predicate, which PostgREST has no way to send —
-- so the upsert this column exists to enable failed against it with 42P10.
-- The predicate bought a smaller index and cost the feature. It is gone, and
-- the live write test is what found that: pgTAP inserts directly and never
-- exercises the inference, so the whole suite passed either way.
--
-- Scoped by user, not global. Two anonymous accounts generating the same UUID
-- is not a thing worth designing for, but scoping costs nothing and makes the
-- constraint say what it means: an intent belongs to whoever formed it. It
-- also matches the RLS predicate and the read index, so the column joins the
-- shape the table already has.
alter table public.check_ins
  add column request_id uuid;

create unique index check_ins_user_request_idx
  on public.check_ins (user_id, request_id);

comment on column public.check_ins.request_id is
  'Client-chosen identity for one write intent. The same intent retried carries the same id, so a commit whose response was lost cannot be inserted twice. Null on every row written before the column existed.';
