//  PlanEngine.swift
//  Fitness Sherpa
//
//  A rule-based recommended training week derived from the athlete's diagnosis profile — the
//  future half of the Plan tab. Each session says WHY it exists (it moves the limiter), mirroring
//  the prototype's calendar. Heuristic v0: a real periodized plan comes later.

import SwiftUI

/// Session kind — shared by HealthKit workouts, manual sessions, and planned sessions for
/// consistent color/icon across the Plan tab.
enum SessionCategory: String, CaseIterable, Identifiable {
    case run, strength, hiit, sim, row, rest, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: return "Run"
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .sim: return "HYROX sim"
        case .row: return "Row"
        case .rest: return "Rest"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .run: return Palette.mint
        case .strength: return Palette.orange
        case .hiit, .sim: return Palette.red
        case .row: return Palette.yellow
        case .rest: return Palette.textFaint
        case .other: return Palette.textMuted
        }
    }

    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .hiit: return "bolt.fill"
        case .sim: return "flag.checkered"
        case .row: return "figure.rower"
        case .rest: return "moon.zzz.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct PlannedSession: Identifiable {
    let id = UUID()
    let dow: String           // "MON"
    let category: SessionCategory
    let type: String          // "TEMPO RUN"
    let name: String          // "Tempo run + strides"
    let meta: String          // "8 km tempo · 40 min · RPE 7"
    let why: String?          // why it moves the limiter
}

enum PlanEngine {
    /// A 7-day recommended week tailored to the profile's binding constraint.
    static func recommendedWeek(for profile: AthleteProfile?) -> [PlannedSession] {
        switch profile {
        case .heavySlowStrong:   // limiter: run pace + power-to-weight
            return [
                .init(dow: "MON", category: .run, type: "EASY RUN · Z2", name: "Aerobic base run",
                      meta: "8 km · easy", why: "Builds the engine that frees up race pace"),
                .init(dow: "TUE", category: .run, type: "TEMPO RUN", name: "Tempo run + strides",
                      meta: "8 km tempo · RPE 7", why: "Moves your limiter — run pace + power-to-weight"),
                .init(dow: "WED", category: .strength, type: "STRENGTH · MAINTAIN", name: "Maintenance lift",
                      meta: "30 min · 3 big lifts", why: "Strong enough for your division — strength is maintenance, not a focus"),
                .init(dow: "THU", category: .run, type: "THRESHOLD", name: "5 × 1 km intervals",
                      meta: "@ threshold · 90s rest", why: "Lifts the pace you can hold"),
                .init(dow: "FRI", category: .rest, type: "REST", name: "Rest day", meta: "recover", why: nil),
                .init(dow: "SAT", category: .sim, type: "HYROX SIM", name: "Stations + compromised runs",
                      meta: "4 × (1 km + station)", why: "Tests the fade — feeds the next re-diagnosis"),
                .init(dow: "SUN", category: .run, type: "LONG RUN · Z2", name: "Long aerobic run",
                      meta: "14 km · easy", why: "Volume that drops weight and builds base"),
            ]
        case .lightFastWeak:     // limiter: strength + station capacity
            return [
                .init(dow: "MON", category: .strength, type: "STRENGTH", name: "Heavy lower + core",
                      meta: "45 min · squat/deadlift", why: "Builds the strength your stations need"),
                .init(dow: "TUE", category: .run, type: "EASY RUN · Z2", name: "Aerobic base run",
                      meta: "8 km · easy", why: "Holds run volume steady while strength builds"),
                .init(dow: "WED", category: .sim, type: "STATION WORK", name: "Sled + wall ball circuit",
                      meta: "station capacity under fatigue", why: "Directly trains the limiter"),
                .init(dow: "THU", category: .strength, type: "STRENGTH", name: "Upper + grip",
                      meta: "40 min", why: "Grip + pull for farmers carry / sandbag"),
                .init(dow: "FRI", category: .rest, type: "REST", name: "Rest day", meta: "recover", why: nil),
                .init(dow: "SAT", category: .sim, type: "HYROX SIM", name: "Full station ladder",
                      meta: "race-pace stations", why: "Rehearses the compromised work"),
                .init(dow: "SUN", category: .run, type: "LONG RUN · Z2", name: "Long aerobic run",
                      meta: "12 km · easy", why: "Maintains the aerobic base"),
            ]
        case .goodAtEverything:  // limiter: integration + fatigue resistance
            return [
                .init(dow: "MON", category: .run, type: "EASY RUN · Z2", name: "Recovery run", meta: "6 km · easy", why: nil),
                .init(dow: "TUE", category: .sim, type: "RACE SIM", name: "Compromised running blocks",
                      meta: "run → station → run", why: "Trains integration under fatigue"),
                .init(dow: "WED", category: .strength, type: "STRENGTH", name: "Power maintenance", meta: "40 min", why: nil),
                .init(dow: "THU", category: .run, type: "THRESHOLD", name: "Pace work", meta: "race-pace intervals",
                      why: "Sharpens goal pace"),
                .init(dow: "FRI", category: .rest, type: "REST", name: "Rest day", meta: "recover", why: nil),
                .init(dow: "SAT", category: .sim, type: "FULL HYROX SIM", name: "Full simulation",
                      meta: "all 8 stations", why: "Dress rehearsal — pacing + fade"),
                .init(dow: "SUN", category: .run, type: "LONG RUN · Z2", name: "Long aerobic run", meta: "14 km · easy", why: nil),
            ]
        default:                 // weak at everything / no diagnosis: build general base
            return [
                .init(dow: "MON", category: .run, type: "EASY RUN · Z2", name: "Base run", meta: "5 km · easy",
                      why: "Fix the biggest deficit first — build the base"),
                .init(dow: "TUE", category: .strength, type: "STRENGTH", name: "Full-body strength", meta: "40 min", why: nil),
                .init(dow: "WED", category: .rest, type: "REST", name: "Rest day", meta: "recover", why: nil),
                .init(dow: "THU", category: .run, type: "EASY RUN · Z2", name: "Base run", meta: "6 km · easy", why: nil),
                .init(dow: "FRI", category: .strength, type: "STRENGTH", name: "Full-body strength", meta: "40 min", why: nil),
                .init(dow: "SAT", category: .sim, type: "INTRO SIM", name: "2 stations + runs",
                      meta: "easy pace", why: "Learn the movements, then re-diagnose"),
                .init(dow: "SUN", category: .rest, type: "REST", name: "Rest day", meta: "recover", why: nil),
            ]
        }
    }

