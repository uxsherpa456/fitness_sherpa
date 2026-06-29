//  DiagnosisEngine.swift
//  Fitness Sherpa
//
//  Pure-Swift port of the prototype's diagnostic engine (server.mjs / index.html).
//  Places an athlete on the strength × running quadrant and names the binding constraint.
//  No dependencies — safe to unit-test in isolation.
//
//  Example:
//      let input = DiagnosisInput(bodyweightLb: 214,
//                                 recent5k: DiagnosisEngine.parse5k("25:45"),
//                                 strengthAxis: 0.78)
//      let dx = DiagnosisEngine.diagnose(input)
//      // dx.profile == .heavySlowStrong, dx.markerX/Y drive the quadrant marker

import Foundation

/// The four HYROX athlete profiles — the output of placing an athlete on the quadrant.
enum AthleteProfile: Int, Codable, CaseIterable {
    case heavySlowStrong = 1     // Heavy & slow, strong enough
    case lightFastWeak   = 2     // Light & fast, not strong enough
    case goodAtEverything = 3
    case weakAtEverything = 4

    var title: String {
        switch self {
        case .heavySlowStrong:  return "Heavy & slow — strong enough"
        case .lightFastWeak:    return "Light & fast — not strong enough"
        case .goodAtEverything: return "Good at everything"
        case .weakAtEverything: return "Weak at everything"
        }
    }

    var limiter: String {
        switch self {
        case .heavySlowStrong:  return "running economy + power-to-weight"
        case .lightFastWeak:    return "strength + station capacity"
        case .goodAtEverything: return "integration + fatigue resistance"
        case .weakAtEverything: return "general base"
        }
    }

    var focus: String {
        switch self {
        case .heavySlowStrong:  return "lose weight toward 200 lb, improve 5k pace; lifting capped"
        case .lightFastWeak:    return "build strength + station work; hold run volume steady"
        case .goodAtEverything: return "race simulation, pacing, compromised running"
        case .weakAtEverything: return "fix the biggest deficit first, then re-diagnose"
        }
    }
}

/// The freshness-checked baseline the engine reasons over.
struct DiagnosisInput {
    var bodyweightLb: Double
    var recent5k: TimeInterval          // seconds
    var strengthAxis: Double            // 0…1 self-assessed strength + station capacity (the run/Health-blind axis)
    var goal5k: TimeInterval = 22 * 60  // the 5k pace a 1:10 finish needs
}

/// A placement on the quadrant plus its interpretation.
struct Diagnosis: Codable, Equatable {
    let profile: AthleteProfile
    let limiter: String
    let focus: String
    let runAxis: Double        // 0 = heavy & slow, 1 = light & fast
    let strengthAxis: Double   // 0 = weak, 1 = strong
    let markerX: Double        // 0...1 across the quadrant (left → right)
    let markerY: Double        // 0...1 down the quadrant (top → bottom)
    let evidence: String
}

enum DiagnosisEngine {

    static func diagnose(_ input: DiagnosisInput) -> Diagnosis {
        let goal = input.goal5k

        // Run axis: better (→1) when 5k is near goal and bodyweight is low.
        let paceScore   = clamp(1 - (input.recent5k - goal) / ((28 * 60) - goal), 0, 1) // 22:00→1, 28:00→0
        let weightScore = clamp(1 - (input.bodyweightLb - 185) / (225 - 185), 0, 1)     // 185 lb→1, 225→0
        let runAxis = paceScore * 0.6 + weightScore * 0.4

        // Strength axis: a continuous 0…1 self-assessment (averaged from the onboarding station/lift
        // questions). Apple Health can't see this, so it's the one axis the athlete enters by hand.
        let strengthAxis = clamp(input.strengthAxis, 0, 1)

        let strong = strengthAxis >= 0.5
        let fast   = runAxis >= 0.5
        let profile: AthleteProfile
        switch (strong, fast) {
        case (true,  false): profile = .heavySlowStrong
        case (false, true):  profile = .lightFastWeak
        case (true,  true):  profile = .goodAtEverything
        case (false, false): profile = .weakAtEverything
        }

        // NOTE: keep in sync with the canonical engine in supabase/functions/_shared/diagnosis.ts.
        // Two intentional differences vs that TS port: (1) markerX/Y here are 0...1, but diagnosis.ts
        // returns them ×100 (0–100 ints) — scale when sharing fixtures; (2) `evidence` there uses the
        // raw 5k input string while this reformats via format5k() — equal for canonical inputs.
        let markerX = 0.12 + runAxis * 0.76
        let markerY = 0.12 + (1 - strengthAxis) * 0.76
        let evidence = "\(format5k(input.recent5k)) 5k, \(Int(input.bodyweightLb)) lb, "
                     + "stations \(strong ? "hold" : "fade") vs \(format5k(goal)) goal"

        return Diagnosis(profile: profile, limiter: profile.limiter, focus: profile.focus,
                         runAxis: runAxis, strengthAxis: strengthAxis,
                         markerX: markerX, markerY: markerY, evidence: evidence)
    }

    // MARK: - Helpers

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    /// "25:45" → 1545 seconds
    static func parse5k(_ mmss: String) -> TimeInterval {
        let parts = mmss.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// 1545 → "25:45"
    static func format5k(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
