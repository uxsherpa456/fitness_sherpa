//  Readiness.swift
//  Ravns
//
//  Readiness v2 — the explainable ledger. The score is an additive sum of three visible pillars
//  (Recovery 45 · Sleep 30 · Training load 25), each scored 0…1 against the athlete's own baseline
//  or ideal zone, so every point on screen is attributable to a signal the athlete can see. The
//  subjective "how you feel" check still scales the final number (applied in AppModel).

import SwiftUI
import HealthKit

struct MetricBaseline { let mean: Double; let sd: Double; let n: Int }

/// One-tap morning wellness — you know you're cooked before the sensors prove it.
enum Feeling: String, CaseIterable, Identifiable {
    case wrecked, tired, ok, good, primed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wrecked: return "Wrecked"
        case .tired:   return "Tired"
        case .ok:      return "OK"
        case .good:    return "Good"
        case .primed:  return "Primed"
        }
    }
    /// Multiplier applied to the objective score.
    var multiplier: Double {
        switch self {
        case .wrecked: return 0.55
        case .tired:   return 0.80
        case .ok:      return 1.00
        case .good:    return 1.05
        case .primed:  return 1.10
        }
    }
}

struct ReadinessComponent: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let unit: String
    let z: Double          // clamped, sign-flipped (positive = better than baseline)
    let weight: Double
    let personal: Bool     // scored against the athlete's own baseline vs a population prior
}

/// One row of the readiness ledger — a scored pillar whose earned points (credit × weight) sum
/// with the others to the readiness score. `position` and the ideal band drive the gauge display;
/// they're deliberately separate from `credit` so "more than ideal" can still read positive
/// (extra sleep is banked, an easy week is fresh — never a scolding).
struct ReadinessPillar: Identifiable {
    let key: String        // "recovery" | "sleep" | "load"
    let label: String
    var weight: Double     // max points (renormalized so shown maxes always total 100)
    let credit: Double     // 0…1 quality → points earned
    let position: Double   // 0…1 marker position on the gauge
    let bandLo: Double     // ideal-zone band on the gauge
    let bandHi: Double
    let status: String     // plain-language read ("Primed", "Sweet spot", "Banked")
    let detail: String     // the numbers behind it ("HRV 74 ms · resting HR 51 bpm…")
    let axisLeft: String   // gauge end/middle labels
    let axisMid: String
    let axisRight: String
    var points: Double { credit * weight }
    var id: String { key }
}

struct ReadinessResult {
    var score: Int?                // sum of pillar points (before the subjective feeling, applied later)
    var components: [ReadinessComponent]
    var recovery: RecoveryResult?  // two-axis HRV/RHR readout (log-z HRV + z RHR) feeding the blend
    var pillars: [ReadinessPillar] = []   // the ledger — pillar points sum to `score`
    var flags: [String] = []              // active outlier warnings (resp rate, recent max effort)
    var cappedGreen: Bool = false
    // training load context (for the card + coach)
    var atl: Double = 0
    var ctl: Double = 0
    var form: Double = 0
    var ratio: Double = 1
    var hrMax: Int = 0
    var lastHardPct: Double?
    var lastHardHoursAgo: Double?
}

enum Readiness {
    struct Verdict { let label: String; let color: Color }
    static func verdict(for score: Int) -> Verdict {
        switch score {
        case 75...:   return Verdict(label: "GREEN · TRAIN HARD", color: Palette.green)
        case 50..<75: return Verdict(label: "AMBER · MODERATE",   color: Palette.yellow)
        default:      return Verdict(label: "RED · RECOVER",      color: Palette.red)
        }
    }
}

enum ReadinessEngine {
    private static let hrvPrior  = MetricBaseline(mean: 45, sd: 20, n: 0)
    private static let rhrPrior  = MetricBaseline(mean: 55, sd: 8, n: 0)
    private static let respPrior = MetricBaseline(mean: 15, sd: 2, n: 0)

