//  GoalLibrary.swift
//  Fitness Sherpa
//
//  Focus-metric goals (the Athlete "arcs"), ported from the prototype's GOAL_LIBRARY + PROFILE_GOALS.
//  Each diagnosis profile surfaces the four metrics that move its limiter. Stored as GoalArc (the
//  same shape the cloud app_state row uses), so goals persist and sync.

import Foundation

extension GoalValue {
    /// Numeric value for math: a number, or a parsed time string (h:mm:ss / mm:ss) in seconds.
    var asDouble: Double? {
        switch self {
        case .number(let d): return d
        case .text(let s):
            let parts = s.split(separator: ":").compactMap { Double($0) }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            return Double(s)
        }
    }
}

extension GoalArc: Identifiable {
    public var id: String { key }
    var betterDown: Bool { better == "down" }
    var isTime: Bool { kind == "time" }
    var currentDisplay: String { current?.display ?? "—" }
    var goalDisplay: String { goal?.display ?? "—" }
    var startDisplay: String { start?.display ?? "—" }
}

enum GoalLibrary {
    static let library: [String: GoalArc] = [
        "fivek":     GoalArc(key: "fivek", label: "5K TIME", unit: "", kind: "time", better: "down",
                             start: .text("26:00"), current: .text("25:45"), goal: .text("22:00")),
        "weight":    GoalArc(key: "weight", label: "WEIGHT", unit: "lb", kind: "num", better: "down",
                             start: .number(220), current: .number(214), goal: .number(200)),
        "bodyfat":   GoalArc(key: "bodyfat", label: "BODY FAT", unit: "%", kind: "num", better: "down",
                             start: .number(22), current: .number(16), goal: .number(14)),
        "z2pace":    GoalArc(key: "z2pace", label: "Z2 PACE /MI", unit: "", kind: "time", better: "down",
                             start: .text("12:00"), current: .text("11:00"), goal: .text("9:30")),
        "squat":     GoalArc(key: "squat", label: "BACK SQUAT", unit: "lb", kind: "num", better: "up",
                             start: .number(225), current: .number(275), goal: .number(315)),
        "farmers":   GoalArc(key: "farmers", label: "FARMERS 200M", unit: "kg", kind: "num", better: "up",
                             start: .number(20), current: .number(24), goal: .number(32)),
        "wallballs": GoalArc(key: "wallballs", label: "WALL BALLS", unit: "reps", kind: "num", better: "up",
                             start: .number(30), current: .number(50), goal: .number(100)),
        "simtime":   GoalArc(key: "simtime", label: "HYROX SIM", unit: "", kind: "time", better: "down",
                             start: .text("1:25:00"), current: .text("1:18:00"), goal: .text("1:10:00")),
    ]

    private static let profileGoals: [Int: [String]] = [
        1: ["fivek", "weight", "bodyfat", "z2pace"],     // heavy & slow → run + power-to-weight
        2: ["squat", "wallballs", "farmers", "weight"],  // light & weak → strength + stations
        3: ["simtime", "fivek", "z2pace", "bodyfat"],    // good everywhere → integration
        4: ["fivek", "squat", "weight", "bodyfat"],      // weak everywhere → biggest levers
    ]

    static func seed(for profile: AthleteProfile?) -> [GoalArc] {
        let keys = profileGoals[profile?.rawValue ?? 1] ?? profileGoals[1]!
        return keys.compactMap { library[$0] }
    }
}
