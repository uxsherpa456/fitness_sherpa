# Fitness Sherpa

A HYROX readiness companion. It reads your Apple Health / Apple Watch data, **diagnoses the
one thing most limiting your goal race time**, tracks the metrics that move it, and coaches
you with AI you can trust — because it proves the data is current and cites your own numbers
before it tells you what to do.

## Repository layout

- **[`prototype/`](prototype/)** — the interactive HTML prototype (design + interaction
  spec). Splash → onboarding baseline assessment → quadrant diagnosis → guided tab tour →
  the app, plus a dependency-free Node proxy that runs the live, evidence-gated AI coach
  with an agentic `recompute_diagnosis` tool. Runs in any browser — see
  [`prototype/README.md`](prototype/README.md).
- **[`ios/`](ios/)** — the native iOS app (SwiftUI + HealthKit + SwiftData). In progress.

Built across two machines (Windows + Mac) sharing this repo — see [`WORKFLOW.md`](WORKFLOW.md).

## Status

The prototype is complete and serves as the working spec. The native build starts now that
a Mac is available. The real data pipeline targets:

**Apple Watch Ultra 2 → Apple Health → SwiftData (local source of truth) → freshness-checked
snapshot → AI coach.**

## The core idea

A diagnostic engine, not a tracker. The goal time is fixed; the job is to find your
*binding constraint* and focus only on the metrics that move it — placing you on a
strength × running quadrant and re-diagnosing as you change. Two non-negotiables:
**freshness** (won't reason off stale data) and **evidence** (every call cites your numbers).
