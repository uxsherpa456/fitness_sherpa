//  HealthRead.swift
//  Fitness Sherpa
//
//  Minimal HealthKit read helpers for the first milestone (SETUP.md §6) + freshness stamping
//  (DATA_MAP.md §5): pull the latest recovery metrics + most recent run, each stamped with the
//  newest sample's date and the time we queried — so the coach's "won't reason off stale data"
//  guardrail has real timestamps to check, not just values.

import HealthKit

extension HealthData {

    /// A single metric value plus the timestamp of the sample it came from.
    struct Sample {
        var value: Double
        var date: Date          // endDate of the newest sample
    }

    /// Full sleep-quality breakdown for the most recent night (hours unless noted).
    struct SleepSummary {
        var inBed: Double
        var asleep: Double          // REM + Core + Deep + Unspecified
        var rem: Double
        var core: Double
        var deep: Double
        var awake: Double           // awake time within the sleep window
        var awakenings: Int         // mid-sleep awake segments
        var efficiency: Double      // asleep / inBed, 0–1
        var wake: Date              // when the night ended (freshness stamp)
    }

    /// One read of the milestone metrics, stamped with when we queried Health.
    struct Reading {
        var queriedAt: Date
        var hrv: Sample?            // HRV SDNN, ms
        var restingHR: Sample?      // bpm
        var bodyMass: Sample?       // lb
        var bodyFat: Sample?        // fraction 0…1
        var sleepSummary: SleepSummary?
        var lastRunDate: Date?

        /// Total sleep as a freshness-stamped Sample (drives the readiness metric set).
        var sleep: Sample? { sleepSummary.map { Sample(value: $0.asleep, date: $0.wake) } }
        var lastRunKm: Double?
        var lastRunMinutes: Double?

        /// The freshness-critical metrics and how old each may be before it's "stale".
        /// Recovery metrics drive readiness and decay fast; bodyweight (the limiter) drifts slowly.
        enum Metric: String, CaseIterable {
            case hrv = "HRV"
            case restingHR = "Resting HR"
            case sleep = "Sleep"
            case bodyweight = "Bodyweight"

            var maxAge: TimeInterval {
                switch self {
                case .hrv, .restingHR, .sleep: return 36 * 3600   // 36 h
                case .bodyweight:              return 14 * 86400   // 14 d
                }
            }

            /// Whether staleness here should block a readiness verdict (recovery metrics only).
            var blocksReadiness: Bool { self != .bodyweight }
        }

        func sample(for m: Metric) -> Sample? {
            switch m {
            case .hrv:        return hrv
            case .restingHR:  return restingHR
            case .sleep:      return sleep
            case .bodyweight: return bodyMass
            }
        }

        /// Age of a metric's sample as of when we queried (nil if missing).
        func age(for m: Metric) -> TimeInterval? {
            sample(for: m).map { queriedAt.timeIntervalSince($0.date) }
        }

        func isStale(_ m: Metric) -> Bool {
            guard let age = age(for: m) else { return true }   // missing = not fresh
            return age > m.maxAge
        }

        /// Names of metrics that are missing or past their freshness window.
        var staleMetrics: [String] { Metric.allCases.filter { isStale($0) }.map(\.rawValue) }

        /// Readiness can be reasoned only when the recovery metrics are current.
        var readinessFresh: Bool { !Metric.allCases.filter(\.blocksReadiness).contains(where: isStale) }
    }

