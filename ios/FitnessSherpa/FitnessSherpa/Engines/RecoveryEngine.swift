//
//  RecoveryEngine.swift
//  Fitness Sherpa
//
//  Two-axis recovery readout built on Apple HealthKit data. Feeds the recovery half of the
//  readiness blend (ReadinessEngine): its log-z HRV + z RHR replace the raw z-scores when there's
//  enough history, and its categorical state is surfaced on the Today card + in the coach context.
//
//  Design notes (read before changing anything):
//  - HealthKit stores HRV exclusively as SDNN. Published "good recovery"
//    thresholds are RMSSD-based and DO NOT transfer. We never compare to
//    external norms — only to the athlete's own rolling baseline.
//  - HRV is log-normal. Raw % swings exaggerate. We log-transform SDNN
//    before computing mean / SD / z-score.
//  - Recovery is two axes (HRV + RHR), never a single percent.
//  - Source tagging: every value carries .source so future code can never
//    accidentally treat SDNN as RMSSD or merge HealthKit over user input.
//

import Foundation

// MARK: - Source tagging

enum MetricSource: String, Codable {
    case user        // manually entered
    case healthkit   // imported, never source of truth
    case system      // derived/computed
}

/// A single morning reading. SDNN is explicit in the name so it can never be
/// confused with RMSSD downstream.
struct MorningReading: Codable {
    let date: Date
    let sdnnMS: Double      // HRV as SDNN, milliseconds
    let rhrBPM: Double      // resting heart rate, bpm
    let source: MetricSource
}

// MARK: - State

enum RecoveryState {
    case insufficientData(daysHave: Int, daysNeed: Int)
    case recovered     // HRV above band, RHR at/below baseline
    case steady        // both within normal band
    case strained      // HRV below band (and/or RHR elevated)
    case watch         // HRV above band AND RHR elevated — saturation/illness/stress

    /// Stable token for the coach context / persistence (the enum's own description isn't clean).
    var key: String {
        switch self {
        case .recovered:        return "recovered"
        case .steady:           return "steady"
        case .strained:         return "strained"
        case .watch:            return "watch"
        case .insufficientData: return "insufficient_data"
        }
    }

    var orbHint: OrbHint {
        switch self {
        case .recovered:        return .init(luminance: .bright, warmth: .warm,  unsettled: false)
        case .steady:           return .init(luminance: .mid,    warmth: .mid,   unsettled: false)
        case .strained:         return .init(luminance: .dim,    warmth: .cool,  unsettled: false)
        case .watch:            return .init(luminance: .bright, warmth: .warm,  unsettled: true)
        case .insufficientData: return .init(luminance: .dim,    warmth: .mid,   unsettled: false)
        }
    }
}

/// Maps to the amber→slate axis + motion vocabulary. No traffic-light colors.
struct OrbHint {
    enum Luminance { case dim, mid, bright }
    enum Warmth    { case cool, mid, warm }
    let luminance: Luminance
    let warmth: Warmth
    let unsettled: Bool   // drives the transient "watch" perturbation, not resting breath
}

// MARK: - Result payload

/// Today's value against the athlete's own "normal" band (±`band`σ) in real units — so the UI can
/// show the actual numbers to beat (e.g. HRV 39 ms · normal 41–83), not just a z-score.
struct AxisRange {
    let today: Double
    let low: Double         // −band edge of normal
    let high: Double        // +band edge of normal
    let unit: String
    let higherIsBetter: Bool
}

struct RecoveryResult {
    let state: RecoveryState
    let headline: String
    let body: String
    let hrvZ: Double?      // nil when insufficient data
    let rhrZ: Double?
    let hrv: AxisRange?    // nil when insufficient data
    let rhr: AxisRange?
    let orbHint: OrbHint
}

// MARK: - Engine

enum RecoveryEngine {

    /// Minimum history before we show any state. HRV baselines are unstable
    /// under ~2 weeks. Below this we refuse to render a verdict.
    static let minimumDays = 14

    /// Window for the rolling baseline.
    static let baselineDays = 60

    /// z-score band that counts as "normal range" for HRV (the primary recovery signal).
    static let band = 1.0

    /// Resting HR is a vital / illness indicator, not a primary recovery dial — lots of benign
    /// things nudge it. So it only reads as "elevated" once it's a real outlier, well past the HRV
    /// band (the way Apple Health surfaces vitals only when they're notably off).
    static let rhrBand = 1.5

