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
    var readiness: ReadinessResult?
    var status = "Reading Health…"
    var loading = false
    var showingMenu = false          // global left hamburger menu
    var settings = UserSettings.load()
    var feelingRaw: String? = AppModel.loadFeeling()
    var goals: [GoalArc] = AppModel.loadGoals()

    func saveSettings() { settings.save() }

    // MARK: Goals (focus-metric arcs)

    private static func loadGoals() -> [GoalArc] {
        guard let d = UserDefaults.standard.data(forKey: "goals.v1"),
              let g = try? JSONDecoder().decode([GoalArc].self, from: d) else { return [] }
        return g
    }
    func saveGoals() {
        if let d = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(d, forKey: "goals.v1") }
    }

    /// Seed the four profile goals if none exist, then update current values from live data.
    func refreshGoals() {
        if goals.isEmpty { goals = GoalLibrary.seed(for: diagnosis?.profile) }
        for i in goals.indices {
            switch goals[i].key {
            case "weight":  if let w = reading?.bodyMass?.value { goals[i].current = .number(w.rounded()) }
            case "bodyfat": if let bf = reading?.bodyFat?.value { goals[i].current = .number((bf * 100).rounded()) }
            case "fivek":   goals[i].current = .text(Self.manual5k)
            default: break
            }
        }
        saveGoals()
    }

    // MARK: Cloud sync (StateClient ↔ app_state row)

    /// Pull the durable copy on launch — cloud wins when it has data (carries across devices/prototype).
    func bootstrapCloud() async {
        guard let state = try? await StateClient.load(), state.updated_at != nil else { return }
        var s = settings
        s.apply(state.settings)
        settings = s
        s.save()
        if !state.goals.isEmpty { goals = state.goals; saveGoals() }
    }

    /// Mirror settings + goals up after an edit.
    func pushToCloud() {
        let snapshot = settings
        let goalsSnapshot = goals
        Task {
            let state = AppState(onboarded: true, profile: snapshot.toProfile(),
                                 goals: goalsSnapshot, settings: snapshot.toAppSettings())
            try? await StateClient.save(state)
        }
    }

    // MARK: Subjective feeling (per day)

    var todayFeeling: Feeling? { feelingRaw.flatMap(Feeling.init) }

    func setFeeling(_ f: Feeling) {
        feelingRaw = f.rawValue
        UserDefaults.standard.set(f.rawValue, forKey: Self.feelingKey)
    }

    private static var feelingKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "feeling." + f.string(from: Date())
    }
    private static func loadFeeling() -> String? { UserDefaults.standard.string(forKey: feelingKey) }

    /// Final readiness: the objective score scaled by today's feeling, with the no-GREEN cap held.
    var readinessScore: Int? {
        guard let rd = readiness, let base = rd.score else { return nil }
        var s = Double(base)
        if let f = todayFeeling { s *= f.multiplier }
        if rd.cappedGreen { s = min(s, 74) }
        return Int(min(100, max(0, s.rounded())))
    }

    /// The freshness-stamped snapshot the coach reasons over (matches the Edge Function contract).
    /// `workouts` lets the coach adapt off recent training load (calories, HR, effort).
    func coachContext(recentWorkouts: [TrainingSession] = [], plan: [PlannedWorkout] = []) -> [String: Any] {
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

        if let rd = readiness {
            func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
            var r: [String: Any] = ["baseline_relative": true]
            if let s = readinessScore { r["score"] = s }
            if let f = todayFeeling { r["how_you_feel"] = f.rawValue }
            r["fitness_ctl"] = r1(rd.ctl)
            r["fatigue_atl"] = r1(rd.atl)
            r["form"] = r1(rd.form)
            r["acute_chronic_load"] = r1(rd.ratio)
            r["hr_max"] = rd.hrMax
            if rd.cappedGreen { r["note"] = "near-max effort in last 24h — capped below GREEN" }
            if let pct = rd.lastHardPct, let h = rd.lastHardHoursAgo {
                r["last_hard_effort"] = ["pct_hrmax": Int((pct * 100).rounded()), "hours_ago": Int(h.rounded())]
            }
            r["components"] = rd.components.map { c -> [String: Any] in
                ["metric": c.label, "value": r1(c.value),
                 "unit": c.unit, "z_vs_baseline": (c.z * 100).rounded() / 100,
                 "source": c.personal ? "personal_baseline" : "population_prior"]
            }
            ctx["readiness"] = r
        }

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

        if !goals.isEmpty {
            ctx["goals"] = goals.map { g -> [String: Any] in
                var d: [String: Any] = ["key": g.key,
                                        "current": g.current?.display ?? "",
                                        "target": g.goal?.display ?? ""]
                if let l = g.label { d["label"] = l }
                if let u = g.unit, !u.isEmpty { d["unit"] = u }
                if let b = g.better { d["better"] = b }
                return d
            }
        }

        if !plan.isEmpty {
            ctx["plan"] = plan.prefix(10).map { p -> [String: Any] in
                var d: [String: Any] = [
                    "date": iso.string(from: p.date),
                    "type": p.type, "name": p.name, "meta": p.meta,
                    "intent": p.intent.rawValue, "completed": p.completed,
                    "source": p.source.rawValue, "phase": p.phase,
                ]
                if let z = p.targetZone { d["target_zone"] = z }
                if let s = p.stations { d["stations"] = s }
                return d
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

            // Reconcile workouts into the store, then compute training load + readiness.
            let workouts = (try? await HealthData.recentWorkouts(days: 365)) ?? []
            TrainingSession.reconcile(workouts, context: context)
            let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
            let load = TrainingLoad.compute(sessions: sessions, restingHR: r.restingHR?.value, age: settings.age)
            readiness = await ReadinessEngine.compute(reading: r, load: load)
            logDailyReadiness(context: context, reading: r, load: load)

            let baseline = Baseline(bodyweightLb: r.bodyMass?.value,
                                    recent5kSeconds: DiagnosisEngine.parse5k(Self.manual5k),
                                    stationsHold: true)
            let dx = DiagnosisEngine.diagnose(baseline.asInput())
            diagnosis = dx
            refreshGoals()

            persist(reading: r, baseline: baseline, diagnosis: dx, context: context)

            status = r.readinessFresh
                ? "Recovery data fresh ✓"
                : "Readiness not trusted — stale/missing: \(r.staleMetrics.joined(separator: ", "))."
        } catch {
            status = "Error: \(error.localizedDescription)"
            print("AppModel.refresh error: \(error)")
        }
    }

    /// Upsert one readiness row for today (the trend that can't be reconstructed from Health).
    private func logDailyReadiness(context: ModelContext, reading r: HealthData.Reading, load: LoadResult) {
        guard let score = readinessScore else { return }
        let day = Calendar.current.startOfDay(for: Date())
        var desc = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.day == day })
        desc.fetchLimit = 1
        let row = (try? context.fetch(desc))?.first
        if let row {
            row.score = score; row.hrv = r.hrv?.value ?? row.hrv
            row.ctl = load.ctl; row.atl = load.atl; row.form = load.form; row.acr = load.ratio
        } else {
            context.insert(DailyReadiness(day: day, score: score, hrv: r.hrv?.value ?? 0,
                                          ctl: load.ctl, atl: load.atl, form: load.form, acr: load.ratio))
        }
        try? context.save()
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
