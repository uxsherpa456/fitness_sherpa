# Fitness Sherpa — iOS app

Native SwiftUI app (HealthKit + SwiftData), built from the spec in
[`../prototype/`](../prototype/).

> Scaffolding lands once Xcode is set up (Mac required).

## Already here (drop into the Xcode target)

- [`SETUP.md`](SETUP.md) — **start here Saturday**: Xcode install → project → capabilities → run on device
- [`DATA_MAP.md`](DATA_MAP.md) — HealthKit metric map, authorization, freshness/query patterns
- [`Sources/DiagnosisEngine.swift`](Sources/DiagnosisEngine.swift) — pure-Swift port of the
  diagnostic engine (the strength × running quadrant). No dependencies; unit-testable.
- [`Sources/Models.swift`](Sources/Models.swift) — SwiftData schema: `Goal`, `Baseline`,
  `DiagnosisRecord`, `Session`, `Benchmark`, `HealthSnapshot`.
- [`Sources/StateSync.swift`](Sources/StateSync.swift) — cloud persistence client + DTOs
  (`AppState`/`GoalArc`/`AppSettings`). Pulls/pushes the same `app_state` row the prototype writes.

First session: new SwiftUI project → add HealthKit capability → add these files to the
target → paste the auth snippet from `DATA_MAP.md` → start reading Ultra 2 data.

## Planned structure

- **SwiftUI `TabView`** — Today · Athlete · Plan · AI Coach (mirrors the prototype)
- **HealthKit read layer** — Apple Watch Ultra 2 → the focused metric set (HRV, resting HR,
  VO₂max, sleep, runs with per-second HR for drift, active energy, bodyweight),
  re-queried on open and before each AI turn, freshness-stamped
- **SwiftData** — local source of truth + trends (offline-first)
- **Cloud sync** — `StateSync.swift` mirrors onboarding/profile/goals/settings to the deployed
  `state` Edge Function (`…/functions/v1/state`, `app_state` table) so data carries across
  devices and from the prototype; pull on launch (cloud wins when it has data), push on edits
- **Diagnostic engine** — strength × running quadrant; a direct port of the prototype's
  `recompute_diagnosis`
- **AI coach** — calls the deployed Supabase Edge Function (already live):
  `https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/coach`. It holds the API key and runs
  the agent loop; evidence + freshness guardrails are core, not cosmetic. The app sends
  `{ messages, context }` and reads the SSE stream (`text` / `tool` / `diagnosis` / `done`).

## Requirements

- Xcode (macOS)
- A physical iPhone — the simulator can't read real HealthKit data
- Apple Watch — supplies most of the metric set

## Manual-entry gaps (by design)

- **Body fat** — needs a smart scale writing to HealthKit, else manual
- **Stations & strength** — the watch can't see them; entered in the Train logger
