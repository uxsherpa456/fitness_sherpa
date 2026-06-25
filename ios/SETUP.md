# Saturday Setup Checklist

Getting from a fresh MacBook Air to a running Fitness Sherpa build on your iPhone 15 Pro Max.
Work top to bottom; the slow parts (Xcode download) are first so they run in the background.

## 0. Before anything else — start the big download
- [ ] App Store → search **Xcode** → **Get** (it's ~7–12 GB; let it run while you do the rest)
- [ ] Sign in to the Mac with your Apple ID
- [ ] On the **iPhone**: Settings → Privacy & Security → **Developer Mode** → On (reboots the phone)
- [ ] Have the **Lightning/USB-C cable** handy to plug the phone into the Mac the first time

## 1. First launch of Xcode
- [ ] Open Xcode → accept the license → let it install "additional components"
- [ ] Xcode → **Settings → Accounts** → **+** → add your Apple ID (this is your free
      *Personal Team* — enough to run on your own device, no paid program needed yet)

## 2. New project
- [ ] **File → New → Project → iOS → App**
- [ ] Product Name: `FitnessSherpa`  ·  Interface: **SwiftUI**  ·  Language: **Swift**
- [ ] Storage: **SwiftData**  ·  uncheck tests for now (add later)
- [ ] Save it **inside the repo** at `fitness_sherpa/ios/` so the app lives next to the spec

## 3. Capabilities & Info.plist
- [ ] Select the target → **Signing & Capabilities** → set **Team** to your Personal Team
- [ ] **+ Capability → HealthKit** (add *Background Delivery* later when you wire observers)
- [ ] Target → **Info** → add key **Privacy - Health Share Usage Description**
      (`NSHealthShareUsageDescription`) with the string from [`DATA_MAP.md`](DATA_MAP.md)

## 4. Drop in what's already written
- [ ] Drag [`Sources/DiagnosisEngine.swift`](Sources/DiagnosisEngine.swift) and
      [`Sources/Models.swift`](Sources/Models.swift) into the project navigator
      ("Copy items if needed" can stay **off** — reference them in place)
- [ ] In your `App` struct add the container:
      ```swift
      .modelContainer(for: [Goal.self, Baseline.self, DiagnosisRecord.self,
                            Session.self, Benchmark.self, HealthSnapshot.self])
      ```
- [ ] Build (⌘B) — the engine + models should compile clean before any UI

## 5. Run on the real phone
- [ ] Plug in the iPhone → trust the Mac on the phone
- [ ] In Xcode's run-destination dropdown, pick **your iPhone** (not a simulator —
      the simulator can't read real HealthKit data)
- [ ] **⌘R**. First run: on the phone, Settings → General → VPN & Device Management →
      trust your developer cert
- [ ] Sanity check: call `try await HealthData.requestAuthorization()` on launch and
      confirm the Health permission sheet appears

## 6. First real milestone
Prove the pipeline end-to-end before building UI:
- [ ] Read **resting HR + HRV + last run** from HealthKit, print them
- [ ] Build a `Baseline` from them + manual bodyweight/5k → `DiagnosisEngine.diagnose(...)`
- [ ] Print the resulting profile + marker → confirms it matches the prototype

Then start the SwiftUI `TabView` (Today · Athlete · Plan · AI Coach), porting screens from
[`../prototype/index.html`](../prototype/index.html) one card at a time.

## Order of build (after setup)
1. HealthKit read layer → freshness-stamped `HealthSnapshot`
2. Onboarding → `Baseline` → `DiagnosisEngine` → first `DiagnosisRecord`
3. Today + Athlete tabs (read-only views of the store)
4. Train logger (manual `Session` / `Benchmark`)
5. AI Coach → backend (Supabase Edge Function port of `prototype/server.mjs`)

## Gotchas
- **Simulator ≠ Health data.** Always test data on the physical phone.
- **Personal Team apps expire after 7 days** and cap at a few app IDs — fine for dev; join
  the paid Developer Program ($99/yr) when you want TestFlight or longer signing.
- **HealthKit returns nothing until authorized** *and* until there's data for that type —
  wear the Ultra 2 a day or two first so HRV/VO₂max/sleep have history.
- Keep the **Anthropic key out of the app** — it stays in the backend, exactly like the
  prototype's `server.mjs`.
