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
        func hours(_ ivs: [(start: Date, end: Date)]) -> Double {
            ivs.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
        }

        let rem    = intervals([HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let core   = intervals([HKCategoryValueSleepAnalysis.asleepCore.rawValue])
        let deep   = intervals([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
        let asleep = intervals([
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ])
        guard !asleep.isEmpty else { return nil }
        let awake  = intervals([HKCategoryValueSleepAnalysis.awake.rawValue])
        let inBedIv = intervals([HKCategoryValueSleepAnalysis.inBed.rawValue])

        let onset = asleep.map(\.start).min() ?? Date()
        let wake  = asleep.map(\.end).max() ?? Date()
        let asleepHrs = hours(asleep)
        let awakeHrs  = hours(awake)
        let inBedHrs  = inBedIv.isEmpty ? asleepHrs + awakeHrs : hours(inBedIv)
        let awakenings = awake.filter { $0.start >= onset && $0.end <= wake }.count

        return SleepSummary(
            inBed: inBedHrs,
            asleep: asleepHrs,
            rem: hours(rem),
            core: hours(core),
            deep: hours(deep),
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

    /// Read the milestone metrics in one call, stamped with the query time.
    static func readSnapshot() async throws -> Reading {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hrv   = latestSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let rhr   = latestSample(.restingHeartRate, unit: bpm)
        async let mass  = latestSample(.bodyMass, unit: .pound())
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
            sleepSummary: try await sleep,
            lastRunDate: run?.endDate,
            lastRunKm: km,
            lastRunMinutes: run.map { $0.duration / 60 }
        )
    }
}
