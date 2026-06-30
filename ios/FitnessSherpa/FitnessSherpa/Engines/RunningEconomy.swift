//  RunningEconomy.swift
//  Ravns
//
//  Running-economy engine for runners working on getting faster. One pipeline, computed client-side
//  from the runs we already ingest (TrainingSession) — no backend needed:
//
//    valid run  →  aerobic-efficiency ratio (speed per unit of cardiac strain, Karvonen HRR)
//               →  Economy Index, normalized 0–100 against the athlete's OWN 28-day rolling baseline
//               →  weekly rollup + a Z2 (easy-day) pace/HR trend
//
//  Everything is self-relative (50 = your baseline), so it holds up across bodyweight changes and
//  never compares the athlete to anyone else. VDOT (aerobic ceiling) comes from the recent 5k.

import Foundation

struct EconomySample: Identifiable {
    let id = UUID()
    let date: Date
    let distanceKm: Double
    let paceSecPerKm: Double
    let avgHR: Int
    let hrReserve: Double      // Karvonen 0…1
    let aer: Double            // (km/min) / HRR — higher = better economy
    let zone: Int              // 1…5 from HRR
    let isFresh: Bool          // not in the 12h shadow of a hard effort
    let index: Double?         // 0…100 vs 28-day baseline (nil before a baseline exists)
}

struct EconomyWeek: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    let avgIndex: Double?
    let z2PaceSecPerKm: Double?
    let hrAtZ2: Int?
    let count: Int
}

struct EconomyResult {
    let samples: [EconomySample]   // newest → oldest
    let weeks: [EconomyWeek]       // oldest → newest
    let validCount: Int
    let building: Bool             // < 5 valid samples → cold start
    let index: Double?             // latest Economy Index (recent mean)
    let deltaPts: Double?          // change vs ~4 weeks ago (the card arrow)
    let baselineAER: Double?
    let z2PaceSecPerKm: Double?    // recent easy-day floor
    let hrAtZ2: Int?
    let vdot: Double               // current aerobic ceiling (from 5k)

    static let empty = EconomyResult(samples: [], weeks: [], validCount: 0, building: true,
                                     index: nil, deltaPts: nil, baselineAER: nil,
                                     z2PaceSecPerKm: nil, hrAtZ2: nil, vdot: 0)
}

enum RunningEconomy {
    static let minValidSamples = 5
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    /// HRR → training zone (1 easy … 5 max). Z2 is the aerobic/easy floor we trend economy on.
    private static func zone(_ hrr: Double) -> Int {
        switch hrr {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default:      return 5
        }
    }

    /// A run is "hard" if it's a sim/HIIT, RPE ≥ 8, or ran above ~85% HRR — used for the fresh shadow.
    private static func isHard(_ s: TrainingSession, rest: Double, hrMax: Double) -> Bool {
        if s.cat == .hiit || s.cat == .sim { return true }
        if let rpe = s.rpe, rpe >= 8 { return true }
        if let hr = s.avgHR.map(Double.init), hrMax > rest {
            return (hr - rest) / (hrMax - rest) > 0.85
        }
        return false
    }

