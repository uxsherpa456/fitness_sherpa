# Fitness Sherpa — iOS app

Native SwiftUI app (HealthKit + SwiftData), built from the spec in
[`../prototype/`](../prototype/).

> Scaffolding lands once Xcode is set up (Mac required).

## Planned structure

- **SwiftUI `TabView`** — Today · Athlete · Plan · AI Coach (mirrors the prototype)
- **HealthKit read layer** — Apple Watch Ultra 2 → the focused metric set (HRV, resting HR,
  VO₂max, sleep, runs with per-second HR for drift, active energy, bodyweight),
  re-queried on open and before each AI turn, freshness-stamped
- **SwiftData** — local source of truth + trends (offline-first)
- **Diagnostic engine** — strength × running quadrant; a direct port of the prototype's
  `recompute_diagnosis`
- **AI coach** — via a backend (Supabase Edge Function) that holds the API key and runs the
  agent loop; evidence + freshness guardrails are core, not cosmetic

## Requirements

- Xcode (macOS)
- A physical iPhone — the simulator can't read real HealthKit data
- Apple Watch — supplies most of the metric set

## Manual-entry gaps (by design)

- **Body fat** — needs a smart scale writing to HealthKit, else manual
- **Stations & strength** — the watch can't see them; entered in the Train logger
