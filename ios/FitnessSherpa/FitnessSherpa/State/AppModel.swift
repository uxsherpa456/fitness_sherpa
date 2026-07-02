//  AppModel.swift
//  Ravns
//
//  Shared observable state: reads HealthKit, runs the DiagnosisEngine, persists to SwiftData,
//  and exposes the current reading + diagnosis to every tab. Replaces the per-view logic that
//  lived in the old ContentView milestone harness.

import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppModel {
    var reading: HealthData.Reading?
    var diagnosis: Diagnosis?
    var readiness: ReadinessResult?
    var status = "Reading Health…"
    var loading = false
    var showingMenu = false          // global left hamburger menu
    var lastWorkoutSync: Date?
    var settings = UserSettings.load()

    init() {
        // Screenshot mode (simulator + `-screenshots YES`): land straight in the populated app as the
        // sample athlete, so marketing/prototype captures skip onboarding.
        if DemoSeed.isScreenshot {
            settings = DemoSeed.sampleSettings
            settings.save()
        } else if DemoSeed.isDemo {
            // The web demo always begins as a brand-new athlete: clear the un-onboarded gate + the
            // "fields pre-fill" flag synchronously so onboarding shows blank with no flash. (SwiftData
            // rows are wiped in RootView's .task, which has a ModelContext.)
            let d = UserDefaults.standard
            ["onboardedBefore", RootView.pendingTourKey].forEach { d.removeObject(forKey: $0) }
            settings = UserSettings()
            settings.save()
        }
    }

    /// Import + reconcile recent workouts from HealthKit, skipping if synced very recently (dedups
    /// the launch refresh vs. opening the Plan tab). `force` bypasses the gate (pull-to-refresh).
    func importWorkouts(context: ModelContext, force: Bool) async {
        if !force, let last = lastWorkoutSync, Date().timeIntervalSince(last) < 20 { return }
        let workouts = (try? await HealthData.recentWorkouts(days: 365)) ?? []
        TrainingSession.reconcile(workouts, context: context)
        lastWorkoutSync = Date()
    }
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

    /// Replace the goal set to match a (re)diagnosed profile, then fill live currents. Used by
    /// onboarding / re-running the baseline, where the profile (and thus the right metrics) can change.
    func reseedGoals(for profile: AthleteProfile?) {
        goals = GoalLibrary.seed(for: profile)
        refreshGoals()
    }

    /// Bodyweight for the diagnosis + goals: Apple Health wins; otherwise the manually-entered value.
    var effectiveBodyweightLb: Double? {
        reading?.bodyMass?.value ?? (settings.bodyweightLb > 0 ? settings.bodyweightLb : nil)
    }
    var effectiveBodyFatPct: Double? {
        reading?.bodyFat.map { $0.value * 100 } ?? (settings.bodyFatPct > 0 ? settings.bodyFatPct : nil)
    }
    /// Standing height (in) for BMI on the run axis: Apple Health wins; otherwise the entered value.
    var effectiveHeightIn: Double? {
        reading?.height?.value ?? (settings.heightIn > 0 ? settings.heightIn : nil)
    }

    /// Seed the four profile goals if none exist, then update current values from live data.
    func refreshGoals() {
        if goals.isEmpty { goals = GoalLibrary.seed(for: diagnosis?.profile) }
        for i in goals.indices {
            switch goals[i].key {
            case "weight":  if let w = effectiveBodyweightLb { goals[i].current = .number(w.rounded()) }
            case "bodyfat": if let bf = effectiveBodyFatPct { goals[i].current = .number(bf.rounded()) }
            case "fivek":   goals[i].current = .text(settings.recent5k)
            default: break
            }
        }
        saveGoals()
    }

    // MARK: Cloud sync (StateClient ↔ app_state row)

    /// Pull the durable copy on launch — cloud wins when it has data (carries across devices/prototype).
    /// Workout + readiness history is restored only into an empty local store, so it repopulates a
    /// fresh/reset device without clobbering one that already has data.
    func bootstrapCloud(context: ModelContext? = nil) async {
        if DemoSeed.isDemo { return }   // demo runs on synthetic data, never the real cloud row
        guard let state = try? await StateClient.load(), state.updated_at != nil else { return }
        var s = settings
        s.apply(state.settings)
        if state.onboarded { s.onboarded = true }   // a returning/synced athlete skips onboarding
        settings = s
        s.save()
        if !state.goals.isEmpty { goals = state.goals; saveGoals() }

        guard let context else { return }
        if (try? context.fetchCount(FetchDescriptor<TrainingSession>())) == 0, !state.sessions.isEmpty {
            state.sessions.forEach { context.insert($0.makeModel()) }
        }
        if (try? context.fetchCount(FetchDescriptor<DailyReadiness>())) == 0, !state.readiness.isEmpty {
            state.readiness.forEach { context.insert($0.makeModel()) }
        }
        try? context.save()
    }

    /// The user-authored history worth syncing: manual or edited workouts (the rest re-imports from
    /// HealthKit) + every readiness-log day (which can't be reconstructed).
    private func gatherHistory(context: ModelContext) -> (sessions: [SessionDTO], readiness: [ReadinessDTO]) {
        let sessions = ((try? context.fetch(FetchDescriptor<TrainingSession>())) ?? [])
            .filter { $0.isManual || $0.isEdited }.map(SessionDTO.init)
        let readiness = ((try? context.fetch(FetchDescriptor<DailyReadiness>())) ?? []).map(ReadinessDTO.init)
        return (sessions, readiness)
    }

    /// Mirror workout + readiness history up (fire-and-forget). The backend merges, so this never
    /// touches settings/goals.
    func pushHistory(context: ModelContext) {
        let (sessions, readiness) = gatherHistory(context: context)
        let s = settings, g = goals
        Task {
            let state = AppState(onboarded: true, profile: s.toProfile(), goals: g,
                                 settings: s.toAppSettings(), sessions: sessions, readiness: readiness)
            try? await StateClient.save(state, includeHistory: true)
        }
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

    // MARK: Sandbox — experience the app as a brand-new user without losing your data

    var inSandbox: Bool { StateClient.isSandbox }

    /// Start a fresh new-user experience. From your real data: back it up to the live cloud row first,
    /// then isolate onto the sandbox key. Already in the sandbox: just clear it again. Either way the
    /// sandbox row + local store are wiped so onboarding runs from scratch (and stays fresh on relaunch).
    @MainActor
    func resetToFreshUser(context: ModelContext) async {
        if !StateClient.isSandbox {
            // Back the real profile + history up to the LIVE row and wait, so the backup lands first.
            StateClient.userKey = StateClient.liveKey
            let history = gatherHistory(context: context)
            let backup = AppState(onboarded: true, profile: settings.toProfile(), goals: goals,
                                  settings: settings.toAppSettings(), sessions: history.sessions, readiness: history.readiness)
            try? await StateClient.save(backup, includeHistory: true)
            StateClient.userKey = StateClient.sandboxKey
        }
        // Clear the sandbox cloud row so a fresh onboarding persists across relaunches.
        try? await StateClient.save(AppState(onboarded: false), includeHistory: true)
        wipeLocal(context: context)
        settings = UserSettings()        // onboarded == false
        goals = []; diagnosis = nil; reading = nil; readiness = nil
        feelingRaw = nil; status = ""
        showingMenu = false              // so onboarding + the tour start with the menu closed
        saveSettings(); saveGoals()
    }

    /// Switch back to the live cloud row and restore settings + goals from it (workouts re-import
    /// from HealthKit; the plan regenerates).
    @MainActor
    func restoreMyData(context: ModelContext) async {
        StateClient.userKey = StateClient.liveKey
        wipeLocal(context: context)
        settings = UserSettings(); goals = []
        showingMenu = false
        await bootstrapCloud(context: context)   // restores settings + goals + history
        await refresh(context: context)
    }

    private func wipeLocal(context: ModelContext) {
        let d = UserDefaults.standard
        ["userSettings.v1", "goals.v1", "onboardedBefore"].forEach { d.removeObject(forKey: $0) }
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("feeling.") { d.removeObject(forKey: key) }
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            if let rows = try? context.fetch(FetchDescriptor<T>()) { rows.forEach { context.delete($0) } }
        }
        deleteAll(TrainingSession.self); deleteAll(PlannedWorkout.self); deleteAll(DailyReadiness.self)
        deleteAll(Baseline.self); deleteAll(DiagnosisRecord.self); deleteAll(HealthSnapshot.self)
        try? context.save()
    }

    // MARK: Subjective feeling (per day)

    var todayFeeling: Feeling? { feelingRaw.flatMap(Feeling.init) }

    func setFeeling(_ f: Feeling) {
        feelingRaw = f.rawValue
        UserDefaults.standard.set(f.rawValue, forKey: Self.feelingKey)
    }

    private static var feelingKey: String {
        "feeling." + DateFormatters.ymd.string(from: Date())
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
    func coachContext(recentWorkouts: [TrainingSession] = [], plan: [PlannedWorkout] = [],
                      readinessLog: [DailyReadiness] = []) -> [String: Any] {
        let iso = ISO8601DateFormatter()

        var metrics: [String: Any] = ["recent_5k": settings.recent5k,
                                      "stations_hold": settings.stationsHold,
                                      "strength_axis": (settings.strengthAxis * 100).rounded() / 100]
        if let bw = effectiveBodyweightLb { metrics["bodyweight_lb"] = Int(bw.rounded()) }
        if let ht = effectiveHeightIn { metrics["height_in"] = (ht * 10).rounded() / 10 }
        if let bf = effectiveBodyFatPct { metrics["body_fat_pct"] = (bf * 10).rounded() / 10 }
        if let g5k = PlanEngine.goalFresh5kSeconds(settings) {   // fresh-5K fitness the goal finish implies (run-axis anchor)
            metrics["goal_5k"] = DiagnosisEngine.format5k(g5k)
        }
        if let dx = diagnosis {   // Daniels VDOT + BMI that drive the run axis (height-normalized)
            if dx.vdot > 0 { metrics["vdot"] = Int(dx.vdot.rounded()) }
            if dx.bmi > 0 { metrics["bmi"] = (dx.bmi * 10).rounded() / 10 }
        }
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
            "scheduled": !settings.noRace,
        ]
        if settings.noRace {
            race["goal_date"] = settings.raceDate   // no booked race — training toward this date
        } else {
            race["date"] = settings.raceDate
            race["location"] = settings.raceLocation
        }
        if let days = settings.daysToRace { race["days_out"] = days }
        ctx["race"] = race

        if let m = settings.mobilityFlag {   // advisory: gates station execution (wall-ball depth, lunges, burpees)
            ctx["mobility"] = ["flag": m.rawValue, "note": m.read]
        }

        // Athlete-entered barbell 1-rep maxes (in their preferred unit) — strength / station-capacity signal.
        let lifts = Lift.allCases.reduce(into: [String: String]()) { acc, lift in
            if let lb = settings.liftMaxesLb[lift.rawValue], let disp = Units.displayWeight(lb: lb, settings) {
                acc[lift.label] = disp
            }
        }
        if !lifts.isEmpty { ctx["lifts"] = lifts }

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
            if !rd.pillars.isEmpty {   // the on-screen ledger — cite these when explaining the score
                r["score_ledger"] = rd.pillars.map { p -> [String: Any] in
                    ["pillar": p.label, "status": p.status,
                     "points": Int(p.points.rounded()), "of": Int(p.weight.rounded())]
                }
            }
            if !rd.flags.isEmpty { r["flags"] = rd.flags }
            if let rec = rd.recovery {
                var rr: [String: Any] = ["state": rec.state.key, "readout": rec.headline]
                if let z = rec.hrvZ { rr["hrv_log_z"] = (z * 100).rounded() / 100 }
                if let z = rec.rhrZ { rr["rhr_z"] = (z * 100).rounded() / 100 }
                if let a = rec.hrv {
                    rr["hrv"] = ["today": Int(a.today.rounded()),
                                 "normal_low": Int(a.low.rounded()), "normal_high": Int(a.high.rounded()), "unit": "ms"]
                }
                if let a = rec.rhr {
                    rr["rhr"] = ["today": Int(a.today.rounded()),
                                 "normal_low": Int(a.low.rounded()), "normal_high": Int(a.high.rounded()), "unit": "bpm"]
                }
                r["recovery"] = rr   // two-axis HRV/RHR readout (log-normal HRV vs own morning baseline)
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
                "goal_focus": d.goalFocus,   // what to work on, relative to the goal finish
                "goal_readiness_pct": Int((d.goalReadiness * 100).rounded()),
                "pace_readiness_pct": Int((d.paceReadiness * 100).rounded()),     // 5k fitness alone vs goal
                "run_readiness_pct": Int((d.runReadiness * 100).rounded()),       // 5k fitness + power-to-weight credit
                "strength_readiness_pct": Int((d.strengthReadiness * 100).rounded()), // strength vs division standard
                "race_weight_lb_away": Int(d.raceWeightLbAway.rounded()),         // lb of fat above race-weight target
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

        // TRENDS — direction over time, so the coach reasons about the trajectory, not just today.
        let log = readinessLog.sorted { $0.day < $1.day }   // oldest → newest
        var trends: [String: Any] = [:]

        func dir(_ delta: Double, eps: Double) -> String {
            delta > eps ? "rising" : (delta < -eps ? "falling" : "flat")
        }
        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

        if log.count >= 4 {
            let scores = log.map { Double($0.score) }
            let recent = Array(scores.suffix(7)), prior = Array(scores.dropLast(7).suffix(7))
            if let r = avg(recent), let p = avg(prior) {
                trends["readiness"] = ["recent_7d_avg": Int(r.rounded()),
                                       "prior_7d_avg": Int(p.rounded()),
                                       "direction": dir(r - p, eps: 1.5),
                                       "series_14d": log.suffix(14).map { $0.score }]
            }
            let hrvs = log.compactMap { $0.hrv > 0 ? $0.hrv : nil }
            if let r = avg(Array(hrvs.suffix(7))), let p = avg(Array(hrvs.dropLast(7).suffix(7))) {
                trends["hrv"] = ["recent_7d_avg": Int(r.rounded()), "prior_7d_avg": Int(p.rounded()),
                                 "direction": dir(r - p, eps: 1.0)]
            }
            if let nowCtl = log.last?.ctl, let thenCtl = log.suffix(15).first?.ctl {
                trends["fitness_ctl"] = ["now": (nowCtl * 10).rounded() / 10,
                                         "two_weeks_ago": (thenCtl * 10).rounded() / 10,
                                         "direction": dir(nowCtl - thenCtl, eps: 1.0),
                                         "current_form": ((log.last?.form ?? 0) * 10).rounded() / 10]
            }
        }

        // Weekly run volume over the last 4 weeks (km), newest week first.
        let runs = recentWorkouts.filter { $0.cat == .run }
        if !runs.isEmpty {
            let now = Date()
            var weekly = [Double](repeating: 0, count: 4)
            for s in runs {
                let wk = Int(now.timeIntervalSince(s.date) / (7 * 86400))
                if wk >= 0, wk < 4, let km = s.distanceKm { weekly[wk] += km }
            }
            trends["weekly_run_km"] = weekly.map { ($0 * 10).rounded() / 10 }
        }

        if !trends.isEmpty { ctx["trends"] = trends }

        // Running economy: self-relative aerobic efficiency (pace per heartbeat) vs the athlete's own
        // 28-day baseline, plus the Z2 floor + VDOT ceiling — the levers for getting faster.
        let eco = RunningEconomy.compute(sessions: recentWorkouts, restingHR: reading?.restingHR?.value,
                                         age: settings.age, recent5k: DiagnosisEngine.parse5k(settings.recent5k))
        if eco.validCount > 0 {
            let unit = Units.distanceUnit(settings)
            var e: [String: Any] = ["valid_samples": eco.validCount, "building_baseline": eco.building,
                                    "vdot": Int(eco.vdot.rounded())]
            if let i = eco.index { e["economy_index"] = Int(i.rounded()) }   // 50 = own baseline; >50 improving
            if let d = eco.deltaPts { e["delta_pts_4wk"] = Int(d.rounded()) }
            if let z = eco.z2PaceSecPerKm { e["z2_pace"] = RunningEconomy.paceLabel(z, unit: unit) }
            if let hr = eco.hrAtZ2 { e["hr_at_z2"] = hr }
            if let g = PlanEngine.goalFresh5kSeconds(settings) {
                e["goal_z2_pace"] = RunningEconomy.paceLabel(g / 5 + 70, unit: unit)
                e["goal_vdot"] = Int(DiagnosisEngine.vdot(seconds: g).rounded())
            }
            ctx["running_economy"] = e
        }
        return ctx
    }

    /// Read Health, diagnose, persist (deduped). Safe to call repeatedly.
    func refresh(context: ModelContext) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if DemoSeed.isDemo { DemoSeed.populate(model: self, context: context); return }
        do {
            try await HealthData.requestAuthorization()
            let r = try await HealthData.readSnapshot()
            reading = r

            // Reconcile workouts into the store, then compute training load + readiness.
            await importWorkouts(context: context, force: true)
            let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
            let load = TrainingLoad.compute(sessions: sessions, restingHR: r.restingHR?.value, age: settings.age)
            readiness = await ReadinessEngine.compute(reading: r, load: load)
            logDailyReadiness(context: context, reading: r, load: load)

            let baseline = Baseline(bodyweightLb: r.bodyMass?.value,
                                    recent5kSeconds: DiagnosisEngine.parse5k(settings.recent5k),
                                    stationsHold: settings.stationsHold)
            // Diagnose off the precise continuous strength axis (the boolean Baseline snapshot is for history).
            let input = DiagnosisInput(bodyweightLb: effectiveBodyweightLb ?? 214,
                                       heightIn: effectiveHeightIn ?? 0,
                                       bodyFatPct: effectiveBodyFatPct ?? 0,
                                       raceLeanBodyFatPct: settings.raceLeanBodyFatPct,
                                       recent5k: DiagnosisEngine.parse5k(settings.recent5k),
                                       strengthAxis: settings.strengthAxis,
                                       goal5k: PlanEngine.goalFresh5kSeconds(settings) ?? 22 * 60)
            let dx = DiagnosisEngine.diagnose(input)
            diagnosis = dx
            refreshGoals()
            PlannedWorkout.seedIfNeeded(profile: dx.profile, settings: settings, context: context)   // so Today + Plan share one plan

            persist(reading: r, baseline: baseline, diagnosis: dx, context: context)

            status = r.readinessFresh
                ? "Recovery data fresh ✓"
                : "Readiness not trusted — stale/missing: \(r.staleMetrics.joined(separator: ", "))."

            pushHistory(context: context)   // keep the cloud's workout + readiness history current
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