    static func compute(reading: HealthData.Reading, load: LoadResult) async -> ReadinessResult {
        let ms = HKUnit.secondUnit(with: .milli)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let hrvBaseT  = HealthData.baseline(.heartRateVariabilitySDNN, unit: ms)
        async let rhrBaseT  = HealthData.baseline(.restingHeartRate, unit: bpm)
        async let respBaseT = HealthData.baseline(.respiratoryRate, unit: bpm)
        async let respTodayT = try? HealthData.latestSample(.respiratoryRate, unit: bpm)
        async let morningT = try? HealthData.morningReadings()

        let hrvBase = await hrvBaseT, rhrBase = await rhrBaseT
        let respBase = await respBaseT
        let respToday = (await respTodayT) ?? nil
        let morning = ((await morningT) ?? nil) ?? []

        // Two-axis recovery: log-z HRV + z RHR vs the athlete's own morning-reading baseline.
        let recovery: RecoveryResult? = morning.last.map {
            RecoveryEngine.evaluate(history: Array(morning.dropLast()), today: $0)
        }

        var comps: [ReadinessComponent] = []
        func z(_ value: Double, _ base: MetricBaseline, invert: Bool) -> Double {
            let raw = (value - base.mean) / base.sd
            return min(max(invert ? -raw : raw, -2), 2)
        }
        func add(_ label: String, _ today: Double?, _ base: MetricBaseline?, prior: MetricBaseline?,
                 weight: Double, unit: String, invert: Bool) {
            guard let today, let b = base ?? prior else { return }
            comps.append(ReadinessComponent(label: label, value: today, unit: unit,
                                            z: z(today, b, invert: invert), weight: weight, personal: base != nil))
        }

        func clampZ(_ z: Double) -> Double { min(max(z, -2), 2) }
        // HRV + RHR: prefer the RecoveryEngine's log-z / z (own morning baseline) when it has ≥14
        // days; otherwise fall back to the raw-z-vs-baseline (population priors early on).
        if let rec = recovery, let hz = rec.hrvZ, let today = morning.last {
            comps.append(ReadinessComponent(label: "HRV", value: today.sdnnMS, unit: "ms",
                                            z: clampZ(hz), weight: 0.35, personal: true))
        } else {
            add("HRV", reading.hrv?.value, hrvBase, prior: hrvPrior, weight: 0.35, unit: "ms", invert: false)
        }
        if let rec = recovery, let rz = rec.rhrZ, let today = morning.last {
            comps.append(ReadinessComponent(label: "Resting HR", value: today.rhrBPM, unit: "bpm",
                                            z: clampZ(-rz), weight: 0.20, personal: true))   // higher RHR = worse
        } else {
            add("Resting HR", reading.restingHR?.value, rhrBase, prior: rhrPrior, weight: 0.20, unit: "bpm", invert: true)
        }
        add("Resp rate", respToday?.value, respBase, prior: respPrior, weight: 0.10, unit: "br/min", invert: true)

        if let s = reading.sleepSummary {
            let dur = clamp((s.asleep - 5) / (8 - 5), 0, 1)
            let eff = clamp((s.efficiency - 0.7) / (0.95 - 0.7), 0, 1)
            comps.append(ReadinessComponent(label: "Sleep", value: s.asleep, unit: "h",
                                            z: min(max(((dur * 0.7 + eff * 0.3) - 0.5) / 0.25, -2), 2),
                                            weight: 0.20, personal: false))
        }

        var result = ReadinessResult(score: nil, components: comps, recovery: recovery, cappedGreen: load.cappedGreen,
                                     atl: load.atl, ctl: load.ctl, form: load.form, ratio: load.ratio,
                                     hrMax: load.hrMax, lastHardPct: load.lastHardPct,
                                     lastHardHoursAgo: load.lastHardHoursAgo)

        guard reading.hrv != nil, !comps.isEmpty else { return result }

        // Blend HRV (0.65) + resting HR (0.35) into one recovery z (comps' z is already
        // sign-flipped, positive = better). Respiratory rate stays an outlier-only flag: dead-zoned
        // to ±1.5σ so ordinary wobble never bites, docking up to 10% of the recovery pillar by ±3σ.
        let zHRV = comps.first { $0.label == "HRV" }?.z
        let zRHR = comps.first { $0.label == "Resting HR" }?.z
        let recZ = zHRV.map { $0 * 0.65 + (zRHR ?? 0) * 0.35 }
        let respPenalty: Double = {
            guard let z = comps.first(where: { $0.label == "Resp rate" })?.z, z < 0 else { return 0 }
            return min(max(0, -z - 1.5) / 1.5, 1) * 0.10
        }()
        let hrvStr = reading.hrv.map { "\(Int($0.value.rounded())) ms" } ?? "—"
        let rhrStr = reading.restingHR.map { "\(Int($0.value.rounded())) bpm" } ?? "—"

        let (pillars, flags, score) = assemble(
            recZ: recZ,
            recDetail: "HRV \(hrvStr) · resting HR \(rhrStr) vs your baseline",
            sleep: reading.sleepSummary,
            respPenalty: respPenalty,
            ratio: load.ratio,
            trained: load.ctl > 1 || load.atl > 1,
            effortMult: load.effortMultiplier)
        result.pillars = pillars
        result.flags = flags
        result.score = score.map { Int(min(100, max(0, $0.rounded()))) }
        return result
    }

