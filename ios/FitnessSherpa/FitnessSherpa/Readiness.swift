//  Readiness.swift
//  Fitness Sherpa
//
//  Provisional readiness score (v0). The prototype shows a 0–100 readiness verdict; until a
//  real baseline-aware model lands, this is a simple, transparent mapping of HRV + resting HR
//  to a band. NOT clinically tuned — it just turns the live recovery metrics into a verdict so
//  the Today hero reflects real data instead of a hardcoded number.

import SwiftUI

enum Readiness {
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    /// 0–100, or nil if there's no HRV to reason from.
    static func score(hrv: Double?, restingHR: Double?) -> Int? {
        guard let hrv else { return nil }
        let hrvScore = clamp((hrv - 20) / (70 - 20), 0, 1)                // 20 ms → 0, 70 ms → 1
        let rhrScore = restingHR.map { clamp((60 - $0) / (60 - 40), 0, 1) } // 60 bpm → 0, 40 bpm → 1
        let combined = rhrScore.map { hrvScore * 0.6 + $0 * 0.4 } ?? hrvScore
        return Int((combined * 100).rounded())
    }

    struct Verdict { let label: String; let color: Color }

    static func verdict(for score: Int) -> Verdict {
        switch score {
        case 75...:   return Verdict(label: "GREEN · TRAIN HARD", color: Palette.green)
        case 50..<75: return Verdict(label: "AMBER · MODERATE",   color: Palette.yellow)
        default:      return Verdict(label: "RED · RECOVER",      color: Palette.red)
        }
    }
}
