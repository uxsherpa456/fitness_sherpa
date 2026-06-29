//  TrainingLoad.swift
//  Fitness Sherpa
//
//  Turns recent workouts into a training-strain picture so readiness reflects what you DID, not
//  just this morning's vitals. Per-session TRIMP (intensity-weighted), EWMA acute (7d) / chronic
//  (42d) load → form, plus a decaying penalty for a recent near-max effort (a PR yesterday should
//  crush today's score even before HRV catches up). Uses your observed max HR as the anchor.

import Foundation

struct LoadResult {
    var atl: Double            // acute load (fatigue), 7-day EWMA of daily TRIMP
    var ctl: Double            // chronic load (fitness), 42-day EWMA
    var form: Double           // ctl - atl  (negative = fatigued)
    var ratio: Double          // atl / ctl  (>1 = acutely overloaded)
    var hrMax: Int             // observed (or age-estimated) max HR
    var lastHardPct: Double?   // % HRmax of the hardest session in the last 72h
    var lastHardHoursAgo: Double?
    var recoveryMultiplier: Double   // 0.5…1.05 applied to the recovery score
    var cappedGreen: Bool      // a ≥95% effort in the last 24h can't return GREEN
}

enum TrainingLoad {
    // Shared helpers (also used by the form-series chart).
    static func hrMaxFor(sessions: [TrainingSession], age: Int) -> Double {
        Double(max(sessions.compactMap { $0.maxHR }.max() ?? 0, 220 - age, 120))
    }
    static func trimp(_ s: TrainingSession, rest: Double, hrMax: Double) -> Double {
        let dur = Double(s.durationMin)
        guard dur > 0 else { return 0 }
        let avg: Double
        if let a = s.avgHR { avg = Double(a) } else {
            let frac: Double
            switch s.cat {
            case .hiit, .sim: frac = 0.85
            case .run, .row:  frac = 0.72
            case .strength:   frac = 0.60
            default:          frac = 0.0
            }
            avg = rest + frac * (hrMax - rest)
        }
        let hrr = min(max((avg - rest) / (hrMax - rest), 0), 1)
        return dur * hrr * 0.64 * exp(1.92 * hrr)            // Banister TRIMP (intensity-weighted)
    }

    /// Daily CTL/ATL/form/ratio over the last `days` — replays the EWMA across workout history.
    static func series(sessions: [TrainingSession], restingHR: Double?, age: Int, days: Int = 30) -> [FormPoint] {
        let rest = restingHR ?? 55
        let hrMax = hrMaxFor(sessions: sessions, age: age)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let total = days + 42                                 // warmup so EWMA is settled by the window
        var daily = [Double](repeating: 0, count: total)
        for s in sessions {
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: today).day ?? 99999
            if diff >= 0, diff < total { daily[total - 1 - diff] += trimp(s, rest: rest, hrMax: hrMax) }
        }
        var atl = 0.0, ctl = 0.0, out: [FormPoint] = []
        let da = exp(-1.0 / 7), dc = exp(-1.0 / 42)
        for i in 0..<total {
            atl = atl * da + daily[i] * (1 - da)
            ctl = ctl * dc + daily[i] * (1 - dc)
            if i >= total - days {
                let date = cal.date(byAdding: .day, value: -(total - 1 - i), to: today) ?? today
                out.append(FormPoint(date: date, ctl: ctl, atl: atl, form: ctl - atl,
                                     ratio: ctl > 0 ? atl / ctl : 1))
            }
        }
        return out
    }

    static func compute(sessions: [TrainingSession], restingHR: Double?, age: Int) -> LoadResult {
        let hrMax = hrMaxFor(sessions: sessions, age: age)
        let rest = restingHR ?? 55
        func trimp(_ s: TrainingSession) -> Double { TrainingLoad.trimp(s, rest: rest, hrMax: hrMax) }

        // Daily TRIMP for the last 42 days, then exponentially-weighted acute/chronic load.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var daily = [Double](repeating: 0, count: 42)
        for s in sessions {
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: today).day ?? 99
            if diff >= 0, diff < 42 { daily[41 - diff] += trimp(s) }
        }
        var atl = 0.0, ctl = 0.0
        let da = exp(-1.0 / 7), dc = exp(-1.0 / 42)
        for t in daily { atl = atl * da + t * (1 - da); ctl = ctl * dc + t * (1 - dc) }
        let ratio = ctl > 0 ? atl / ctl : (atl > 0 ? 2 : 1)
        let loadMult = ratio <= 1 ? 1.0 : max(0.7, 1 - (ratio - 1) * 0.25)   // gentler acute-overload dampener

        // Hardest effort in the last 48h + how long ago (peak HR preferred).
        var lastHardPct: Double?, lastHardHours: Double?
        for s in sessions {
            let hours = Date().timeIntervalSince(s.date) / 3600
            guard hours >= 0, hours <= 48 else { continue }
            let pct: Double
            if let mx = s.maxHR { pct = Double(mx) / hrMax }
            else if let a = s.avgHR { pct = Double(a) / hrMax + 0.05 }
            else {
                switch s.cat {
                case .hiit, .sim: pct = 0.90
                case .run, .row:  pct = 0.80
                case .strength:   pct = 0.70
                default:          pct = 0
                }
            }
            if pct > (lastHardPct ?? 0) { lastHardPct = pct; lastHardHours = hours }
        }

        var effortMult = 1.0, cappedGreen = false
        if let pct = lastHardPct, let hours = lastHardHours {
            let severity = min(max((pct - 0.90) / 0.10, 0), 1) * 0.22    // up to −0.22 at maximal effort
            let decay = max(0, 1 - hours / 48)                          // mostly gone by ~2 days
            effortMult = 1 - severity * decay
            if pct >= 0.95, hours < 18 { cappedGreen = true }           // hard cap only the day-of window
        }

        return LoadResult(
            atl: atl, ctl: ctl, form: ctl - atl, ratio: ratio, hrMax: Int(hrMax),
            lastHardPct: lastHardPct, lastHardHoursAgo: lastHardHours,
            recoveryMultiplier: max(0.5, loadMult * effortMult),
            cappedGreen: cappedGreen)
    }
}
