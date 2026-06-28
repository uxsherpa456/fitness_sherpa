//  AppModel.swift
//  Fitness Sherpa
//
//  Shared observable state: reads HealthKit, runs the DiagnosisEngine, persists to SwiftData,
//  and exposes the current reading + diagnosis to every tab. Replaces the per-view logic that
//  lived in the old ContentView milestone harness.

import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppModel {
    /// Chip-timed 5k PR — manual for now (a race result, not in HealthKit). Moves to onboarding later.
    static let manual5k = "24:31"

    var reading: HealthData.Reading?
    var diagnosis: Diagnosis?
    var status = "Reading Health…"
    var loading = false
    var settings = UserSettings.load()

    func saveSettings() { settings.save() }

    var readinessScore: Int? {
        Readiness.score(hrv: reading?.hrv?.value,
                        restingHR: reading?.restingHR?.value,
                        sleepHrs: reading?.sleep?.value)
    }

    /// The freshness-stamped snapshot the coach reasons over (matches the Edge Function contract).
    /// `workouts` lets the coach adapt off recent training load (calories, HR, effort).
    func coachContext(recentWorkouts: [TrainingSession] = []) -> [String: Any] {
        let iso = ISO8601DateFormatter()

        var metrics: [String: Any] = ["recent_5k": Self.manual5k, "stations_hold": true]
        if let bw = reading?.bodyMass?.value { metrics["bodyweight_lb"] = Int(bw.rounded()) }
        if let hrv = reading?.hrv?.value { metrics["hrv_ms"] = Int(hrv.rounded()) }
        if let rhr = reading?.restingHR?.value { metrics["resting_hr_bpm"] = Int(rhr.rounded()) }
        if let sleep = reading?.sleep?.value { metrics["sleep_hrs"] = (sleep * 10).rounded() / 10 }
        if let s = readinessScore { metrics["readiness_score"] = s }

        var ctx: [String: Any] = [
            "metrics": metrics,
            "nutrition": ["goal": "lose", "training_day": "quality"],
            "demographics": [
                "format": settings.format,
                "gender": settings.gender,
                "tier": settings.tier,
                "age": settings.age,
            ],
        ]

        var race: [String: Any] = [
            "goal_time": settings.goalTime,
            "date": settings.raceDate,
            "location": settings.raceLocation,
        ]
        if let days = settings.daysToRace { race["days_out"] = days }
        ctx["race"] = race

        if let r = reading {
            let mins = Int(Date().timeIntervalSince(r.queriedAt) / 60)
            ctx["freshness"] = [
                "checked": "\(mins)m ago",
                "checked_at": iso.string(from: r.queriedAt),
                "readiness_fresh": r.readinessFresh,
                "stale_or_missing": r.staleMetrics,
            ]
            if let date = r.lastRunDate {
                var lr: [String: Any] = ["when": iso.string(from: date)]
                if let km = r.lastRunKm { lr["km"] = (km * 100).rounded() / 100 }
                if let m = r.lastRunMinutes { lr["minutes"] = Int(m.rounded()) }
                ctx["last_run"] = lr
            }
        }

        if let s = reading?.sleepSummary {
            func h(_ v: Double) -> Double { (v * 10).rounded() / 10 }
            ctx["sleep"] = [
                "asleep_hrs": h(s.asleep),
                "rem_hrs": h(s.rem),
                "core_hrs": h(s.core),
                "deep_hrs": h(s.deep),
                "awake_hrs": h(s.awake),
                "in_bed_hrs": h(s.inBed),
                "efficiency_pct": Int((s.efficiency * 100).rounded()),
                "awakenings": s.awakenings,
            ]
        }

        if let d = diagnosis {
            ctx["diagnosis"] = [
                "profile": d.profile.title,
                "limiter": d.limiter,
                "focus": d.focus,
                "marker": ["x": Int((d.markerX * 100).rounded()), "y": Int((d.markerY * 100).rounded())],
                "evidence": d.evidence,
            ]
        }

        if !recentWorkouts.isEmpty {
            ctx["recent_workouts"] = recentWorkouts.prefix(12).map { s -> [String: Any] in
                var w: [String: Any] = [
                    "date": iso.string(from: s.date),
                    "type": s.cat.label,
                    "duration_min": s.durationMin,
                    "source": s.isManual ? "manual" : (s.isEdited ? "edited" : "healthkit"),
                ]
                if let km = s.distanceKm { w["distance_km"] = (km * 100).rounded() / 100 }
                if let kcal = s.caloriesKcal { w["calories"] = Int(kcal.rounded()) }
                if let hr = s.avgHR { w["avg_hr"] = hr }
                if let mx = s.maxHR { w["max_hr"] = mx }
                if let rpe = s.rpe { w["rpe"] = rpe }
                return w
            }
        }
        return ctx
    }

    /// Read Health, diagnose, persist (deduped). Safe to call repeatedly.
    func refresh(context: ModelContext) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            try await HealthData.requestAuthorization()
            let r = try await HealthData.readSnapshot()
            reading = r

            let baseline = Baseline(bodyweightLb: r.bodyMass?.value,
                                    recent5kSeconds: DiagnosisEngine.parse5k(Self.manual5k),
                                    stationsHold: true)
            let dx = DiagnosisEngine.diagnose(baseline.asInput())
            diagnosis = dx

            persist(reading: r, baseline: baseline, diagnosis: dx, context: context)

            status = r.readinessFresh
                ? "Recovery data fresh ✓"
                : "Readiness not trusted — stale/missing: \(r.staleMetrics.joined(separator: ", "))."
        } catch {
            status = "Error: \(error.localizedDescription)"
            print("AppModel.refresh error: \(error)")
        }
    }

    /// Save a snapshot + (on change) a diagnosis & its baseline, skipping unchanged dupes.
    private func persist(reading r: HealthData.Reading, baseline: Baseline,
                         diagnosis dx: Diagnosis, context: ModelContext) {
        var snapDesc = FetchDescriptor<HealthSnapshot>(sortBy: [.init(\.capturedAt, order: .reverse)])
        snapDesc.fetchLimit = 1
        let lastSnap = try? context.fetch(snapDesc).first
        if lastSnap?.hrv != r.hrv?.value || lastSnap?.restingHR != r.restingHR?.value
            || lastSnap?.sleepHrs != r.sleep?.value {
            context.insert(HealthSnapshot(capturedAt: r.queriedAt,
                                          hrv: r.hrv?.value,
                                          restingHR: r.restingHR?.value,
                                          sleepHrs: r.sleep?.value,
                                          staleMetrics: r.staleMetrics))
        }

        var dxDesc = FetchDescriptor<DiagnosisRecord>(sortBy: [.init(\.date, order: .reverse)])
        dxDesc.fetchLimit = 1
        let lastDx = try? context.fetch(dxDesc).first
        if lastDx?.profileRaw != dx.profile.rawValue || lastDx?.evidence != dx.evidence {
            context.insert(DiagnosisRecord(dx))
            context.insert(baseline)
        }

        do { try context.save() } catch { print("Persist error: \(error)") }
    }
}
