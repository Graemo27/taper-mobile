-- Make pad order a fact the database keeps, so it can be reordered.
--
-- `position` shipped as "untidy rather than broken": no unique index, ties
-- broken by id, and a client that read the last position and added one. Two
-- adds close enough together both read the same number and both take it. That
-- was a fair trade while position only decided which of two keys drew first.
-- It stops being fair the moment the user can *set* the order — a pad that
-- quietly disagrees with the arrangement somebody just made is worse than one
-- that never let them arrange it.
--
-- Three parts: make the existing data satisfy the rule, state the rule, and
-- take position allocation away from the client.

-- 1. Renumber what is already there.
--
-- Dense, per user and ledger, in the order the pad currently draws — position
-- then id, the same tiebreak `Pad.inDisplayOrder` uses. Anyone carrying a
-- duplicate from the race gets a stable arrangement that looks identical to
-- what they last saw; the constraint below would otherwise refuse to be added
-- at all, and failing a migration on live data is not a way to find out.
with ordered as (
  select id,
         row_number() over (
           partition by user_id, ledger order by position, id
         ) - 1 as seat
  from public.pad_keys
)
update public.pad_keys as k
   set position = ordered.seat
  from ordered
 where k.id = ordered.id
   and k.position is distinct from ordered.seat;

-- 2. State the rule.
--
-- Deferrable, and that is the whole reason this is a constraint rather than a
-- unique index: reordering passes through states where two keys share a seat,
-- and an immediately-checked constraint would refuse the middle of a swap.
-- Deferred, the check happens once at commit, by which time the arrangement
-- is whole again.
alter table public.pad_keys
  add constraint pad_keys_user_ledger_position_key
    unique (user_id, ledger, position) deferrable initially deferred;

-- 3. Take allocation away from the client.
--
-- `position` becomes nullable so a caller can decline to choose one, which is
-- what the trigger below is for. Nullable in the column, never null in a row:
-- nothing that reaches the table keeps a null.
alter table public.pad_keys
  alter column position drop not null,
  alter column position drop default;

-- The lock is the point. Without it two concurrent inserts read the same max
-- and both claim it — the original race, now surfacing as a failed write
-- rather than a duplicate, which is not an improvement for somebody adding a
-- key. Taken per user and ledger so it serialises only the rows that actually
-- compete, and held to the end of the transaction, which is where the
-- deferred constraint is checked.
create function public.place_pad_key() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.position is null then
    perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':' || new.ledger));
    select coalesce(max(position), -1) + 1 into new.position
      from public.pad_keys
     where user_id = new.user_id and ledger = new.ledger;
  end if;
  return new;
end $$;

create trigger pad_keys_place
  before insert on public.pad_keys
  for each row execute function public.place_pad_key();

-- Reordering, as one statement.
--
-- PostgREST cannot wrap several updates in a transaction, and a reorder sent
-- as N requests is N chances to leave the pad half-rearranged. This takes the
-- ids in their new order and seats them by array index.
--
-- `security invoker` deliberately: RLS still applies, so this can only move
-- rows its caller could already have updated one by one. It is a convenience
-- and a transaction, not a privilege.
--
-- The whole ledger or nothing. A partial list would leave the keys it omits
-- holding seats the listed ones now want, which the constraint would refuse at
-- commit with a message about nothing the caller did wrong.
create function public.reorder_pad_keys(key_ids bigint[])
returns setof public.pad_keys
language plpgsql security invoker set search_path = '' as $$
declare
  target_ledger text;
begin
  select ledger into target_ledger
    from public.pad_keys
   where id = any(key_ids) and user_id = (select auth.uid())
   group by ledger
  having count(*) = cardinality(key_ids);

  if target_ledger is null then
    raise exception 'reorder_pad_keys: the ids must be your own and all in one ledger';
  end if;

  if exists (
    select 1 from public.pad_keys
     where user_id = (select auth.uid()) and ledger = target_ledger
       and not (id = any(key_ids))
  ) then
    raise exception 'reorder_pad_keys: every key in the ledger must be listed';
  end if;

  return query
    update public.pad_keys as k
       set position = seat.index - 1
      from unnest(key_ids) with ordinality as seat(id, index)
     where k.id = seat.id and k.user_id = (select auth.uid())
     returning k.*;
end $$;

revoke all on function public.reorder_pad_keys(bigint[]) from public;
grant execute on function public.reorder_pad_keys(bigint[]) to authenticated;
