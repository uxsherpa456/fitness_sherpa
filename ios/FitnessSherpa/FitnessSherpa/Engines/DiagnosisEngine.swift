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
        case .heavySlowStrong:  return "strong enough for your division — strength stays at maintenance, not a focus; the work is dropping weight and sharpening 5k pace"
        case .lightFastWeak:    return "build strength + station work; hold run volume steady"
        case .goodAtEverything: return "race simulation, pacing, compromised running"
        case .weakAtEverything: return "fix the biggest deficit first, then re-diagnose"
        }
    }
}

/// The freshness-checked baseline the engine reasons over.
struct DiagnosisInput {
    var bodyweightLb: Double
    var heightIn: Double = 0            // standing height (in); 0 = unknown → BMI falls back to a weight anchor
    var bodyFatPct: Double = 0          // body fat %; 0 = unknown → no power-to-weight credit
    var raceLeanBodyFatPct: Double = 12 // the athlete's race-weight body-fat target (set by division/gender)
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
    let markerX: Double        // 0...1 across the quadrant — where you ARE (left → right)
    let markerY: Double        // 0...1 down the quadrant — where you ARE (top → bottom)
    let goalMarkerX: Double    // 0...1 — where your GOAL puts you (running at goal fitness)
    let goalMarkerY: Double    // 0...1 — where your GOAL puts you (strength at division standard)
    let paceReadiness: Double  // 0...1 — how close your 5k fitness alone is to what the goal needs
    let runReadiness: Double   // 0...1 — pace + power-to-weight credit; drives the run-axis position
    let strengthReadiness: Double // 0...1 — how close your strength is to your division standard
    let goalReadiness: Double  // 0...1 — overall readiness for the goal finish
    let raceWeightLbAway: Double  // lb of fat above your race-weight target (0 if at/below or unknown)
    let goalFocus: String      // what to work on, relative to the goal (not the absolute profile)
    let vdot: Double           // Daniels–Gilbert VDOT (pseudo-VO2max) from the recent 5k
    let bmi: Double            // body-mass index from weight + height (0 if height unknown)
    let evidence: String

    // Tolerant decode so older stored/synced diagnoses (missing the newer fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile      = try c.decode(AthleteProfile.self, forKey: .profile)
        limiter      = try c.decode(String.self, forKey: .limiter)
        focus        = try c.decode(String.self, forKey: .focus)
        runAxis      = try c.decode(Double.self, forKey: .runAxis)
        strengthAxis = try c.decode(Double.self, forKey: .strengthAxis)
        markerX      = try c.decode(Double.self, forKey: .markerX)
        markerY      = try c.decode(Double.self, forKey: .markerY)
        goalMarkerX  = (try? c.decode(Double.self, forKey: .goalMarkerX)) ?? markerX
        goalMarkerY  = (try? c.decode(Double.self, forKey: .goalMarkerY)) ?? markerY
        paceReadiness = (try? c.decode(Double.self, forKey: .paceReadiness)) ?? 0
        runReadiness = (try? c.decode(Double.self, forKey: .runReadiness)) ?? ((try? c.decode(Double.self, forKey: .paceReadiness)) ?? 0)
        strengthReadiness = (try? c.decode(Double.self, forKey: .strengthReadiness)) ?? 0
        goalReadiness = (try? c.decode(Double.self, forKey: .goalReadiness)) ?? 0
        raceWeightLbAway = (try? c.decode(Double.self, forKey: .raceWeightLbAway)) ?? 0
        goalFocus    = (try? c.decode(String.self, forKey: .goalFocus)) ?? focus
        vdot         = (try? c.decode(Double.self, forKey: .vdot)) ?? 0
        bmi          = (try? c.decode(Double.self, forKey: .bmi)) ?? 0
        evidence     = try c.decode(String.self, forKey: .evidence)
    }

    init(profile: AthleteProfile, limiter: String, focus: String, runAxis: Double,
         strengthAxis: Double, markerX: Double, markerY: Double,
         goalMarkerX: Double, goalMarkerY: Double, paceReadiness: Double, runReadiness: Double,
         strengthReadiness: Double, goalReadiness: Double, raceWeightLbAway: Double,
         goalFocus: String, vdot: Double, bmi: Double, evidence: String) {
        self.profile = profile; self.limiter = limiter; self.focus = focus
        self.runAxis = runAxis; self.strengthAxis = strengthAxis
        self.markerX = markerX; self.markerY = markerY
        self.goalMarkerX = goalMarkerX; self.goalMarkerY = goalMarkerY
        self.paceReadiness = paceReadiness; self.runReadiness = runReadiness
        self.strengthReadiness = strengthReadiness
        self.goalReadiness = goalReadiness; self.raceWeightLbAway = raceWeightLbAway
        self.goalFocus = goalFocus
        self.vdot = vdot; self.bmi = bmi; self.evidence = evidence
    }
}

