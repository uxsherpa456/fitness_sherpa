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
                .init(dow: "WED", category: .strength, type: "STRENGTH · CAPPED", name: "Maintenance lift",
                      meta: "30 min · 3 big lifts", why: "Capped — holds strength without fighting weight loss"),
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

    /// The weekly day-of-week skeleton (Mon…Sun) for a profile — its training-day mix follows the limiter.
    private static func weeklySkeleton(_ p: AthleteProfile?) -> [Role] {
        switch p {
        case .heavySlowStrong:   return [.qualityRun, .easyRun, .strength, .qualityRun, .rest, .sim, .longRun]
        case .lightFastWeak:     return [.strength, .easyRun, .sim, .strength, .rest, .sim, .longRun]
        case .goodAtEverything:  return [.easyRun, .sim, .strength, .qualityRun, .rest, .sim, .longRun]
        default:                 return [.easyRun, .strength, .rest, .easyRun, .strength, .sim, .rest]
        }
    }

    /// Walk every day from today to race day, render the skeleton day modulated by its phase.
    static func generate(profile: AthleteProfile?, daysToRace: Int, startDate: Date) -> [GeneratedSession] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: startDate)
        let totalDays = min(max(daysToRace, 7), 366)   // cap at ~1 year
        guard let raceDate = cal.date(byAdding: .day, value: totalDays, to: today) else { return [] }
        let weekdayMon0 = (cal.component(.weekday, from: today) + 5) % 7
        let startMonday = cal.date(byAdding: .day, value: -weekdayMon0, to: today) ?? today
        let blocks = Periodization.roadmap(daysToRace: totalDays, profile: profile)
        let skeleton = weeklySkeleton(profile)

        var out: [GeneratedSession] = []
        var date = today
        while date <= raceDate {
            let weekOffset = (cal.dateComponents([.day], from: startMonday, to: date).day ?? 0) / 7
            let (phase, weekInPhase) = phaseFor(weekOffset, blocks)
            let weekday = (cal.component(.weekday, from: date) + 5) % 7
            out.append(render(role: skeleton[weekday], phase: phase, weekInPhase: weekInPhase,
                              profile: profile, date: date, weekNumber: weekOffset + 1))
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
                               profile: AthleteProfile?, date: Date, weekNumber: Int) -> GeneratedSession {
        // Volume by phase × progressive overload within the phase × a light deload every 4th week.
        let phaseVol: Double = { switch phase { case .base: return 1.0; case .build: return 1.0; case .peak: return 0.85; case .taper: return 0.55 } }()
        let prog = 0.9 + 0.05 * Double(min(weekInPhase, 4))
        let deload = (weekInPhase > 0 && weekInPhase % 4 == 3) ? 0.82 : 1.0
        let vol = phaseVol * prog * deload
        func km(_ base: Double) -> Int { max(3, Int((base * vol).rounded())) }

        func make(_ cat: SessionCategory, _ type: String, _ name: String, _ meta: String,
                  _ intent: PlanIntent, _ zone: String?, _ why: String?) -> GeneratedSession {
            GeneratedSession(date: date, category: cat, type: type, name: name, meta: meta,
                             intent: intent, zone: zone, why: why, phase: phase, weekNumber: weekNumber)
        }

        switch role {
        case .rest:
            return make(.rest, "REST", "Rest day", "recover", .rest, nil, nil)

        case .easyRun:
            return make(.run, "EASY RUN · Z2", "Aerobic base run", "\(km(8)) km · easy", .easy, "Z2",
                        "\(phase.label) — aerobic base that frees up race pace.")

        case .longRun:
            return make(.run, "LONG RUN · Z2", "Long aerobic run", "\(km(phase == .taper ? 9 : 14)) km · easy", .easy, "Z2",
                        "\(phase.label) — volume + power-to-weight.")

        case .qualityRun:
            switch phase {
            case .base:
                return make(.run, "STEADY RUN · Z2", "Steady aerobic run", "\(km(9)) km · easy-moderate", .easy, "Z2",
                            "Base — volume first; hold intensity easy.")
            case .build:
                return make(.run, "TEMPO RUN", "Tempo + strides", "\(km(8)) km tempo · RPE 7", .quality, "tempo",
                            "Build — lifts the pace you can hold.")
            case .peak:
                return make(.run, "GOAL-PACE INTERVALS", "Race-pace intervals", "5 × 1 km @ goal · 90s", .quality, "threshold",
                            "Peak — locks in goal pace.")
            case .taper:
                return make(.run, "SHARPENER", "Strides + openers", "20 min easy + 6 strides", .quality, nil,
                            "Taper — stay sharp, arrive fresh.")
            }

        case .strength:
            if profile == .heavySlowStrong {
                return make(.strength, "STRENGTH · CAPPED", "Maintenance lift", "30 min · 3 big lifts", .strength, nil,
                            "Capped — holds strength without fighting weight loss.")
            }
            switch phase {
            case .base:  return make(.strength, "STRENGTH · FOUNDATION", "Foundational strength", "45 min · squat/DL/press", .strength, nil, "Base — build the strength your stations need.")
            case .build: return make(.strength, "STRENGTH · BUILD", "Heavy lower + pull", "45 min", .strength, nil, "Build — strength + grip for the stations.")
            case .peak:  return make(.strength, "STRENGTH · MAINTAIN", "Power maintenance", "30 min", .strength, nil, "Peak — keep strength, prioritise race work.")
            case .taper: return make(.strength, "STRENGTH · LIGHT", "Light + crisp", "20 min · explosive", .strength, nil, "Taper — touch the weights, no fatigue.")
            }

        case .sim:
            switch phase {
            case .base:  return make(.sim, "STATION TECHNIQUE", "Movement quality", "stations · clean reps", .easy, nil, "Base — groove the movements.")
            case .build: return make(.sim, "STATION CIRCUIT", "Sled + wall ball + carries", "capacity under fatigue", .quality, nil, "Build — station capacity under fatigue.")
            case .peak:  return make(.sim, "RACE SIM @ GOAL", "Compromised runs + stations", "4 × (1 km + station) @ goal", .race_sim, nil, "Peak — rehearse pacing + the fade.")
            case .taper: return make(.sim, "MINI SIM", "Short sharp sim", "2 × (1 km + station)", .race_sim, nil, "Taper — short, race-pace, sharp.")
            }
        }
    }
}
