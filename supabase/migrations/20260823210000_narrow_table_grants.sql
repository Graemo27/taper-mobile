-- Say what each role may do, instead of inheriting it.
--
-- Every table above granted the privileges its policies needed, and every table
-- got more than that anyway. Supabase configures the project with
-- `alter default privileges in schema public grant all on tables to anon,
-- authenticated, service_role`, so a new table arrives holding `arwdDxtm` for
-- both client roles before any migration of ours runs. A `grant` cannot take
-- that back — it only adds — so `taper_plan_versions` shipped with the comment
-- "no delete, because there is no delete policy" above a table that granted
-- delete regardless.
--
-- Two things came of that, and only the second is a hole.
--
-- **Delete was never open.** RLS refuses a command with no permissive policy
-- for it, so `taper_plans` and `taper_plan_versions` denied deletes on the
-- policy even where the grant allowed them. That half was belt-and-braces with
-- one strap missing, not an exposure.
--
-- **Truncate was.** ⚠️ `truncate` is not a row operation and RLS does not see
-- it: a role holding the privilege empties the whole table, every user's rows
-- at once, whatever the policies say. Driven against the local database as
-- `authenticated`, `delete` was refused and `truncate` returned TRUNCATE TABLE
-- and left zero rows. PostgREST never issues it — there is no REST verb that
-- maps to truncate, so nothing the app can send reaches this — but "no route
-- exposes it today" is a property of the client, and this file is about what
-- the database permits. It is also the one privilege that can bulk-delete rows
-- in a project where every user is anonymous and nothing can be reconstructed.
--
-- `anon` is stripped entirely rather than narrowed. It is the role before a
-- sign-in, no policy on any of these tables names it, and `nrt-search` refuses
-- a request that carries the anon key instead of a user session. It needs
-- nothing here, so it gets nothing — which also removes its truncate.
--
-- Idempotent: `revoke` on a privilege already absent is a no-op, so this is
-- safe to re-run and safe on both a database that inherited the defaults and
-- one that did not. Local and hosted had diverged — local never granted delete
-- to `authenticated`, hosted granted everything — and after this they agree,
-- which is the point. `taper_core_test.sql` asserts the exact set so the two
-- cannot drift apart again unnoticed.
--
-- Deliberately not touching `alter default privileges` itself. Rewriting the
-- project's defaults would change how every future table in `public` is
-- created, including any Supabase creates for its own features, and the
-- blast radius of getting that wrong is larger than the thing being fixed.
-- Each table states its own grants; the test is what stops a new one being
-- forgotten.

revoke all on public.taper_plans from anon, authenticated;
revoke all on public.taper_plan_versions from anon, authenticated;
revoke all on public.pad_keys from anon, authenticated;
revoke all on public.check_ins from anon, authenticated;

-- Re-granted to match the policies each table actually has, and nothing else.

-- No delete: a plan is corrected in place, never removed.
grant select, insert, update on public.taper_plans to authenticated;

-- No delete: a version is what a past day was measured against, so removing
-- one would leave days in the log with no ceiling to draw against.
grant select, insert, update on public.taper_plan_versions to authenticated;

-- Delete, because a key can be taken off the pad.
grant select, insert, update, delete on public.pad_keys to authenticated;

-- Delete, because a check-in can be taken back off the day.
grant select, insert, update, delete on public.check_ins to authenticated;