    // MARK: - Full periodized plan (per-week session generation to race day)

    /// One generated session with its phase + week tag, ready to persist as a PlannedWorkout.
    struct GeneratedSession {
        let date: Date
        let category: SessionCategory
        let type: String
        let name: String
        let meta: String
        let intent: PlanIntent
        let zone: String?
        let why: String?
        let phase: TrainingPhase
        let weekNumber: Int
    }

    private enum Role { case easyRun, longRun, qualityRun, strength, sim, rest }

    /// Training paces for the athlete's distance unit. Easy/long/tempo/threshold come off the recent
    /// 5K; the **race pace is back-solved from the goal finish** — `(goal − station time) / 8 km` —
    /// so it reflects the time they're chasing, not just current 5K fitness.
    struct Paces {
        let easy: String, long: String, tempo: String, threshold: String, race: String, fiveK: String
        let goalAmbitious: Bool   // goal demands running at/above fresh-5K pace (clamped)
    }

    static func paces(_ settings: UserSettings) -> Paces? {
        let secs5k = DiagnosisEngine.parse5k(settings.recent5k)   // "24:31" → 1471 s
        guard secs5k > 0 else { return nil }
        let perKm5k = secs5k / 5.0
        let unit = Units.distanceUnit(settings)

        // Estimate total station + roxzone time, then the run pace the goal finish requires.
        var ambitious = false
        let racePerKm: Double = {
            guard let finish = parseFinishSeconds(settings.goalTime) else { return perKm5k + 28 }
            let perKm = (finish - goalStationSeconds(settings)) / 8.0
            if perKm < perKm5k { ambitious = true; return perKm5k }       // can't beat fresh-5K pace over compromised runs
            return perKm
        }()

        func fmt(_ secPerKm: Double) -> String {
            let p = secPerKm * (unit == "mi" ? 1.609344 : 1)
            let s = Int(p.rounded())
            return String(format: "%d:%02d/%@", s / 60, s % 60, unit)
        }
        return Paces(easy: fmt(perKm5k + 70), long: fmt(perKm5k + 62), tempo: fmt(perKm5k + 25),
                     threshold: fmt(perKm5k + 12), race: fmt(racePerKm), fiveK: fmt(perKm5k),
                     goalAmbitious: ambitious)
    }

    /// Station + roxzone time the goal finish implies (stronger athletes hold the stations faster;
    /// Pro singles carry heavier). Shared by the pace back-solve and the diagnosis goal anchor.
    private static func goalStationSeconds(_ settings: UserSettings) -> Double {
        let base = 1800.0                                                  // ~30 min stations + transitions baseline
        let strengthAdj = 1.25 - 0.4 * min(max(settings.strengthAxis, 0), 1)
        let proAdj = (settings.tier == "pro" && settings.format == "singles") ? 1.12 : 1.0
        return base * strengthAdj * proAdj
    }

