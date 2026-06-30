//  Readiness.swift
//  Ravns
//
//  Readiness v1.1 — baseline-relative recovery × training strain × how you feel.
//  Each recovery signal is a z-score vs the athlete's own ~60-day baseline (population priors until
//  enough history). That blend is then scaled by training load (recent strain via TrainingLoad) and
//  the athlete's subjective check. Every input is exposed for evidence/coaching.

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

struct ReadinessResult {
    var score: Int?                // recovery × load (before the subjective feeling, applied later)
    var components: [ReadinessComponent]
    var recovery: RecoveryResult?  // two-axis HRV/RHR readout (log-z HRV + z RHR) feeding the blend
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
        let degC = HKUnit.degreeCelsius()

        async let hrvBaseT  = HealthData.baseline(.heartRateVariabilitySDNN, unit: ms)
        async let rhrBaseT  = HealthData.baseline(.restingHeartRate, unit: bpm)
        async let respBaseT = HealthData.baseline(.respiratoryRate, unit: bpm)
        async let tempBaseT = HealthData.baseline(.appleSleepingWristTemperature, unit: degC)
        async let respTodayT = try? HealthData.latestSample(.respiratoryRate, unit: bpm)
        async let tempTodayT = try? HealthData.latestSample(.appleSleepingWristTemperature, unit: degC)
        async let morningT = try? HealthData.morningReadings()

        let hrvBase = await hrvBaseT, rhrBase = await rhrBaseT
        let respBase = await respBaseT, tempBase = await tempBaseT
        let respToday = (await respTodayT) ?? nil
        let tempToday = (await tempTodayT) ?? nil
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

        if let t = tempToday?.value, let tb = tempBase {
            comps.append(ReadinessComponent(label: "Wrist temp", value: t, unit: "°C",
                                            z: -min(abs((t - tb.mean) / tb.sd), 2), weight: 0.10, personal: true))
        }
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

        // Recovery is driven by the continuous "how recovered" signals — HRV and sleep. The vitals
        // (resting HR, respiratory rate, wrist temp) are illness / strain flags: like Apple Health,
        // they only pull the score down when they're genuine outliers, not for the ordinary ±1σ
        // wobble that a hard session, heat, or a late meal routinely cause.
        let driverLabels: Set<String> = ["HRV", "Sleep"]
        let drivers = comps.filter { driverLabels.contains($0.label) }
        let vitals  = comps.filter { !driverLabels.contains($0.label) }

        let driverW = drivers.reduce(0) { $0 + $1.weight }
        let base = driverW > 0
            ? drivers.reduce(0.0) { $0 + (($1.z + 2) / 4 * 100) * ($1.weight / driverW) }
            : 50.0

        // Dead-zoned vital penalty: nothing within ±deadzone σ, ramping to a full hit by ±fullAt σ.
        // `z` is already sign-flipped (negative = worse: elevated RHR / resp, or temp deviation),
        // so only bad outliers bite — a low resting HR or a normal reading never costs you.
        let deadzone = 1.5, fullAt = 3.0
        let penalty = vitals.reduce(0.0) { acc, c in
            let excess = max(0, -c.z - deadzone)
            return acc + min(excess / (fullAt - deadzone), 1) * c.weight
        }
        let recoveryPct = base * (1 - min(penalty, 0.6))   // vitals can dock at most 60%
        let scored = recoveryPct * load.recoveryMultiplier
        result.score = Int(min(100, max(0, scored.rounded())))
        return result
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
