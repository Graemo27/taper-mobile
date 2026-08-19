-- Let the current cap reach zero.
--
-- `taper_plans.current_cap_mg` was created with `check (current_cap_mg > 0)`,
-- written on the assumption that a ceiling of nothing is meaningless. It is the
-- opposite: zero is the number the whole plan descends toward, and the quit week
-- is exactly when the cap is zero. As shipped, every plan with a quit date would
-- have failed to persist on reaching its goal — the one moment that matters.
--
-- Caught by the plan generator, whose descent ends at zero by construction, and
-- confirmed against this schema before the fix: inserting a plan with
-- current_cap_mg = 0 raised check_violation.
--
-- `starting_cap_mg > 0` deliberately keeps its strict form. A plan that begins
-- at zero has nothing to taper and is a data-entry error, where a plan that
-- *ends* at zero has succeeded.

alter table public.taper_plans
  drop constraint if exists taper_plans_current_cap_mg_check;

alter table public.taper_plans
  add constraint taper_plans_current_cap_not_negative
  check (current_cap_mg >= 0);
