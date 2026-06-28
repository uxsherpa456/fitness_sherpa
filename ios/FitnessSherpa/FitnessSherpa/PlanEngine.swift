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
}
