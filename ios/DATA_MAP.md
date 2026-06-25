# HealthKit Data Map

The focused metric set the app reads, mapped to HealthKit types — what the **Apple Watch
Ultra 2** supplies, what's manual, and the authorization + query patterns. Ready to wire up
once Xcode is installed.

## 1. Authorization

The app is **read-only** from HealthKit (manual entries live in SwiftData, not HealthKit).

**Info.plist**
- `NSHealthShareUsageDescription` — "Fitness Sherpa reads your recovery and workout data to diagnose what's limiting your race time and coach you off current, real numbers."
- (Add `NSHealthUpdateUsageDescription` only if you later write body metrics back.)

**Capability:** add *HealthKit* in Signing & Capabilities. Background delivery needs the
*HealthKit → Background Delivery* entitlement.

## 2. The metric set

| Metric | HealthKit identifier | Kind | Unit | Source | Freshness-critical |
|---|---|---|---|---|---|
| Heart rate (per-second) | `.heartRate` | Quantity | count/min | Watch | for workouts |
| HRV (SDNN) | `.heartRateVariabilitySDNN` | Quantity | ms | Watch | ✅ readiness |
| Resting HR | `.restingHeartRate` | Quantity | count/min | Watch | ✅ readiness |
| Sleep | `.sleepAnalysis` | Category | stages | Watch | ✅ readiness |
| VO₂max | `.vo2Max` | Quantity | mL/kg·min | Watch (outdoor runs) | weekly |
| Run distance | `.distanceWalkingRunning` | Quantity | km / mi | Watch | per-workout |
| Running speed | `.runningSpeed` (iOS 16+) | Quantity | m/s | Watch | per-workout |
| Running power | `.runningPower` (iOS 16+) | Quantity | W | Watch (Ultra) | per-workout |
| Active energy | `.activeEnergyBurned` | Quantity | kcal | Watch | daily |
| Bodyweight | `.bodyMass` | Quantity | kg / lb | Scale / manual | the limiter |
| Body fat % | `.bodyFatPercentage` | Quantity | % | **Smart scale / manual** | the limiter |
| Workouts | `HKWorkoutType` | Workout | — | Watch | per-workout |
| GPS route | `HKSeriesType.workoutRoute()` | Series | — | Watch | optional |

Recovery metrics (HRV, resting HR, sleep) are the ones the **freshness guardrail** protects —
the coach refuses to compute a readiness verdict off any of them when stale.

## 3. Workouts & the HR-drift read

Pull `HKWorkout` samples and filter by `HKWorkoutActivityType`:
- `.running` — the run sessions (most of the diagnosis)
- `.functionalStrengthTraining`, `.traditionalStrengthTraining` — strength
- `.highIntensityIntervalTraining`, `.crossTraining` — HYROX-style sessions
- `.rowing` — erg work

**HR drift / aerobic decoupling** (the "did the base hold" read): for a run workout, fetch
`.heartRate` samples within `workout.startDate ... workout.endDate`, split first half vs
second half, and compare the **pace : HR** ratio (Pa:HR). Rising decoupling = fading base.
Per-second HR comes from the workout's associated samples; pace from `.runningSpeed` /
`.distanceWalkingRunning`.

## 4. Not in HealthKit → SwiftData (manual)

The strength axis and stations can't come from the watch — they're entered in the Train
logger and stored locally:
- Station benchmark times (wall balls, sled push/pull, lunges, etc.) and "how they hold
  under fatigue"
- Key lift numbers
- Body fat fallback when there's no smart scale

These feed the diagnosis exactly like the prototype's onboarding does.

## 5. Query patterns (freshness)

- **Latest value:** `HKStatisticsQuery` (`.mostRecent`) or a sorted `HKSampleQuery`
  (`endDate` desc, limit 1).
- **Incremental + live:** `HKAnchoredObjectQuery` (keep the anchor) + `HKObserverQuery`
  with `enableBackgroundDelivery` so the app re-pulls when the watch syncs.
- **Stamp freshness two ways:** (a) when the app last *successfully queried* a type, and
  (b) the `endDate` of the newest sample. "Synced 2 min ago" must mean *I checked Health 2
  min ago and this is the newest sample available* — never "the data is complete." Surface
  the gap when an expected metric is missing or old.

## 6. Authorization snippet (paste into the project)

```swift
import HealthKit

enum HealthData {
    static let store = HKHealthStore()

    /// Everything the app reads — used for the authorization request.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
            .distanceWalkingRunning, .runningSpeed, .runningPower,
            .activeEnergyBurned, .basalEnergyBurned,
            .bodyMass, .bodyFatPercentage,
            .stepCount, .respiratoryRate
        ]
        for id in quantities {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
}
```

> `.runningSpeed` / `.runningPower` are iOS 16+ running metrics the Ultra 2 records — keep
> them behind availability checks if you target older iOS.

## 7. Common units (for reading samples)

```swift
let bpm   = HKUnit.count().unitDivided(by: .minute())        // heart rate, resting HR
let ms    = HKUnit.secondUnit(with: .milli)                  // HRV SDNN
let vo2   = HKUnit(from: "mL/kg*min")                        // VO2max
let kcal  = HKUnit.kilocalorie()                            // active energy
let lb    = HKUnit.pound()                                  // bodyweight
let pct   = HKUnit.percent()                                // body fat
let mps   = HKUnit.meter().unitDivided(by: .second())        // running speed
```