    /// The fresh-5K time (seconds) the goal finish implies: race pace is back-solved from the goal
    /// `(finish − stations) / 8 km`, then un-compromised — a fresh 5K runs ~27 s/km faster than HYROX
    /// race-run pace. This anchors the diagnosis run axis to the *goal the athlete is chasing* rather
    /// than a fixed pace. `nil` if the goal can't be parsed.
    static func goalFresh5kSeconds(_ settings: UserSettings) -> Double? {
        guard let finish = parseFinishSeconds(settings.goalTime) else { return nil }
        let racePerKm = (finish - goalStationSeconds(settings)) / 8.0
        let freshPerKm = racePerKm - 28        // un-compromise: a fresh 5K runs ~28 s/km faster than race pace
        guard freshPerKm > 0 else { return nil }
        return freshPerKm * 5.0
    }

    /// "1:10" / "1:10:00" → seconds.
    private static func parseFinishSeconds(_ t: String) -> Double? {
        let p = t.split(separator: ":").compactMap { Double($0) }
        if p.count == 3 { return p[0] * 3600 + p[1] * 60 + p[2] }
        if p.count == 2 { return p[0] * 3600 + p[1] * 60 }
        return nil
    }

    /// The weekly day-of-week skeleton (Mon…Sun) for a profile — its training-day mix follows the limiter.
    private static func weeklySkeleton(_ p: AthleteProfile?) -> [Role] {
        switch p {
        case .heavySlowStrong:   return [.qualityRun, .easyRun, .strength, .qualityRun, .rest, .sim, .longRun]
        case .lightFastWeak:     return [.strength, .easyRun, .sim, .strength, .rest, .sim, .longRun]
        case .goodAtEverything:  return [.easyRun, .sim, .strength, .qualityRun, .rest, .sim, .longRun]
        default:                 return [.easyRun, .strength, .rest, .easyRun, .strength, .sim, .rest]
        }
    }

