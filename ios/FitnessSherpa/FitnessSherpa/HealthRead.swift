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

    /// One read of the milestone metrics, stamped with when we queried Health.
    struct Reading {
        var queriedAt: Date
        var hrv: Sample?            // HRV SDNN, ms
        var restingHR: Sample?      // bpm
        var bodyMass: Sample?       // lb
        var sleep: Sample?          // hours asleep, last night
        var lastRunDate: Date?
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

    /// Total time asleep over the most recent night: merges overlapping "asleep" intervals from
    /// the last 36h (de-duping multiple sources) and stamps with the wake time. `nil` if none.
    static func latestSleep() async throws -> Sample? {
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

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let intervals = samples.filter { asleep.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return nil }

        var merged: [(start: Date, end: Date)] = []
        for iv in intervals {
            if let last = merged.last, iv.start <= last.end {
                merged[merged.count - 1].end = max(last.end, iv.end)
            } else {
                merged.append(iv)
            }
        }
        let totalSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        let wake = merged.map(\.end).max() ?? Date()
        return Sample(value: totalSeconds / 3600, date: wake)
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
            sleep: try await sleep,
            lastRunDate: run?.endDate,
            lastRunKm: km,
            lastRunMinutes: run.map { $0.duration / 60 }
        )
    }
}