    /// Compute today's recovery from a history of morning readings.
    /// `history` should already be filtered to morning readings (first reading
    /// post-wake, not a daily mean) and sorted oldest→newest. `today` is the
    /// current morning's reading and is excluded from baseline math.
    static func evaluate(history: [MorningReading], today: MorningReading) -> RecoveryResult {

        let window = Array(history.suffix(baselineDays))

        guard window.count >= minimumDays else {
            let state = RecoveryState.insufficientData(daysHave: window.count, daysNeed: minimumDays)
            return RecoveryResult(
                state: state,
                headline: "Still learning your baseline",
                body: emptyStateBody(have: window.count, need: minimumDays),
                hrvZ: nil,
                rhrZ: nil,
                hrv: nil,
                rhr: nil,
                orbHint: state.orbHint
            )
        }

        // HRV: log-transform, then z-score.
        let lnHist = window.map { log($0.sdnnMS) }
        let hrvMean = mean(lnHist)
        let hrvSD = stdDev(lnHist, mean: hrvMean)
        let hrvZ = hrvSD > 0 ? (log(today.sdnnMS) - hrvMean) / hrvSD : 0

        // RHR: raw, z-score (RHR is ~normal, no transform needed).
        let rhrHist = window.map { $0.rhrBPM }
        let rhrMean = mean(rhrHist)
        let rhrSD = stdDev(rhrHist, mean: rhrMean)
        let rhrZ = rhrSD > 0 ? (today.rhrBPM - rhrMean) / rhrSD : 0

        let state = classify(hrvZ: hrvZ, rhrZ: rhrZ)
        let copy = readout(for: state)

        // Normal band in real units. HRV band lives in log space → exponentiate back to ms.
        let hrvRange = AxisRange(today: today.sdnnMS,
                                 low: exp(hrvMean - band * hrvSD),
                                 high: exp(hrvMean + band * hrvSD),
                                 unit: "ms", higherIsBetter: true)
        let rhrRange = AxisRange(today: today.rhrBPM,
                                 low: rhrMean - rhrBand * rhrSD,
                                 high: rhrMean + rhrBand * rhrSD,
                                 unit: "bpm", higherIsBetter: false)

        return RecoveryResult(
            state: state,
            headline: copy.headline,
            body: copy.body,
            hrvZ: hrvZ,
            rhrZ: rhrZ,
            hrv: hrvRange,
            rhr: rhrRange,
            orbHint: state.orbHint
        )
    }

    // MARK: Classification

    private static func classify(hrvZ: Double, rhrZ: Double) -> RecoveryState {
        let hrvHigh = hrvZ > band
        let hrvLow  = hrvZ < -band
        let rhrHigh = rhrZ > rhrBand        // only a real outlier counts as elevated

        switch (hrvHigh, hrvLow, rhrHigh) {
        case (true,  _,    true):  return .watch       // up + elevated RHR = divergence
        case (true,  _,    false): return .recovered   // up + clean RHR
        case (_,     true, _):     return .strained    // HRV suppressed
        case (false, false, true): return .strained    // RHR elevated alone
        default:                   return .steady
        }
    }

    // MARK: Copy

    private static func readout(for state: RecoveryState) -> (headline: String, body: String) {
        switch state {
        case .recovered:
            return ("Recovered",
                    "HRV is above your normal range and resting HR is at baseline. Solid autonomic recovery. Train as planned.")
        case .steady:
            return ("Steady",
                    "HRV and resting HR are both in your normal range. Nothing flagged. Train as planned.")
        case .strained:
            return ("Strained",
                    "HRV is below your normal range. Your system is carrying load. Keep it easy or pull back volume, and check sleep.")
        case .watch:
            return ("Watch",
                    "HRV is up but resting HR is also elevated — a split that can mean parasympathetic saturation, stress, or early illness. Not a green light for a max effort. If it persists, look at sleep, hydration, and how you feel.")
        case .insufficientData(let have, let need):
            return ("Still learning your baseline", emptyStateBody(have: have, need: need))
        }
    }

    private static func emptyStateBody(have: Int, need: Int) -> String {
        let remaining = max(0, need - have)
        if have == 0 {
            return "No morning readings yet. Wear your watch to sleep and we'll start building your baseline. \(need) days needed before a recovery readout."
        }
        return "\(have) of \(need) days logged. Readings stabilize around two weeks — \(remaining) more and we can read your recovery against your own history."
    }

    // MARK: Math

    private static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func stdDev(_ xs: [Double], mean m: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let variance = xs.map { pow($0 - m, 2) }.reduce(0, +) / Double(xs.count - 1)
        return variance.squareRoot()
    }
}