    /// Latest single sample for a quantity type, with its timestamp. `nil` if none/unauthorized.
    static func latestSample(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Sample? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                if let s = samples?.first as? HKQuantitySample {
                    cont.resume(returning: Sample(value: s.quantity.doubleValue(for: unit), date: s.endDate))
                } else {
                    cont.resume(returning: nil)
                }
            }
            store.execute(q)
        }
    }

    /// Merge overlapping date intervals (de-dupes overlapping samples from multiple sources).
    private static func merge(_ ivs: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        let sorted = ivs.sorted { $0.start < $1.start }
        var out: [(start: Date, end: Date)] = []
        for iv in sorted {
            if let last = out.last, iv.start <= last.end {
                out[out.count - 1].end = max(last.end, iv.end)
            } else {
                out.append(iv)
            }
        }
        return out
    }

    /// Full sleep-quality breakdown for the most recent night: per-stage hours, time in bed,
    /// efficiency, awake time, and awakenings — from the last 36h, merged across sources.
    static func latestSleep() async throws -> SleepSummary? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-36 * 3600), end: Date())
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return nil }

        func intervals(_ values: Set<Int>) -> [(start: Date, end: Date)] {
            merge(samples.filter { values.contains($0.value) }.map { (start: $0.startDate, end: $0.endDate) })
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let asleep = intervals(asleepValues)
        guard let last = asleep.last else { return nil }

        // Isolate the MOST RECENT sleep session: the contiguous cluster ending at the latest
        // interval, walking back while gaps stay under 4h. Prevents summing two nights / a nap.
        var startIdx = asleep.count - 1
        while startIdx > 0, asleep[startIdx].start.timeIntervalSince(asleep[startIdx - 1].end) <= 4 * 3600 {
            startIdx -= 1
        }
        let windowStart = asleep[startIdx].start
        let wake = last.end

        // Sum a metric's intervals clipped to the session window [windowStart, wake].
        func windowHours(_ ivs: [(start: Date, end: Date)]) -> Double {
            ivs.reduce(0.0) { acc, iv in
                let s = max(iv.start, windowStart), e = min(iv.end, wake)
                return acc + max(0, e.timeIntervalSince(s))
            } / 3600
        }

        let asleepHrs = windowHours(asleep)
        let awakeIv = intervals([HKCategoryValueSleepAnalysis.awake.rawValue])
        let awakeHrs = windowHours(awakeIv)
        let inBedIv = intervals([HKCategoryValueSleepAnalysis.inBed.rawValue])
        let inBedHrs = inBedIv.isEmpty ? asleepHrs + awakeHrs : windowHours(inBedIv)
        let awakenings = awakeIv.filter { $0.start >= windowStart && $0.end <= wake }.count

        return SleepSummary(
            inBed: inBedHrs,
            asleep: asleepHrs,
            rem: windowHours(intervals([HKCategoryValueSleepAnalysis.asleepREM.rawValue])),
            core: windowHours(intervals([HKCategoryValueSleepAnalysis.asleepCore.rawValue])),
            deep: windowHours(intervals([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])),
            awake: awakeHrs,
            awakenings: awakenings,
            efficiency: inBedHrs > 0 ? min(1, asleepHrs / inBedHrs) : 0,
            wake: wake
        )
    }

    /// Most recent running workout, or `nil`.
    static func latestRun() async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForWorkouts(with: .running)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
    }

    /// A completed workout read from HealthKit (read-only; manual sessions live in SwiftData).
    struct Workout: Identifiable {
        let id: UUID
        let category: SessionCategory
        let typeLabel: String
        let date: Date
        let durationMin: Int
        let distanceKm: Double?
        let caloriesKcal: Double?
        let avgHR: Int?
        let maxHR: Int?
    }

    private static func categorize(_ t: HKWorkoutActivityType) -> (SessionCategory, String) {
        switch t {
        case .running:                                            return (.run, "Run")
        case .walking, .hiking:                                   return (.run, "Walk")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return (.strength, "Strength")
        case .highIntensityIntervalTraining, .crossTraining:     return (.hiit, "HIIT")
        case .rowing:                                            return (.row, "Row")
        default:                                                 return (.other, "Workout")
        }
    }

    /// Recent completed workouts from HealthKit, newest first.
    static func recentWorkouts(days: Int = 21) async throws -> [Workout] {
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-Double(days) * 86400), end: Date())
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 200, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return workouts.map { w in
            var km: Double? = nil
            if let distType, let d = w.statistics(for: distType)?.sumQuantity() {
                km = d.doubleValue(for: .meterUnit(with: .kilo))
            }
            var kcal: Double? = nil
            if let energyType, let e = w.statistics(for: energyType)?.sumQuantity() {
                kcal = e.doubleValue(for: .kilocalorie())
            }
            var avgHR: Int? = nil, maxHR: Int? = nil
            if let hrType, let hr = w.statistics(for: hrType) {
                avgHR = hr.averageQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
                maxHR = hr.maximumQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
            }
            let (cat, label) = categorize(w.workoutActivityType)
            return Workout(id: w.uuid, category: cat, typeLabel: label,
                           date: w.endDate, durationMin: Int(w.duration / 60),
                           distanceKm: (km ?? 0) > 0.05 ? km : nil,
                           caloriesKcal: (kcal ?? 0) > 0 ? kcal : nil,
                           avgHR: avgHR, maxHR: maxHR)
        }
    }

    // MARK: - Baselines (for the readiness model)

    /// Per-day aggregated values over the last `days` (one bucket per day) — the substrate for
    /// rolling baselines. `.discreteAverage` for vitals, `.cumulativeSum` for energy.
    static func dailyValues(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int,
                            options: HKStatisticsOptions) async throws -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date()).addingTimeInterval(86400)     // start of tomorrow
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        var interval = DateComponents(); interval.day = 1

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options,
                anchorDate: cal.startOfDay(for: Date()),
                intervalComponents: interval)
            q.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var values: [Double] = []
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let qty = options.contains(.cumulativeSum) ? stat.sumQuantity() : stat.averageQuantity()
                    if let qty { values.append(qty.doubleValue(for: unit)) }
                }
                cont.resume(returning: values)
            }
            store.execute(q)
        }
    }

    /// Rolling baseline (mean + SD) for a metric. Needs ≥7 days of data, else nil → caller uses a prior.
    static func baseline(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int = 60) async -> MetricBaseline? {
        guard let values = try? await dailyValues(id, unit: unit, days: days, options: .discreteAverage),
              values.count >= 7 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return MetricBaseline(mean: mean, sd: max(sqrt(variance), 0.0001), n: values.count)
    }

    /// Read the milestone metrics in one call, stamped with the query time.
    static func readSnapshot() async throws -> Reading {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hrv   = latestSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let rhr   = latestSample(.restingHeartRate, unit: bpm)
        async let mass  = latestSample(.bodyMass, unit: .pound())
        async let bf    = latestSample(.bodyFatPercentage, unit: .percent())
        async let sleep = latestSleep()

        let run = try await latestRun()
        var km: Double? = nil
        if let run, let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
           let dist = run.statistics(for: distType)?.sumQuantity() {
            km = dist.doubleValue(for: .meterUnit(with: .kilo))
        }

        return Reading(
            queriedAt: Date(),
            hrv: try await hrv,
            restingHR: try await rhr,
            bodyMass: try await mass,
            bodyFat: try await bf,
            sleepSummary: try await sleep,
            lastRunDate: run?.endDate,
            lastRunKm: km,
            lastRunMinutes: run.map { $0.duration / 60 }
        )
    }
}
