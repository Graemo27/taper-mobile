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
-- Nothing else has to move. `pad_key_id` is already nullable — it is provenance
-- and never read for display — so an urge needs no key on the pad to point at,
-- and `form` carries no check constraint, so the snapshot can say what it was
-- without the enum having a case for it.
--
-- `>= 0` rather than dropping the check. A negative dose is still nonsense, and
-- the column is what stops a client bug writing one.
alter table public.check_ins
  drop constraint check_ins_mg_check,
  add constraint check_ins_mg_check check (mg >= 0);
