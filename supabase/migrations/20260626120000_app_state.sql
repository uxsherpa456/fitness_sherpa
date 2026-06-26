-- app_state — single-row-per-athlete mirror of the prototype's local state.
-- The `state` Edge Function self-creates this on first call; this migration records the schema
-- in the repo so the native app (SwiftData models) maps onto a known contract.
--
-- profile  : { sex, age, ... }            (Athlete demographics / division)
-- goals    : [ { key, label, unit, kind, better, start, current, goal }, ... ]  (focus-metric arcs)
-- settings : { location, goalTime, raceDate, raceLoc, weightUnit, distUnit, sex, age }

create table if not exists public.app_state (
  user_key   text        primary key,
  onboarded  boolean     not null default false,
  profile    jsonb       not null default '{}'::jsonb,
  goals      jsonb       not null default '[]'::jsonb,
  settings   jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- RLS stays ON with no policies: the anon/public roles cannot touch the table directly.
-- The `state` function reaches it via SUPABASE_DB_URL (full DB creds), bypassing RLS — the same
-- "logic lives server-side, keys never ship to the client" posture as the coach function.
alter table public.app_state enable row level security;
