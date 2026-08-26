-- Let a check-in record nothing consumed.
--
-- `check_ins.mg` shipped as `> 0`, which is right for everything the app could
-- log at the time: a tap on a pad key is a thing taken, and zero of it is not
-- an event. The craving screen breaks that assumption. "It passed — count it"
-- records an urge somebody rode out — real, worth keeping, and zero milligrams
-- by definition.
--
-- This is the second time this project has relaxed a `> 0` that was written
-- when only one kind of row existed; `allow_zero_current_cap` was the first,
-- for the week a plan reaches its goal. The pattern is worth naming: a check
-- that encodes "every row so far has been positive" is a check that will be
-- wrong the first time a new kind of row arrives.
--
-- Zero is allowed only for a row tied to no key, which is what keeps the old
-- invariant true where it still applies: zero of a *product* is not an event.
-- A plain `>= 0` would have accepted a nought-milligram pouch, contradicting
-- the paragraph above it.
--
-- Shaped by the row rather than by its vocabulary. `form = 'urge'` would work
-- today and put a client's word in a check constraint, where changing it later
-- is a migration; `pad_key_id is null` says the same thing about what the row
-- *is* — nothing on the pad was tapped — and stays true whatever the craving
-- screen ends up calling it.
--
-- `pad_key_id` is already nullable and already `on delete set null`, so an
-- existing row keeps satisfying this when its key is deleted: `mg > 0` carries
-- it.
--
-- Written as `mg = 0` and not as "anything not positive", because the first
-- draft of this said `mg > 0 or pad_key_id is null` and thereby accepted a
-- *negative* dose on any keyless row — the floor the old check existed to hold
-- disappeared into the second branch. Its own test caught it.
alter table public.check_ins
  drop constraint check_ins_mg_check,
  add constraint check_ins_mg_check
    check (mg > 0 or (mg = 0 and pad_key_id is null));
