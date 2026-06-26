# Coach backend — Supabase Edge Function

Cloud port of `prototype/server.mjs`. Holds the Anthropic key as a secret, applies the
freshness + evidence guardrails, runs the agent loop (`recompute_diagnosis` tool), and streams
the reply (SSE). This is what the **iOS app** calls in production — no laptop required.

## Live endpoint (deployed)

```
https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/coach
```

**Status: ✅ deployed + verified live** — streams real Claude responses, cites the athlete's
numbers, enforces the freshness guardrail, and runs the `recompute_diagnosis` tool. The
`ANTHROPIC_API_KEY` secret is set. The iOS app can call this URL directly.

Deployed with `--no-verify-jwt` (callable without an anon key for now). Set the key once with
`supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref rcbjfjgffzadagndxthp`.

**Hybrid models:** chat runs on `claude-sonnet-4-6`; once `recompute_diagnosis` fires, the turn
that explains the re-diagnosis escalates to `claude-opus-4-8` (deep reasoning where it matters).
Override with the `COACH_MODEL` / `DIAGNOSIS_MODEL` secrets.
Test from the browser prototype: append
`?coach=https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/coach` to the URL.

```
supabase/functions/
├── _shared/
│   ├── cors.ts
│   ├── diagnosis.ts        # the diagnostic engine (kept in sync with the JS + Swift ports)
│   └── fuel.ts             # calorie + macro engine
├── coach/
│   └── index.ts            # POST /functions/v1/coach  — chat + agent, streamed
└── state/
    └── index.ts            # POST /functions/v1/state  — persistence (load/save), self-bootstraps its table
```

## state — persistence (deployed)

```
https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/state
```

**Status: ✅ deployed + verified** (`--no-verify-jwt`). Mirrors the prototype's local state
(`onboarded` / `profile` / `goals` / `settings`) into a single `public.app_state` row per athlete
so data survives a browser wipe, carries across devices, and gives the **native app** a real table
to sync against. Uses the auto-injected `SUPABASE_DB_URL` (full DB creds) and **self-creates its
table on first call** — no migration run or dashboard step required. Schema is recorded in
`supabase/migrations/20260626120000_app_state.sql` for the SwiftData mapping.

```
POST …/state   { "action":"load", "user_key":"ryan" }
  -> { onboarded, profile, goals, settings, updated_at }
POST …/state   { "action":"save", "user_key":"ryan", onboarded, profile, goals, settings }
  -> { "ok": true }
```

The prototype keeps `localStorage` as the instant/offline cache and mirrors every save up to this
function; on launch it pulls the durable copy (cloud wins if it has data). Single-user prototype, so
the key is the fixed string `ryan`; the native app will swap that for the authenticated user id.
Deploy: `supabase functions deploy state --no-verify-jwt`.

## Prerequisites
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase` on
  the Mac, or scoop/winget on Windows)
- A Supabase project (you already use Supabase) — grab its **project ref** from the dashboard URL

## Local dev
```bash
supabase login
supabase link --project-ref <your-project-ref>

# put the key in a local env file (NOT committed)
echo "ANTHROPIC_API_KEY=sk-ant-..." > supabase/.env.local

supabase functions serve coach --env-file supabase/.env.local --no-verify-jwt
# -> http://localhost:54321/functions/v1/coach
```

## Deploy
```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...    # one-time, stored encrypted
supabase functions deploy coach
# -> https://<project-ref>.supabase.co/functions/v1/coach
```

## Calling it

Same request/response shape as the local proxy — `{ messages, context }` in, SSE
(`text` / `tool` / `diagnosis` / `done`) out — so the prototype client and the iOS app share
one contract.

```
POST https://<ref>.supabase.co/functions/v1/coach
Authorization: Bearer <SUPABASE_ANON_KEY>   # omit if deployed with --no-verify-jwt
Content-Type: application/json

{ "messages": [{ "role": "user", "content": "Am I on track for 1:10?" }],
  "context": { /* freshness-stamped snapshot */ } }
```

- **Prototype:** just open it with the endpoint in the URL — no edit needed:
  `…/index.html?coach=https://<ref>.supabase.co/functions/v1/coach&coachkey=<anon key>`
  (the choice is remembered in localStorage; reload without params to keep using it, or
  `?coach=http://localhost:8788/api/chat` to switch back to the local proxy).
- **iOS app:** point the coach client at the function URL; the anon key ships in the app, the
  Anthropic key never does.

## Auth note
By default Edge Functions require a Supabase JWT (the anon key in `Authorization`). For quick
testing you can deploy/serve with `--no-verify-jwt`; for the real app, send the anon key and
(later) gate on an authenticated user.
