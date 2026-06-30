//  Periodization.swift
//  Ravns
//
//  Turns "days to race" + the diagnosis profile into a phased macro plan — base → build → peak →
//  taper — allocating the weeks you actually have, weighted by your limiter. This is the roadmap the
//  onboarding reveal promises; the weekly sessions (PlanEngine) are the near-term detail, tagged with
//  whichever phase is current. Recomputed live from today, so as the race nears the roadmap shifts
//  (base shrinks, you roll into build, then peak, then taper) without anything to maintain.

import SwiftUI

enum TrainingPhase: String, CaseIterable {
    case base, build, peak, taper

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .base:  return Palette.mint
        case .build: return Palette.yellow
        case .peak:  return Palette.orange
        case .taper: return Palette.green
        }
    }
}

struct PhaseBlock: Identifiable {
    let id = UUID()
    let phase: TrainingPhase
    let weeks: Int
    let startWeek: Int        // 0-based from today
    let focus: String

    var isCurrent: Bool { startWeek == 0 }

    /// [start, end) dates for this block, measured from a plan start (today).
    func range(from start: Date) -> (Date, Date) {
        let cal = Calendar.current
        let s = cal.date(byAdding: .weekOfYear, value: startWeek, to: start) ?? start
        let e = cal.date(byAdding: .weekOfYear, value: startWeek + weeks, to: start) ?? start
        return (s, e)
    }
}

enum Periodization {

    /// The phase roadmap from today to race day, weighted by the athlete's limiter.
    static func roadmap(daysToRace: Int?, profile: AthleteProfile?) -> [PhaseBlock] {
        let days = max(daysToRace ?? 56, 7)
        let total = max(1, Int((Double(days) / 7.0).rounded(.up)))

        // Too short to periodize — it's all about arriving fresh / sharp.
        if total <= 2 {
            return [PhaseBlock(phase: .taper, weeks: total, startWeek: 0, focus: focus(.taper, profile))]
        }

        // Taper (last), then peak, then base (limiter-weighted), then build = the remainder.
        let taper = total >= 14 ? 2 : (total >= 4 ? 1 : 0)
        var rem = total - taper
        let peakFrac = profile == .goodAtEverything ? 0.30 : 0.20
        let peak = rem >= 3 ? max(1, Int((Double(rem) * peakFrac).rounded())) : (rem >= 2 ? 1 : 0)
        rem -= peak
        let baseFrac: Double = {
            switch profile {
            case .weakAtEverything:  return 0.55   // needs the longest foundation
            case .goodAtEverything:  return 0.30   // already built — less base, more sharpening
            default:                 return 0.45
            }
        }()
        let base = rem > 0 ? Int((Double(rem) * baseFrac).rounded()) : 0
        let build = max(0, rem - base)

        var blocks: [PhaseBlock] = []
        var startWeek = 0
        for (phase, w) in [(TrainingPhase.base, base), (.build, build), (.peak, peak), (.taper, taper)] where w > 0 {
            blocks.append(PhaseBlock(phase: phase, weeks: w, startWeek: startWeek, focus: focus(phase, profile)))
            startWeek += w
        }
        if blocks.isEmpty {   // belt-and-suspenders for tiny remainders
            blocks = [PhaseBlock(phase: .build, weeks: total, startWeek: 0, focus: focus(.build, profile))]
        }
        return blocks
    }

    /// Which phase the athlete is in right now (the first block, since the roadmap starts today).
    static func currentPhase(daysToRace: Int?, profile: AthleteProfile?) -> TrainingPhase {
        roadmap(daysToRace: daysToRace, profile: profile).first?.phase ?? .build
    }

    private static func focus(_ phase: TrainingPhase, _ p: AthleteProfile?) -> String {
        let bias: String
        switch p {
        case .heavySlowStrong:  bias = "running volume + power-to-weight"
        case .lightFastWeak:    bias = "strength + station capacity"
        case .goodAtEverything: bias = "integration + pacing"
        case .weakAtEverything: bias = "both — biggest gap first"
        case nil:               bias = "general base"
        }
        switch phase {
        case .base:  return "Aerobic + strength foundation, biased to \(bias)."
        case .build: return "Add intensity + race-specific work — \(bias)."
        case .peak:  return "Race simulation + goal pace; rehearse the fade."
        case .taper: return "Cut volume, hold sharpness, arrive fresh."
        }
    }
}
