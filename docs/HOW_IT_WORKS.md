# Ravn — How It Works
### A one-page technical brief

*(Ravn is the working name. Native iOS app, built on Apple Health. Today it's a working prototype on a real device with live data.)*

---

## The idea in one line
**Ravn diagnoses what's actually holding a HYROX athlete back, builds them a phased plan to race day, and adjusts daily based on how recovered they are — with an AI coach that reasons over all of it.**

The app is the **delivery system**. A coach's methodology is the **content**. They plug together cleanly.

---

## The pipeline

**1 · Baseline assessment (onboarding)**
A few honest questions place the athlete on a **strength × running quadrant** — four limiter profiles:
- *Heavy & slow, strong enough* — limiter is run pace + power-to-weight
- *Light & fast, not strong* — limiter is strength + station capacity
- *Good at everything* — limiter is integration / pacing
- *Weak at everything* — needs a base on both

The **run axis** comes from a recent 5K + bodyweight (power-to-weight). The **strength axis** comes from the athlete's barbell lifts **measured against their division's standards** (Open vs Pro, men's vs women's) — so "strong enough" means strong enough *for the race they're doing*, not a generic bar. A separate **mobility flag** (squat depth, ankle, posterior chain) is carried as an advisory limiter, not a score.

**2 · Apple Health integration**
Reads HRV, resting HR, sleep, respiratory rate, wrist temperature, workouts, bodyweight, VO₂max — always with a freshness stamp (it won't make a call off stale data).

**3 · Daily readiness**
Two-axis recovery — HRV and resting HR scored against the athlete's **own rolling baseline** (log-normal HRV, not generic thresholds) — combined with **training load** (per-session training impulse → acute/chronic load → "form") and a one-tap subjective check. Vitals like resting HR and breathing only ding the score when they're true outliers (illness/strain), the way Apple treats them.

**4 · Periodization → race day**
From the athlete's days-to-race and limiter profile, Ravn lays out **base → build → peak → taper**, weighting the phases by what they need (a weaker athlete gets a longer base; an already-elite athlete gets more sharpening).

**5 · Concrete, personalized sessions**
Every week is generated phase-appropriately with **real targets**:
- Run paces from the athlete's 5K; the **HYROX race pace is back-solved from their goal finish time** (goal − estimated station time ÷ 8 km) — and flags the goal as ambitious if it requires near-5K running.
- Station work at the **exact implement weights of their division** (sled / wall ball / sandbag / farmers).

**6 · AI coach**
A chat coach (built on Claude) that reasons over the athlete's full context — diagnosis, readiness, training load, plan, goals, freshness — and can **edit the plan and goals directly** when asked. It won't prescribe off stale or missing data.

**7 · Durable + synced**
Settings, goals, workout history, and the readiness trend sync to the cloud and survive a reinstall or new device.

---

## Where a coach's methodology plugs in

Everything below is **rules and numbers**, not a rewrite — each is a place his expertise replaces our reasoned defaults:

| Today (our reasoned default) | Replace with his methodology |
|---|---|
| Strength standards by division | **His** "strong enough" numbers per lift / division |
| Estimated station times (for goal-pace math) | **His** real station-time benchmarks by ability/division |
| Phase lengths + session templates | **His** periodization + session prescriptions |
| How we decide the limiter | **His** diagnostic logic |
| Coach's voice + priorities | **His** coaching philosophy in the AI coach |

## What we'd need from him to do that
- Strength standards (lift → bodyweight multiple or absolute, by division)
- Station-time benchmarks (per station, by ability tier / division)
- His phase structure and the sessions that belong in each
- How he reads an athlete's limiter from their numbers
- His non-negotiables and coaching principles (these become the coach's rules)

---

## Why this is hard to copy
- **Own-baseline recovery** — compares the athlete to themselves, not a population chart (HRV in Apple Health is SDNN, and most published thresholds don't even apply).
- **Division-aware everything** — strength, stations, pacing all scale to the exact race.
- **Goal-derived pacing** — works backward from the time they're chasing.
- **An agentic coach** that can actually change the plan, grounded in real data with guardrails.

The engines are already built and pluggable. Adding a real methodology makes the *content* world-class without touching the delivery system.