enum DiagnosisEngine {

    static func diagnose(_ input: DiagnosisInput) -> Diagnosis {
        let goal = input.goal5k

        // Run axis: better (→1) on stronger running performance and leaner body composition.
        //
        // Performance uses VDOT (Daniels & Gilbert) — a pseudo-VO2max derived from race time that
        // blends aerobic capacity and running economy into one number — scored against the VDOT the
        // goal 5k demands. Reaches 1 at goal fitness and 0 about a 12-point VDOT deficit below it
        // (≈ the old 22:00→28:00 spread, but on a physiological scale).
        let athleteVdot = vdot(seconds: input.recent5k)
        let goalVdot    = vdot(seconds: goal)
        let paceScore = clamp((athleteVdot - (goalVdot - 12)) / 12, 0, 1)

        // Body / running-economy via BMI, so it's normalized for height (and reads correctly across
        // genders, unlike fixed pound anchors). BMI 23 → lean power-to-weight (1); 31 → heavy (0).
        // Falls back to the legacy weight anchor when height is unknown.
        let bmi = (input.heightIn > 0)
            ? 703 * input.bodyweightLb / (input.heightIn * input.heightIn)
            : 0
        let weightScore = bmi > 0
            ? clamp(1 - (bmi - 23) / (31 - 23), 0, 1)
            : clamp(1 - (input.bodyweightLb - 185) / (225 - 185), 0, 1)

        let runAxis = paceScore * 0.6 + weightScore * 0.4

        // Strength axis: a continuous 0…1 self-assessment (averaged from the onboarding station/lift
        // questions). Apple Health can't see this, so it's the one axis the athlete enters by hand.
        let strengthAxis = clamp(input.strengthAxis, 0, 1)

        // EVERYTHING below is RELATIVE TO THE GOAL. Readiness on each axis = how close you are to what
        // the goal needs: running = your VDOT vs the goal's; strength = vs your division standard.
        let paceReadiness = paceScore
        let strengthReadiness = clamp(strengthAxis / 0.5, 0, 1)   // 1.0 once you clear your division standard

        // Power-to-weight credit: HYROX rewards leanness (compromised running + bodyweight stations),
        // and pace improves ~proportionally with fat lost — a leading signal your 5k hasn't caught yet.
        // As you near your race-weight target this closes part of the run gap, so leaning out shows up
        // as progress NOW. It only ever HELPS (floored at your measured pace readiness) and is bounded.
        let leanGain = 0.35                // max share of the remaining run gap that race-weight can close
        let leanRange = 10.0               // body-fat points above target over which the credit fades to 0
        let bodyReady = input.bodyFatPct > 0
            ? clamp(1 - (input.bodyFatPct - input.raceLeanBodyFatPct) / leanRange, 0, 1)
            : 0
        let runReadiness = clamp(paceReadiness + leanGain * bodyReady * (1 - paceReadiness), 0, 1)
        let raceWeightLbAway = (input.bodyFatPct > 0 && input.bodyweightLb > 0)
            ? max(0, input.bodyweightLb * (input.bodyFatPct - input.raceLeanBodyFatPct) / 100)
            : 0

        // You only read as "ready" on an axis once you've essentially reached the goal's requirement —
        // so the marker sits in the LIMITING cell until then, and "good at everything" means ready on
        // BOTH. `ready` is the readiness at which an axis crosses into its goal-ready half.
        let ready = 0.9
        let strong = strengthReadiness >= ready
        let fast   = runReadiness >= ready
        let profile: AthleteProfile
        switch (strong, fast) {
        case (true,  false): profile = .heavySlowStrong
        case (false, true):  profile = .lightFastWeak
        case (true,  true):  profile = .goodAtEverything
        case (false, false): profile = .weakAtEverything
        }

        // Map a 0…1 readiness to a 0…1 quadrant position, with `ready` landing on the mid-line, so the
        // marker only crosses into the goal-ready half once the axis is actually there.
        // NOTE: keep in sync with the canonical engine in supabase/functions/_shared/diagnosis.ts —
        // markerX/Y here are 0...1; diagnosis.ts returns them ×100.
        func pos(_ r: Double) -> Double {
            r <= ready ? r * 0.5 / ready : 0.5 + (r - ready) / (1 - ready) * 0.5
        }
        let markerX = 0.12 + pos(runReadiness) * 0.76
        let markerY = 0.12 + (1 - pos(strengthReadiness)) * 0.76

        // GOAL = ready on both (the complete-athlete corner), inset just off the corner label.
        let goalPos = 0.92
        let goalMarkerX = 0.12 + goalPos * 0.76
        let goalMarkerY = 0.12 + (1 - goalPos) * 0.76
        let goalReadiness = clamp(0.55 * runReadiness + 0.45 * strengthReadiness, 0, 1)

        let gapRun = 1 - runReadiness, gapStr = 1 - strengthReadiness
        let pacePct = Int((paceReadiness * 100).rounded())
        let lbAway = Int(raceWeightLbAway.rounded())
        let goalFocus: String
        if gapRun < 0.12 && gapStr < 0.12 {
            goalFocus = "Race-ready — sharpen pacing, transitions, and compromised running."
        } else if gapRun >= gapStr {
            goalFocus = "Running is your gap — you're at \(pacePct)% of the 5k fitness your goal needs. "
                      + "Build run speed" + (lbAway > 0 ? "; ~\(lbAway) lb from race-weight." : ".")
        } else {
            goalFocus = "Strength + station capacity is your gap — bring your lifts to your division "
                      + "standard while holding run volume."
        }

        let body = bmi > 0 ? String(format: "BMI %.1f", bmi) : "\(Int(input.bodyweightLb)) lb"
        let evidence = "VDOT \(Int(athleteVdot.rounded())) · \(format5k(input.recent5k)) 5k · \(body) · "
                     + "stations \(strong ? "hold" : "fade") vs \(format5k(goal)) goal"

        return Diagnosis(profile: profile, limiter: profile.limiter, focus: profile.focus,
                         runAxis: runAxis, strengthAxis: strengthAxis,
                         markerX: markerX, markerY: markerY,
                         goalMarkerX: goalMarkerX, goalMarkerY: goalMarkerY,
                         paceReadiness: paceReadiness, runReadiness: runReadiness,
                         strengthReadiness: strengthReadiness,
                         goalReadiness: goalReadiness, raceWeightLbAway: raceWeightLbAway,
                         goalFocus: goalFocus, vdot: athleteVdot, bmi: bmi, evidence: evidence)
    }

    // MARK: - Helpers

    /// Daniels–Gilbert "VDOT" — a pseudo-VO2max from a race performance (default a 5k), combining
    /// aerobic capacity and running economy into one fitness index. From Jack Daniels' Running
    /// Formula (Daniels & Gilbert, *Oxygen Power*). Most accurate for efforts of ~15–50 min.
    static func vdot(meters: Double = 5000, seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        let t = seconds / 60                                   // minutes
        let v = meters / t                                     // velocity, m/min
        let vo2 = -4.60 + 0.182258 * v + 0.000104 * v * v      // oxygen cost at race pace
        let pctMax = 0.8 + 0.1894393 * exp(-0.012778 * t)      // sustainable fraction of VO2max
                          + 0.2989558 * exp(-0.1932605 * t)
        return vo2 / pctMax
    }

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
