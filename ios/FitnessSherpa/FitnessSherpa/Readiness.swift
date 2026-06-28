//  Readiness.swift
//  Fitness Sherpa
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
    var cappedGreen: Bool = false
    // training load context (for the card + coach)
    var atl: Double = 0
    var ctl: Double = 0
    var form: Double = 0
    var ratio: Double = 1
    var hrMax: Int = 0
    var lastHardPct: Double?
    var lastHardHoursAgo: Double?
    var recoveryMultiplier: Double = 1
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

        let hrvBase = await hrvBaseT, rhrBase = await rhrBaseT
        let respBase = await respBaseT, tempBase = await tempBaseT
        let respToday = (await respTodayT) ?? nil
        let tempToday = (await tempTodayT) ?? nil

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

        add("HRV", reading.hrv?.value, hrvBase, prior: hrvPrior, weight: 0.35, unit: "ms", invert: false)
        add("Resting HR", reading.restingHR?.value, rhrBase, prior: rhrPrior, weight: 0.20, unit: "bpm", invert: true)
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

        var result = ReadinessResult(score: nil, components: comps, cappedGreen: load.cappedGreen,
                                     atl: load.atl, ctl: load.ctl, form: load.form, ratio: load.ratio,
                                     hrMax: load.hrMax, lastHardPct: load.lastHardPct,
                                     lastHardHoursAgo: load.lastHardHoursAgo,
                                     recoveryMultiplier: load.recoveryMultiplier)

        guard reading.hrv != nil, !comps.isEmpty else { return result }

        let totalW = comps.reduce(0) { $0 + $1.weight }
        let recovery = comps.reduce(0.0) { $0 + (($1.z + 2) / 4 * 100) * ($1.weight / totalW) }
        let scored = recovery * load.recoveryMultiplier
        result.score = Int(min(100, max(0, scored.rounded())))
        return result
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
