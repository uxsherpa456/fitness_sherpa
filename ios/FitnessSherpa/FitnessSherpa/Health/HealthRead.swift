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

    /// The most-recent day's *average* for a discrete metric — the number the Health app shows on its
    /// tile (e.g. HRV averages all of the day's SDNN readings, not the latest one). Anchored to the
    /// calendar day of the newest sample, and stamped with that sample's time for freshness.
    static func dailyAverageSample(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Sample? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id),
              let latest = try await latestSample(id, unit: unit) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: latest.date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
        let avg: Double? = try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
        // Average over the day, but keep the freshness stamp on the latest reading.
        return Sample(value: avg ?? latest.value, date: latest.date)
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

    /// Daily aggregated series (date + value) for a metric — for trend charts.
    static func dailySeries(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int,
                            options: HKStatisticsOptions) async throws -> [TrendPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date()).addingTimeInterval(86400)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        var interval = DateComponents(); interval.day = 1
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options, anchorDate: cal.startOfDay(for: Date()), intervalComponents: interval)
            q.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var points: [TrendPoint] = []
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let qty = options.contains(.cumulativeSum) ? stat.sumQuantity() : stat.averageQuantity()
                    if let qty { points.append(TrendPoint(date: stat.startDate, value: qty.doubleValue(for: unit))) }
                }
                cont.resume(returning: points)
            }
            store.execute(q)
        }
    }

    /// Per-day "morning" readings for the RecoveryEngine: each day's **overnight SDNN average**
    /// (samples in the [00:00, 10:00) sleep/early-morning window, averaged to smooth the big
    /// sample-to-sample swings) paired with that day's resting HR. Oldest → newest.
    ///
    /// We average rather than take a single reading because one Apple Watch SDNN sample is very
    /// noisy and the earliest overnight sample is usually a sleep-onset dip — the *opposite* of a
    /// recovery value. Resting HR is forward-filled (it posts with a lag and changes slowly), so the
    /// latest day with an overnight HRV reading still resolves to "today" instead of stalling on
    /// yesterday. (True per-night sleep-window detection is a future refinement.)
    static func morningReadings(days: Int = 70) async throws -> [MorningReading] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let ms = HKUnit.secondUnit(with: .milli)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(-Double(days) * 86400))
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())

        let hrvSamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: hrvType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        // Average the overnight window per day.
        var acc: [Date: (sum: Double, n: Int)] = [:]
        for s in hrvSamples where cal.component(.hour, from: s.startDate) < 10 {
            let day = cal.startOfDay(for: s.startDate)
            let v = s.quantity.doubleValue(for: ms)
            let cur = acc[day] ?? (0, 0)
            acc[day] = (cur.sum + v, cur.n + 1)
        }
        var morningHRV: [Date: Double] = [:]
        for (day, a) in acc { morningHRV[day] = a.sum / Double(a.n) }

        // Apple stores one resting-HR value per day.
        let rhrSeries = (try? await dailySeries(.restingHeartRate, unit: bpm, days: days, options: .discreteAverage)) ?? []
        var rhrByDay: [Date: Double] = [:]
        for p in rhrSeries { rhrByDay[cal.startOfDay(for: p.date)] = p.value }

        // Build oldest→newest, forward-filling resting HR so today (HRV present, RHR may lag) still resolves.
        var lastRHR: Double?
        var out: [MorningReading] = []
        for day in morningHRV.keys.sorted() {
            guard let sdnn = morningHRV[day] else { continue }
            if let rhr = rhrByDay[day] { lastRHR = rhr }
            guard let rhr = lastRHR else { continue }   // skip leading days before any RHR exists
            out.append(MorningReading(date: day, sdnnMS: sdnn, rhrBPM: rhr, source: .healthkit))
        }
        return out
    }

    /// Per-night sleep over the last `days` (asleep / deep / REM hours), grouped into sleep sessions.
    static func sleepNights(days: Int = 30) async throws -> [SleepNight] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-Double(days + 1) * 86400), end: Date())
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return [] }
        func intervals(_ values: Set<Int>) -> [(start: Date, end: Date)] {
            merge(samples.filter { values.contains($0.value) }.map { (start: $0.startDate, end: $0.endDate) })
        }
        let asleep = intervals([
            HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue])
        guard !asleep.isEmpty else { return [] }
        let remIv = intervals([HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let deepIv = intervals([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])

        // Group asleep intervals into nights (split on gaps > 4h).
        var nightsRanges: [(start: Date, end: Date)] = []
        var cur: (start: Date, end: Date)?
        for iv in asleep {
            if var c = cur, iv.start.timeIntervalSince(c.end) <= 4 * 3600 {
                c.end = max(c.end, iv.end); cur = c
            } else {
                if let c = cur { nightsRanges.append(c) }
                cur = iv
            }
        }
        if let c = cur { nightsRanges.append(c) }

        func clipHours(_ ivs: [(start: Date, end: Date)], _ win: (start: Date, end: Date)) -> Double {
            ivs.reduce(0.0) { acc, iv in
                let s = max(iv.start, win.start), e = min(iv.end, win.end)
                return acc + max(0, e.timeIntervalSince(s))
            } / 3600
        }
        let cal = Calendar.current
        return nightsRanges.map { win in
            SleepNight(date: cal.startOfDay(for: win.end), asleep: clipHours(asleep, win),
                       deep: clipHours(deepIv, win), rem: clipHours(remIv, win))
        }.sorted { $0.date < $1.date }
    }

    /// Read the milestone metrics in one call, stamped with the query time.
    static func readSnapshot() async throws -> Reading {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hrv   = dailyAverageSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
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
