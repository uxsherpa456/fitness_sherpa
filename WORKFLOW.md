# Workflow — two machines, one repo

Fitness Sherpa is built across a **Windows PC** and a **MacBook Air**, sharing this repo as
the single source of truth. Split work by what each machine is uniquely good at; sync via git.

## Who does what

| Machine | Owns | Folder |
|---|---|---|
| **Mac** (Apple toolchain only) | Xcode, SwiftUI views, HealthKit, running/debugging on the iPhone, signing/TestFlight | `ios/` |
| **Windows** (everything else) | AI coach backend, the HTML prototype/spec, prompts + guardrails, docs/planning, git, scheduled agents | `prototype/`, backend, docs |

The iOS app is only part of the work. The backend, coaching prompts, diagnosis logic, design
iteration, and planning are platform-agnostic — keep doing them on Windows **in parallel** with
the Mac build so two streams move at once.

## Git is the spine

- Both machines clone: `git clone https://github.com/uxsherpa456/fitness_sherpa.git`
- **`git pull` before you start** on either machine.
- Commit small, push often. **Don't edit the same file on both machines at once** — if a piece
  of work spans both, branch (`git checkout -b feature/x`) and merge.
- The repo — not a chat or a USB stick — is how the two machines (and the two Claude Code
  instances) stay in sync.

## Repo layout

```
fitness_sherpa/
├── README.md            overview
├── WORKFLOW.md          this file
├── prototype/           the HTML prototype = the living spec  (Windows)
├── supabase/            coach backend — Edge Function         (Windows)
│   └── functions/coach  POST /functions/v1/coach (chat + agent, streamed)
└── ios/                 native SwiftUI app                    (Mac)
    ├── SETUP.md         Saturday: zero → running on device
    ├── DATA_MAP.md      HealthKit metric map + auth
    └── Sources/         DiagnosisEngine.swift + Models.swift  (ported, ready to drop in)
```

## Cross-machine dev (the useful trick)

Both machines on the same Wi-Fi: **run the coach backend on Windows, point the Mac's dev app
at it.** Edit `prototype/server.mjs` (or the future Edge Function) on Windows; the iOS app picks
it up live.

- Start it on Windows: `node prototype/server.mjs` (binds all interfaces).
- Find the Windows LAN IP: `ipconfig` → IPv4 address (e.g. `192.168.x.x`).
- In the iOS app, point the coach URL at `http://192.168.x.x:8788` instead of `localhost`.
- Long-term, move the backend to a **Supabase Edge Function** so the app calls the cloud, not a
  laptop.

## Claude Code on both

Run Claude Code on each machine. **Windows-Claude**: backend, prototype, prompts, docs, planning.
**Mac-Claude**: SwiftUI views, HealthKit wiring, Xcode. Both read this repo, so both share the
plan — start a session by having it read `WORKFLOW.md` and the relevant folder's `README`.

## Keep the engines in sync

`prototype/` (JS) and `ios/Sources/DiagnosisEngine.swift` (Swift) implement the **same diagnosis
math**. If you change the formula in one, change it in the other in the same commit — the
prototype, the coach, and the app must always agree on a profile.

## Secrets

The Anthropic API key never enters the app or the repo — it lives only in the backend's
environment (`ANTHROPIC_API_KEY`). `.gitignore` blocks `.env`. Same rule on both machines.

## Current state (update as you go)

- [x] Prototype complete (the spec)
- [x] `ios/` prepped: SETUP, DATA_MAP, DiagnosisEngine, Models
- [x] Coach backend ported to a Supabase Edge Function (`supabase/functions/coach`) — written + logic verified; **needs `supabase functions deploy`**
- [ ] Mac set up, Xcode installed, project created in `ios/`
- [ ] HealthKit read layer → freshness-stamped snapshot
- [ ] SwiftUI tabs ported from the prototype
- [ ] Deploy the Edge Function + point the iOS app at it
