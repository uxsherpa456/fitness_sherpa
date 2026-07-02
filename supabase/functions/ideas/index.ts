// deno-lint-ignore-file no-explicit-any
//
// ideas — the product-idea ledger Hugin writes to while coaching.
// Hugin sees all of the athlete's data, so mid-conversation he surfaces things the app *should*
// do but can't yet. The coach function's `log_idea` tool posts them here; every idea gets a
// stable reference id (RAVN-<n>) the builder can hand to a coding agent ("build RAVN-12").
// Same self-bootstrapping pattern as `state` — no migration or dashboard step needed.
//
// Deploy:   supabase functions deploy ideas --no-verify-jwt
// Endpoint: https://<project-ref>.supabase.co/functions/v1/ideas
//
// Contract:
//   POST { action:"log", title, detail, context?, source? } -> { ok, ref }
//   POST { action:"get", ref }                              -> { ok, idea }
//   POST { action:"list", status? }                         -> { ok, ideas: [...] }
//   POST { action:"update", ref, status }                   -> { ok }   (proposed|building|built|dropped)

import { corsHeaders } from "../_shared/cors.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.5/mod.js";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false });

let ready: Promise<unknown> | null = null;
function ensure() {
  if (!ready) {
    ready = sql`
      create table if not exists public.app_ideas (
        id         serial      primary key,
        title      text        not null,
        detail     text        not null default '',
        context    jsonb       not null default '{}'::jsonb,
        source     text        not null default 'hugin',
        status     text        not null default 'proposed',
        user_key   text        not null default 'ryan',
        created_at timestamptz not null default now()
      )
    `;
  }
  return ready;
}

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const refOf = (id: number) => `RAVN-${id}`;
const idOf = (ref: string) => Number(String(ref).replace(/[^0-9]/g, ""));

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    await ensure();
    const body = await req.json().catch(() => ({} as any));

    if (body.action === "log") {
      const title = String(body.title ?? "").slice(0, 200).trim();
      if (!title) return json({ ok: false, error: "title required" }, 400);
      const detail = String(body.detail ?? "").slice(0, 4000);
      const source = String(body.source ?? "hugin").slice(0, 32);
      const userKey = String(body.user_key ?? "ryan").slice(0, 128);
      const context = body.context ?? {};
      const rows = await sql`
        insert into public.app_ideas (title, detail, context, source, user_key)
        values (${title}, ${detail}, ${JSON.stringify(context)}::jsonb, ${source}, ${userKey})
        returning id
      `;
      return json({ ok: true, ref: refOf(rows[0].id) });
    }

    if (body.action === "get") {
      const id = idOf(body.ref ?? "");
      if (!id) return json({ ok: false, error: "ref required" }, 400);
      const rows = await sql`select * from public.app_ideas where id = ${id}`;
      if (!rows.length) return json({ ok: false, error: "not found" }, 404);
      const r = rows[0];
      return json({ ok: true, idea: { ...r, ref: refOf(r.id) } });
    }

    if (body.action === "list") {
      const rows = body.status
        ? await sql`select * from public.app_ideas where status = ${String(body.status)} order by id desc limit 100`
        : await sql`select * from public.app_ideas order by id desc limit 100`;
      return json({ ok: true, ideas: rows.map((r: any) => ({ ...r, ref: refOf(r.id) })) });
    }

    if (body.action === "update") {
      const id = idOf(body.ref ?? "");
      const status = String(body.status ?? "").slice(0, 32);
      if (!id || !["proposed", "building", "built", "dropped"].includes(status)) {
        return json({ ok: false, error: "ref + valid status required" }, 400);
      }
      await sql`update public.app_ideas set status = ${status} where id = ${id}`;
      return json({ ok: true });
    }

    return json({ ok: false, error: "unknown action" }, 400);
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});