    /// Walk every day from today to race day, render the skeleton day modulated by its phase, with
    /// concrete targets: run paces from the 5K + station loads from the athlete's division.
    static func generate(profile: AthleteProfile?, settings: UserSettings, startDate: Date) -> [GeneratedSession] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: startDate)
        let totalDays = min(max(settings.daysToRace ?? 56, 7), 366)   // cap at ~1 year
        guard let raceDate = cal.date(byAdding: .day, value: totalDays, to: today) else { return [] }
        let weekdayMon0 = (cal.component(.weekday, from: today) + 5) % 7
        let startMonday = cal.date(byAdding: .day, value: -weekdayMon0, to: today) ?? today
        let blocks = Periodization.roadmap(daysToRace: totalDays, profile: profile)
        let skeleton = weeklySkeleton(profile)
        let paces = paces(settings)
        let stations = HyroxStations.weights(for: settings)

        var out: [GeneratedSession] = []
        var date = today
        while date <= raceDate {
            let weekOffset = (cal.dateComponents([.day], from: startMonday, to: date).day ?? 0) / 7
            let (phase, weekInPhase) = phaseFor(weekOffset, blocks)
            let weekday = (cal.component(.weekday, from: date) + 5) % 7
            out.append(render(role: skeleton[weekday], phase: phase, weekInPhase: weekInPhase,
                              profile: profile, date: date, weekNumber: weekOffset + 1,
                              paces: paces, stations: stations, settings: settings))
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return out
    }

    private static func phaseFor(_ weekOffset: Int, _ blocks: [PhaseBlock]) -> (TrainingPhase, Int) {
        for b in blocks where weekOffset >= b.startWeek && weekOffset < b.startWeek + b.weeks {
            return (b.phase, weekOffset - b.startWeek)
        }
        if let last = blocks.last { return (last.phase, max(0, weekOffset - last.startWeek)) }
        return (.build, 0)
    }

    private static func render(role: Role, phase: TrainingPhase, weekInPhase: Int,
                               profile: AthleteProfile?, date: Date, weekNumber: Int,
                               paces: Paces?, stations: StationWeights, settings: UserSettings) -> GeneratedSession {
        // Volume by phase × progressive overload within the phase × a light deload every 4th week.
        let phaseVol: Double = { switch phase { case .base: return 1.0; case .build: return 1.0; case .peak: return 0.85; case .taper: return 0.55 } }()
        let prog = 0.9 + 0.05 * Double(min(weekInPhase, 4))
        let deload = (weekInPhase > 0 && weekInPhase % 4 == 3) ? 0.82 : 1.0
        let vol = phaseVol * prog * deload
        func km(_ base: Double) -> Int { max(3, Int((base * vol).rounded())) }
        func dist(_ base: Double) -> String { Units.displayDistance(km: Double(km(base)), settings) ?? "\(km(base)) km" }

        func make(_ cat: SessionCategory, _ type: String, _ name: String, _ meta: String,
                  _ intent: PlanIntent, _ zone: String?, _ why: String?) -> GeneratedSession {
            GeneratedSession(date: date, category: cat, type: type, name: name, meta: meta,
                             intent: intent, zone: zone, why: why, phase: phase, weekNumber: weekNumber)
        }

        switch role {
        case .rest:
            return make(.rest, "REST", "Rest day", "recover", .rest, nil, nil)

        case .easyRun:
            return make(.run, "EASY RUN · Z2", "Aerobic base run", "\(dist(8)) · \(paces?.easy ?? "easy")", .easy, "Z2",
                        "\(phase.label) — aerobic base that frees up race pace.")

        case .longRun:
            return make(.run, "LONG RUN · Z2", "Long aerobic run", "\(dist(phase == .taper ? 9 : 14)) · \(paces?.long ?? "easy")", .easy, "Z2",
                        "\(phase.label) — volume + power-to-weight.")

        case .qualityRun:
            switch phase {
            case .base:
                return make(.run, "STEADY RUN · Z2", "Steady aerobic run", "\(dist(9)) · \(paces?.easy ?? "easy-moderate")", .easy, "Z2",
                            "Base — volume first; hold intensity easy.")
            case .build:
                return make(.run, "TEMPO RUN", "Tempo + strides", "\(dist(8)) tempo · \(paces?.tempo ?? "RPE 7")", .quality, "tempo",
                            "Build — lifts the pace you can hold.")
            case .peak:
                let note = (paces?.goalAmbitious ?? false)
                    ? "Peak — your goal needs near-5K running off the stations; ambitious."
                    : "Peak — locks in the run pace your goal finish needs."
                return make(.run, "GOAL-PACE INTERVALS", "Race-pace intervals", "5 × 1 km @ \(paces?.race ?? "goal") · 90s", .quality, "threshold", note)
            case .taper:
                return make(.run, "SHARPENER", "Strides + openers", "20 min easy + 6 strides @ \(paces?.fiveK ?? "5k")", .quality, nil,
                            "Taper — stay sharp, arrive fresh.")
            }

        case .strength:
            if profile == .heavySlowStrong {
                return make(.strength, "STRENGTH · MAINTAIN", "Maintenance lift", "30 min · 3 big lifts", .strength, nil,
                            "Strong enough for your division — strength is maintenance here, not a focus.")
            }
            switch phase {
            case .base:  return make(.strength, "STRENGTH · FOUNDATION", "Foundational strength", "45 min · squat/DL/press", .strength, nil, "Base — build the strength your stations need.")
            case .build: return make(.strength, "STRENGTH · BUILD", "Heavy lower + carries", "45 min + farmers \(stations.farmersKg)kg, sandbag \(stations.sandbagKg)kg", .strength, nil, "Build — strength + grip at race loads.")
            case .peak:  return make(.strength, "STRENGTH · MAINTAIN", "Power maintenance", "30 min", .strength, nil, "Peak — keep strength, prioritise race work.")
            case .taper: return make(.strength, "STRENGTH · LIGHT", "Light + crisp", "20 min · explosive", .strength, nil, "Taper — touch the weights, no fatigue.")
            }

        case .sim:
            switch phase {
            case .base:  return make(.sim, "STATION TECHNIQUE", "Movement quality", "wall ball \(stations.wallBallKg)kg + sled technique · clean reps", .easy, nil, "Base — groove the movements at race weight.")
            case .build: return make(.sim, "STATION CIRCUIT", "Sled + wall ball + carries", "sled \(stations.sledKg)kg · WB \(stations.wallBallKg)kg · farmers \(stations.farmersKg)kg", .quality, nil, "Build — station capacity under fatigue, at your division loads.")
            case .peak:  return make(.sim, "RACE SIM @ GOAL", "Compromised runs + stations", "4 × (1 km @ \(paces?.race ?? "goal") + station @ race weight)", .race_sim, nil, "Peak — rehearse pacing + the fade.")
            case .taper: return make(.sim, "MINI SIM", "Short sharp sim", "2 × (1 km @ \(paces?.race ?? "goal") + station)", .race_sim, nil, "Taper — short, race-pace, sharp.")
            }
        }
    }
}