    static func compute(sessions: [TrainingSession], restingHR: Double?, age: Int,
                        recent5k: TimeInterval) -> EconomyResult {
        let rest = restingHR ?? 55
        let hrMax = TrainingLoad.hrMaxFor(sessions: sessions, age: age)
        guard hrMax > rest else { return .empty }
        let vdot = DiagnosisEngine.vdot(seconds: recent5k)

        // Build raw samples from valid runs: a run, ≥ 2 km, with usable HR in the aerobic+ band.
        let runs = sessions.filter { $0.cat == .run }.sorted { $0.date > $1.date }
        var raw: [(s: TrainingSession, pace: Double, hrr: Double, aer: Double, fresh: Bool)] = []
        for s in runs {
            guard let km = s.distanceKm, km >= 2, s.durationMin > 0, let hr = s.avgHR else { continue }
            let hrr = clamp((Double(hr) - rest) / (hrMax - rest), 0, 1)
            guard hrr > 0.4 else { continue }                 // walking / GPS-noise floor
            let paceSecPerKm = Double(s.durationMin) * 60 / km
            let speedKmPerMin = 1 / (paceSecPerKm / 60)
            let aer = speedKmPerMin / hrr
            // Fresh = no hard effort in the 12h before this run.
            let fresh = !sessions.contains { other in
                guard other.id != s.id else { return false }
                let gap = s.date.timeIntervalSince(other.date)
                return gap > 0 && gap <= 12 * 3600 && isHard(other, rest: rest, hrMax: hrMax)
            }
            raw.append((s, paceSecPerKm, hrr, aer, fresh))
        }

        let validCount = raw.count
        guard validCount >= 1 else { return EconomyResult(samples: [], weeks: [], validCount: 0,
                                                          building: true, index: nil, deltaPts: nil,
                                                          baselineAER: nil, z2PaceSecPerKm: nil,
                                                          hrAtZ2: nil, vdot: vdot) }

        // 28-day rolling baseline AER from FRESH samples (fatigue confounds economy).
        let now = raw.first?.s.date ?? Date()
        let baselinePool = raw.filter { $0.fresh && now.timeIntervalSince($0.s.date) <= 28 * 86400 }
        let baseSource = baselinePool.isEmpty ? raw.filter(\.fresh) : baselinePool
        let baselineAER = baseSource.isEmpty ? nil : baseSource.map(\.aer).reduce(0, +) / Double(baseSource.count)
        let building = validCount < minValidSamples

        func indexFor(_ aer: Double) -> Double? {
            guard let b = baselineAER, b > 0, !building else { return nil }
            return clamp(50 + (aer / b - 1) * 100, 0, 100)    // 50 = baseline; +10% AER → 60
        }

        let samples = raw.map { r in
            EconomySample(date: r.s.date, distanceKm: r.s.distanceKm ?? 0, paceSecPerKm: r.pace,
                          avgHR: r.s.avgHR ?? 0, hrReserve: r.hrr, aer: r.aer, zone: zone(r.hrr),
                          isFresh: r.fresh, index: indexFor(r.aer))
        }

        // Weekly rollup (calendar weeks, Monday start), oldest → newest.
        let cal = Calendar.current
        let groups = Dictionary(grouping: samples) { s in
            cal.dateInterval(of: .weekOfYear, for: s.date)?.start ?? cal.startOfDay(for: s.date)
        }
        let weeks = groups.keys.sorted().map { wk -> EconomyWeek in
            let items = groups[wk] ?? []
            let idxs = items.compactMap(\.index)
            let z2 = items.filter { $0.zone <= 2 && $0.isFresh }
            return EconomyWeek(weekStart: wk,
                               avgIndex: idxs.isEmpty ? nil : idxs.reduce(0, +) / Double(idxs.count),
                               z2PaceSecPerKm: z2.isEmpty ? nil : z2.map(\.paceSecPerKm).reduce(0, +) / Double(z2.count),
                               hrAtZ2: z2.isEmpty ? nil : Int((z2.map { Double($0.avgHR) }.reduce(0, +) / Double(z2.count)).rounded()),
                               count: items.count)
        }

        // Headline index = mean of last-14-day sample indices; delta vs ~4 weeks back.
        let recent = samples.filter { now.timeIntervalSince($0.date) <= 14 * 86400 }.compactMap(\.index)
        let index = recent.isEmpty ? samples.compactMap(\.index).first : recent.reduce(0, +) / Double(recent.count)
        let priorWeekIdx = weeks.first(where: { now.timeIntervalSince($0.weekStart) >= 21 * 86400 })?.avgIndex
            ?? weeks.first?.avgIndex
        let deltaPts = (index != nil && priorWeekIdx != nil) ? index! - priorWeekIdx! : nil

        // Recent Z2 (easy-day) floor: fresh easy runs in the last 28 days.
        let z2Recent = samples.filter { $0.zone <= 2 && $0.isFresh && now.timeIntervalSince($0.date) <= 28 * 86400 }
        let z2Pace = z2Recent.isEmpty ? nil : z2Recent.map(\.paceSecPerKm).reduce(0, +) / Double(z2Recent.count)
        let hrAtZ2 = z2Recent.isEmpty ? nil : Int((z2Recent.map { Double($0.avgHR) }.reduce(0, +) / Double(z2Recent.count)).rounded())

        return EconomyResult(samples: samples, weeks: weeks, validCount: validCount, building: building,
                             index: index, deltaPts: deltaPts, baselineAER: baselineAER,
                             z2PaceSecPerKm: z2Pace, hrAtZ2: hrAtZ2, vdot: vdot)
    }

    /// Format a pace (sec/km) for the athlete's distance unit: "9:30/mi".
    static func paceLabel(_ secPerKm: Double, unit: String) -> String {
        let p = secPerKm * (unit == "mi" ? 1.609344 : 1)
        let s = Int(p.rounded())
        return String(format: "%d:%02d/%@", s / 60, s % 60, unit)
    }
}