    /// Build the ledger: pillar points sum to the score. Weights renormalize over the pillars that
    /// have data (Recovery 45 · Sleep 30 · Load 25), so a missing signal never silently zeroes the
    /// score and the shown maxes always total 100. No score without HRV — same gate as ever.
    static func assemble(recZ: Double?, recDetail: String, sleep: HealthData.SleepSummary?,
                         respPenalty: Double, ratio: Double, trained: Bool, effortMult: Double)
        -> (pillars: [ReadinessPillar], flags: [String], score: Double?) {
        var raw: [(base: Double, p: ReadinessPillar)] = []
        var flags: [String] = []

        if let z = recZ {
            let pos = clamp((z + 2) / 4, 0, 1)
            let status = pos >= 0.58 ? "Primed" : pos >= 0.42 ? "At baseline"
                       : pos >= 0.28 ? "Run down" : "Suppressed"
            raw.append((45, ReadinessPillar(
                key: "recovery", label: "Recovery", weight: 0,
                credit: pos * (1 - respPenalty), position: pos, bandLo: 0.5, bandHi: 1.0,
                status: status, detail: recDetail,
                axisLeft: "SUPPRESSED", axisMid: "BASELINE", axisRight: "PRIMED")))
            if respPenalty > 0 { flags.append("Respiratory rate elevated vs your baseline") }
        }

        if let s = sleep {
            let dur = clamp((s.asleep - 5) / 3, 0, 1)
            let eff = clamp((s.efficiency - 0.7) / 0.25, 0, 1)
            // Position keeps moving past the optimal band, but credit never drops — long sleep is
            // banked recovery, not a fault.
            let status = s.asleep >= 9 ? "Banked" : s.asleep >= 7 ? "Optimal"
                       : s.asleep >= 6 ? "Light" : "Short"
            raw.append((30, ReadinessPillar(
                key: "sleep", label: "Sleep", weight: 0,
                credit: dur * 0.7 + eff * 0.3, position: clamp((s.asleep - 4) / 6, 0, 1),
                bandLo: 0.5, bandHi: 0.833, status: status,
                detail: String(format: "%.1f h asleep · %.0f%% efficiency", s.asleep, s.efficiency * 100),
                axisLeft: "SHORT", axisMid: "OPTIMAL", axisRight: "BANKED")))
        }

        // Training load: full credit in the acute:chronic sweet spot (0.8–1.3). An easy stretch
        // stays positive ("Fresh" — small nudge, you're detraining); overreaching costs real points,
        // and a recent near-max effort discounts the pillar until it decays (~48 h).
        let loadPos: Double = trained
            ? (ratio <= 1.05 ? ratio / 2.1 : 0.5 + min((ratio - 1.05) / 1.05, 1) * 0.5)
            : 0.12
        var loadCredit: Double
        if !trained            { loadCredit = 0.85 }
        else if ratio < 0.8    { loadCredit = 0.85 + 0.15 * (ratio / 0.8) }
        else if ratio <= 1.3   { loadCredit = 1 }
        else                   { loadCredit = max(0.35, 1 - (ratio - 1.3) * 0.6) }
        loadCredit = clamp(loadCredit * effortMult, 0, 1)
        let loadStatus = !trained ? "Building" : ratio < 0.8 ? "Fresh" : ratio <= 1.3 ? "Sweet spot"
                       : ratio <= 1.6 ? "Pushing it" : "Overreached"
        raw.append((25, ReadinessPillar(
            key: "load", label: "Training load", weight: 0,
            credit: loadCredit, position: loadPos, bandLo: 0.381, bandHi: 0.619,
            status: loadStatus,
            detail: trained ? String(format: "acute vs chronic load %.1f×", ratio) : "No recent sessions logged",
            axisLeft: "FRESH", axisMid: "SWEET SPOT", axisRight: "OVERREACHED")))
        if effortMult < 0.95 { flags.append("Near-max effort in the last 48 h — still paying it back") }

        guard recZ != nil else { return ([], flags, nil) }   // no HRV → no score, as ever
        let totalBase = raw.reduce(0) { $0 + $1.base }
        let pillars = raw.map { item -> ReadinessPillar in
            var p = item.p
            p.weight = item.base / totalBase * 100
            return p
        }
        return (pillars, flags, pillars.reduce(0) { $0 + $1.points })
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
