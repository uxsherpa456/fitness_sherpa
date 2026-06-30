//  DemoSeed.swift
//  Fitness Sherpa
//
//  Web/demo data. Appetize streams the iOS SIMULATOR, which has no Apple Health — so the live
//  readiness/recovery/diagnosis would be empty. In the simulator we instead synthesize a realistic
//  sample athlete (vitals, workouts, readiness trend, diagnosis trail, plan) so a shared link shows
//  the app fully alive. Gated by `#if targetEnvironment(simulator)`, so the real device build is
//  unaffected and always uses live HealthKit.

import Foundation
import SwiftData

enum DemoSeed {
    static var isDemo: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return UserDefaults.standard.bool(forKey: "forceDemo")
        #endif
    }

    // MARK: Sample athlete

    static var sampleSettings: UserSettings {
        var s = UserSettings()
        s.name = "Alex Carter"
        s.location = "Austin, TX"
        s.format = "singles"; s.gender = "mens"; s.tier = "open"
        s.age = 32
        s.goalTime = "1:15"
        s.raceDate = DateFormatters.ymd.string(from: Calendar.current.date(byAdding: .day, value: 70, to: Date()) ?? Date())
        s.raceLocation = "Austin, TX"
        s.recent5k = "23:10"
        s.bodyweightLb = 205
        s.bodyFatPct = 16
        s.heightIn = 71            // 5'11" → BMI ~28.6 (heavy for his frame)
        s.strengthAxis = 0.72
        s.mobilityScore = 0.82
        s.onboarded = true
        return s
    }

    /// Synthetic morning vitals (HealthKit is empty in the simulator).
    static func reading() -> HealthData.Reading {
        let now = Date()
        let sleep = HealthData.SleepSummary(inBed: 8.0, asleep: 7.4, rem: 1.6, core: 4.5, deep: 1.3,
                                            awake: 0.4, awakenings: 2, efficiency: 0.92, wake: now)
        return HealthData.Reading(
            queriedAt: now,
            hrv: .init(value: 74, date: now),
            restingHR: .init(value: 51, date: now),
            bodyMass: .init(value: 205, date: now),
            bodyFat: .init(value: 0.16, date: now),
            height: .init(value: 71, date: now),
            sleepSummary: sleep,
            lastRunDate: Calendar.current.date(byAdding: .day, value: -1, to: now),
            lastRunKm: 8.0,
            lastRunMinutes: 41)
    }

    /// Synthetic readiness (steady — good HRV/sleep, vitals in range).
    static func readiness() -> ReadinessResult {
        let comps = [
            ReadinessComponent(label: "HRV", value: 74, unit: "ms", z: 0.9, weight: 0.35, personal: true),
            ReadinessComponent(label: "Resting HR", value: 51, unit: "bpm", z: 0.7, weight: 0.20, personal: true),
            ReadinessComponent(label: "Sleep", value: 7.4, unit: "h", z: 0.6, weight: 0.20, personal: false),
        ]
        let recovery = RecoveryResult(
            state: .steady, headline: "Steady",
            body: "HRV and resting HR are both in your normal range. Nothing flagged. Train as planned.",
            hrvZ: 0.9, rhrZ: -0.6,
            hrv: AxisRange(today: 74, low: 58, high: 92, unit: "ms", higherIsBetter: true),
            rhr: AxisRange(today: 51, low: 47, high: 57, unit: "bpm", higherIsBetter: false),
            orbHint: RecoveryState.steady.orbHint)
        return ReadinessResult(score: 73, components: comps, recovery: recovery, cappedGreen: false,
                               atl: 56, ctl: 61, form: 5, ratio: 0.92, hrMax: 188,
                               lastHardPct: nil, lastHardHoursAgo: nil)
    }

    // MARK: Populate (called from AppModel.refresh in demo mode)

    /// Clear the SwiftData stores so every demo session starts clean (called once on launch).
    @MainActor
    static func wipeStores(context: ModelContext) {
        func deleteAll<T: PersistentModel>(_ t: T.Type) { (try? context.fetch(FetchDescriptor<T>()))?.forEach { context.delete($0) } }
        deleteAll(TrainingSession.self); deleteAll(PlannedWorkout.self); deleteAll(DailyReadiness.self)
        deleteAll(Baseline.self); deleteAll(DiagnosisRecord.self); deleteAll(HealthSnapshot.self)
        try? context.save()
    }

    /// Populate live vitals + history after the viewer finishes onboarding (their own answers stay).
    @MainActor
    static func populate(model: AppModel, context: ModelContext) {
        model.reading = reading()
        model.readiness = readiness()
        let dx = DiagnosisEngine.diagnose(DiagnosisInput(
            bodyweightLb: model.settings.bodyweightLb > 0 ? model.settings.bodyweightLb : 205,
            heightIn: model.effectiveHeightIn ?? 71,
            bodyFatPct: model.effectiveBodyFatPct ?? 16,
            raceLeanBodyFatPct: model.settings.raceLeanBodyFatPct,
            recent5k: DiagnosisEngine.parse5k(model.settings.recent5k),
            strengthAxis: model.settings.strengthAxis,
            goal5k: PlanEngine.goalFresh5kSeconds(model.settings) ?? 22 * 60))
        model.diagnosis = dx
        model.reseedGoals(for: dx.profile)
        model.status = "Demo · sample data"

        if (try? context.fetchCount(FetchDescriptor<TrainingSession>())) == 0 {
            seedWorkouts(context)
            seedReadinessLog(context)
            seedDiagnosisTrail(context, current: dx)
            try? context.save()
        }
        PlannedWorkout.seedIfNeeded(profile: dx.profile, settings: model.settings, context: context)
    }

    // MARK: Store seeds

    private static func seedWorkouts(_ context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // A repeating training week, replayed over the past 6 weeks with light variation.
        let week: [(day: Int, cat: SessionCategory, title: String, km: Double?, min: Int, cal: Double, avg: Int, max: Int, rpe: Int)] = [
            (1, .run, "Tempo run + strides", 8, 42, 540, 162, 178, 7),
            (2, .strength, "Heavy lower + carries", nil, 45, 320, 118, 150, 6),
            (3, .run, "Easy aerobic run", 8, 44, 470, 138, 150, 4),
            (5, .sim, "Station circuit", nil, 50, 600, 156, 181, 8),
            (6, .run, "Long aerobic run", 14, 78, 880, 142, 156, 5),
        ]
        for w in 0..<6 {
            let drift = Double(6 - w)   // older weeks slightly easier/slower
            for s in week {
                let daysAgo = w * 7 + (7 - s.day)
                guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today.addingTimeInterval(7 * 3600)) else { continue }
                let km = s.km.map { ($0 - drift * 0.3).rounded() }
                let session = TrainingSession(
                    healthkitUUID: nil, date: date, category: s.cat.rawValue, title: s.title,
                    durationMin: s.min - Int(drift), distanceKm: km,
                    caloriesKcal: s.cal - drift * 10, avgHR: s.avg, maxHR: s.max, rpe: s.rpe, source: .healthkit)
                context.insert(session)
            }
        }
    }

    private static func seedReadinessLog(_ context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let scores = [62, 58, 64, 70, 66, 60, 55, 68, 72, 74, 69, 63, 59, 71, 76, 73, 67, 61, 70, 78,
                      75, 72, 66, 64, 73, 80, 77, 71, 68, 73]
        for (i, score) in scores.enumerated() {
            guard let day = cal.date(byAdding: .day, value: -(scores.count - 1 - i), to: today) else { continue }
            let hrv = 60.0 + Double(score - 60) * 0.6
            context.insert(DailyReadiness(day: day, score: score, hrv: hrv,
                                          ctl: 55 + Double(i) * 0.2, atl: 52 + Double(i % 5),
                                          form: Double(i % 7) - 3, acr: 0.9 + Double(i % 4) * 0.05))
        }
    }

    /// A short path of past quadrant positions trending toward the strong/fast corner.
    private static func seedDiagnosisTrail(_ context: ModelContext, current: Diagnosis) {
        let cal = Calendar.current
        let earlier: [(daysAgo: Int, bw: Double, bf: Double, t: String)] = [
            (84, 218, 22, "25:10"), (56, 213, 20, "24:20"), (28, 209, 18, "23:40"),
        ]
        for e in earlier {
            let dx = DiagnosisEngine.diagnose(DiagnosisInput(bodyweightLb: e.bw, heightIn: 71,
                                                             bodyFatPct: e.bf, raceLeanBodyFatPct: 12,
                                                             recent5k: DiagnosisEngine.parse5k(e.t),
                                                             strengthAxis: 0.72,
                                                             goal5k: PlanEngine.goalFresh5kSeconds(sampleSettings) ?? 22 * 60))
            let date = cal.date(byAdding: .day, value: -e.daysAgo, to: Date()) ?? Date()
            context.insert(DiagnosisRecord(dx, date: date))
        }
        context.insert(DiagnosisRecord(current))
    }
}
