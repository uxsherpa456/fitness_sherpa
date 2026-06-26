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
- [ ] **Bundle Identifier** auto-fills as `com.<you>.FitnessSherpa` — leave it, just make it unique.
      A free Personal Team allows only a handful of app IDs, so don't keep changing it.
- [ ] Target → **General → Minimum Deployments → iOS 17.0**. SwiftData needs 17; the running
      power/speed metrics need 16+ — iOS 17 covers both. (Leaving it lower gives cryptic build errors.)

## 3. Capabilities & Info.plist
- [ ] Select the target → **Signing & Capabilities** → set **Team** to your Personal Team
- [ ] **+ Capability → HealthKit** (add *Background Delivery* later when you wire observers)
- [ ] Target → **Info** → add key **Privacy - Health Share Usage Description**
      (`NSHealthShareUsageDescription`) with the string from [`DATA_MAP.md`](DATA_MAP.md)

## 4. Drop in what's already written
- [ ] Drag [`Sources/DiagnosisEngine.swift`](Sources/DiagnosisEngine.swift),
      [`Sources/Models.swift`](Sources/Models.swift), and
      [`Sources/StateSync.swift`](Sources/StateSync.swift) into the project navigator
      ("Copy items if needed" can stay **off** — reference them in place)
- [ ] **Verify Target Membership** for each: select the file → File Inspector (⌥⌘1) → tick the
      checkbox next to your app target. Unchecked membership is the #1 silent "cannot find X in
      scope" error.
- [ ] Create a new file **`HealthData.swift`** (File → New → File → Swift File) and paste the
      authorization enum from [`DATA_MAP.md`](DATA_MAP.md) §6 — step 5 calls
      `HealthData.requestAuthorization()`, which won't exist until you do this.
- [ ] In your `App` struct (the template's `@main …App` file) add the container:
      ```swift
      .modelContainer(for: [Goal.self, Baseline.self, DiagnosisRecord.self,
                            Session.self, Benchmark.self, HealthSnapshot.self])
      ```
- [ ] Build (⌘B) — the engine + models + sync client should compile clean before any UI

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
3. **Cloud sync** ([`StateSync.swift`](Sources/StateSync.swift), already written): on launch call
   `StateClient.load()` — if `updated_at != nil` the cloud has data (skip onboarding, seed the
   store); after onboarding and any goals/settings edit call `StateClient.save(...)`. Same
   `app_state` row + `user_key:"ryan"` the prototype writes (swap the key for the signed-in user later).
4. Today + Athlete tabs (read-only views of the store)
5. Train logger (manual `Session` / `Benchmark`)
6. AI Coach → the deployed coach function (already live; see README)

## Gotchas
- **No Watch app to build.** You are *not* making a watchOS target — the Ultra 2 already syncs
  its data to Apple Health on the iPhone, and the app reads it from there.
- **First run fails until you Trust.** After ⌘R the first launch (and again every 7 days when the
  cert expires), the app won't open until you tap **Trust** on the phone (Settings → General →
  VPN & Device Management) — then re-run from Xcode.
- **Background Delivery is a separate toggle.** Live re-pull (`HKObserverQuery` +
  `enableBackgroundDelivery`) needs **Signing & Capabilities → HealthKit → ✓ Background Delivery**.
  Add it when you wire observers; the plain HealthKit capability is enough to start.
- **Simulator ≠ Health data.** Always test data on the physical phone.
- **Personal Team apps expire after 7 days** and cap at a few app IDs — fine for dev; join
  the paid Developer Program ($99/yr) when you want TestFlight or longer signing.
- **HealthKit returns nothing until authorized** *and* until there's data for that type —
  wear the Ultra 2 a day or two first so HRV/VO₂max/sleep have history.
- Keep the **Anthropic key out of the app** — it stays in the backend, exactly like the
  prototype's `server.mjs`.
