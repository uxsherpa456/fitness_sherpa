//  StrengthStandards.swift
//  Fitness Sherpa
//
//  Turns the onboarding barbell answers into the strength axis, measured against the athlete's
//  HYROX division — so "strong enough for my division" is what puts you on the strong side of the
//  quadrant, not a one-size-fits-all bar. The grid below is the "strength is NOT your limiter" line
//  for each lift, as a bodyweight multiple; Pro carries heavier implements than Open, men's heavier
//  than women's, so the bar scales accordingly.

import Foundation

enum StrengthLift: String, CaseIterable {
    case squat, bench, deadlift
}

enum StrengthStandards {
    /// Bodyweight-multiple at which strength stops being the limiter, by division group.
    /// Keyed "<men|women>_<open|pro>". Mixed/team formats use the athlete's gender at Open weights.
    private static let grid: [String: [StrengthLift: Double]] = [
        "men_open":   [.squat: 1.25, .bench: 1.00, .deadlift: 1.50],
        "men_pro":    [.squat: 1.50, .bench: 1.25, .deadlift: 1.75],
        "women_open": [.squat: 1.00, .bench: 0.60, .deadlift: 1.25],
        "women_pro":  [.squat: 1.25, .bench: 0.75, .deadlift: 1.50],
    ]

    static func key(for s: UserSettings) -> String {
        let women = s.gender == "womens"
        let pro = s.tier == "pro" && s.format == "singles"   // Pro weights only apply to singles
        return "\(women ? "women" : "men")_\(pro ? "pro" : "open")"
    }

    /// The "strong enough" bodyweight multiple for one lift in the athlete's division.
    static func standard(_ lift: StrengthLift, _ s: UserSettings) -> Double {
        grid[key(for: s)]?[lift] ?? grid["men_open"]![lift]!
    }

    /// Map answered lifts (lift → the athlete's bodyweight multiple) to a 0…1 strength axis vs the
    /// division standards. Meeting the standard maps to 0.5 — exactly the strong/weak boundary — so
    /// hitting your division's numbers lands you in the "strong enough" quadrant; exceeding pushes up.
    static func liftAxis(_ answers: [StrengthLift: Double], _ s: UserSettings) -> Double? {
        guard !answers.isEmpty else { return nil }
        let axes = answers.map { lift, mult -> Double in
            let ratio = mult / standard(lift, s)
            return min(max(0.5 + (ratio - 1) * 0.6, 0), 1)   // ratio 1 → 0.5; ~1.83 → 1.0; ~0.17 → 0
        }
        return axes.reduce(0, +) / Double(axes.count)
    }

    /// Human label for the current division (for the onboarding hint).
    static func divisionLabel(_ s: UserSettings) -> String {
        let g = s.gender == "womens" ? "Women's" : "Men's"
        let t = (s.tier == "pro" && s.format == "singles") ? "Pro" : "Open"
        return "\(g) \(t)"
    }
}
