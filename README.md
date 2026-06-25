# Fitness Sherpa — HYROX Readiness (prototype)

An interactive prototype of a native-iOS **HYROX readiness companion**: it reads your
health/performance data, **diagnoses the one thing most limiting your goal race time**,
tracks the metrics that move it, and lets you have **data-grounded AI conversations**
about training — gated by a guarantee that every answer uses current, real data.

> This is a single-file HTML prototype (the design + interaction spec). The shipping app
> is native iOS (SwiftUI + HealthKit + SwiftData).

## The idea

It's a **diagnostic engine, not a tracker**. The goal time is fixed; the app's job is to
find your *binding constraint* and focus only on the metrics that move it. It places you
on a strength × running quadrant:

- **Heavy & slow, but strong enough** → limiter is running economy + power-to-weight
- **Light & fast, not strong enough** → limiter is strength + station capacity
- **Good at everything** → limiter is integration / fatigue resistance
- **Weak at everything** → limiter is general base

Two non-negotiables: **freshness** (it won't reason off stale data, and says so) and
**evidence** (every recommendation cites your own numbers).

## What's in here

- `index.html` — the whole prototype (no build step). Splash → onboarding baseline
  assessment → quadrant reveal → guided tab tour → the app.
  Tabs: **Today** (readiness verdict, fuel, last-workout read, next session, AI coach
  entry) · **Athlete** (diagnosis quadrant, fitness score, training status, race-log
  metrics) · **Plan** (weekly training calendar) · **AI Coach** (evidence-gated chat).
- `server.mjs` — a dependency-free Node proxy that serves the app **and** runs the live
  AI coach: it holds the Anthropic API key, builds a freshness-stamped system prompt with
  a guardrail, and runs an agent loop with a `recompute_diagnosis` tool that live-updates
  the quadrant.

## Run it

**Static only (canned coach):**
```bash
python -m http.server 5599
# open http://localhost:5599
```

**With the live AI coach (real model + agentic re-diagnosis):**
```bash
# get a key at https://console.anthropic.com
ANTHROPIC_API_KEY=sk-ant-... node server.mjs   # PowerShell: $env:ANTHROPIC_API_KEY="sk-ant-..."; node server.mjs
# open http://localhost:8788
```
No key? The coach falls back to canned answers and the rest of the app works fully.
The API key lives only in your environment — never in the app or the repo.

## Design language

Dark canvas + mint accent. Cards use a **flat left edge + accent stripe, rounded right**
convention; monospace for technical labels, Hanken Grotesk for the splash wordmark.
