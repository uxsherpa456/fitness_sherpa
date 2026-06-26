// deno-lint-ignore-file no-explicit-any
//
// state — tiny persistence backend for the HYROX prototype.
// Mirrors the prototype's localStorage (onboarded / profile / goals / settings) into Postgres so
// the data survives a browser wipe, carries across devices, and gives the native app a real table
// to sync against. Self-bootstraps its table on first call — no migration or dashboard step needed.
//
// Deploy:   supabase functions deploy state --no-verify-jwt
// Endpoint: https://<project-ref>.supabase.co/functions/v1/state
// Uses the auto-injected SUPABASE_DB_URL — there are no secrets to set.
//
// Contract (same open posture as `coach`, deployed --no-verify-jwt):
//   POST { action:"load", user_key }                          -> { onboarded, profile, goals, settings, updated_at }
//   POST { action:"save", user_key, onboarded, profile, goals, settings } -> { ok:true }

import { corsHeaders } from "../_shared/cors.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.5/mod.js";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false });

// create the table once per cold start (CREATE TABLE IF NOT EXISTS is idempotent)
let ready: Promise<unknown> | null = null;
function ensure() {
  if (!ready) {
    ready = sql`
      create table if not exists public.app_state (
        user_key   text        primary key,
        onboarded  boolean     not null default false,
        profile    jsonb       not null default '{}'::jsonb,
        goals      jsonb       not null default '[]'::jsonb,
        settings   jsonb       not null default '{}'::jsonb,
        updated_at timestamptz not null default now()
      )
    `;
  }
  return ready;
}

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    await ensure();
    const body = await req.json().catch(() => ({} as any));
    const key = String(body.user_key ?? "ryan").slice(0, 128);

    if (body.action === "save") {
      await sql`
        insert into public.app_state (user_key, onboarded, profile, goals, settings, updated_at)
        values (${key}, ${!!body.onboarded}, ${sql.json(body.profile ?? {})},
                ${sql.json(body.goals ?? [])}, ${sql.json(body.settings ?? {})}, now())
        on conflict (user_key) do update set
          onboarded  = excluded.onboarded,
          profile    = excluded.profile,
          goals      = excluded.goals,
          settings   = excluded.settings,
          updated_at = now()
      `;
      return json({ ok: true });
    }

    // default: load
    const rows = await sql`
      select onboarded, profile, goals, settings, updated_at
      from public.app_state where user_key = ${key}
    `;
    return json(rows[0] ?? { onboarded: false, profile: {}, goals: [], settings: {}, updated_at: null });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});
