//  PlanMatcher.swift
//  Ravns
//
//  RAVN-12 — auto-match synced workouts to planned sessions (runtime, no persistence). A planned
//  session is "done" when a compatible workout lands within ±1 day; the match feeds the plan card's
//  actuals, the "Unplanned" tag on stray workouts, and weekly plan-adherence. Derived each render
//  from the plan + workouts already in the store, so it self-corrects as data syncs — nothing stored.

import Foundation

enum PlanMatcher {

    /// planned.id → the workout that satisfies it. Greedy, one-to-one, deterministic (by date).
    static func matchMap(planned: [PlannedWorkout], sessions: [TrainingSession]) -> [UUID: TrainingSession] {
        let cal = Calendar.current
        let targets = planned.filter { $0.intent != .rest && $0.cat != .rest }
            .sorted { $0.date < $1.date }
        var used = Set<UUID>()
        var map: [UUID: TrainingSession] = [:]
        for p in targets {
            let pday = cal.startOfDay(for: p.date)
            let best = sessions
                .filter { s in
                    !used.contains(s.id)
                        && compatible(planned: p.cat, actual: s.cat)
                        && abs(cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: pday).day ?? 99) <= 1
                }
                .min { abs($0.date.timeIntervalSince(p.date)) < abs($1.date.timeIntervalSince(p.date)) }
            if let best { map[p.id] = best; used.insert(best.id) }
        }
        return map
    }

    /// A workout can close a planned session of the same category (HIIT/sim/row are interchangeable
    /// as high-intensity conditioning). Strict elsewhere so we don't false-match a run to a lift.
    static func compatible(planned: SessionCategory, actual: SessionCategory) -> Bool {
        if planned == actual { return true }
        let conditioning: Set<SessionCategory> = [.hiit, .sim, .row]
        return conditioning.contains(planned) && conditioning.contains(actual)
    }

    /// "36 min · 158 bpm · 3.9 mi · 442 cal" — the matched workout's output for the plan card.
    static func actualSummary(_ s: TrainingSession, _ settings: UserSettings) -> String {
        var parts = ["\(s.durationMin) min"]
        if let hr = s.avgHR { parts.append("\(hr) bpm") }
        if let km = s.distanceKm, km > 0, let d = Units.displayDistance(km: km, settings) { parts.append(d) }
        if let cal = s.caloriesKcal, cal > 0 { parts.append("\(Int(cal.rounded())) cal") }
        return parts.joined(separator: " · ")
    }

    struct Adherence {
        let done: Int          // planned sessions completed or matched
        let planned: Int       // planned (non-rest) sessions in the window
        let unplanned: Int     // workouts in the window not matching any plan
        var pct: Int { planned == 0 ? 0 : Int((Double(done) / Double(planned) * 100).rounded()) }
        var hasPlan: Bool { planned > 0 }
    }

    /// Trailing-7-day adherence (through today) — meaningful mid-week, unlike a whole-week ratio.
    static func adherence(planned: [PlannedWorkout], sessions: [TrainingSession],
                          matches: [UUID: TrainingSession], now: Date = Date()) -> Adherence {
        let cal = Calendar.current
        let end = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -6, to: end) else {
            return Adherence(done: 0, planned: 0, unplanned: 0)
        }
        let window: (Date) -> Bool = { d in
            let day = cal.startOfDay(for: d); return day >= start && day <= end
        }
        let plannedInWindow = planned.filter { $0.intent != .rest && $0.cat != .rest && window($0.date) }
        let done = plannedInWindow.filter { $0.completed || matches[$0.id] != nil }.count
        let matchedIDs = Set(matches.values.map { $0.id })
        let unplanned = sessions.filter { window($0.date) && !matchedIDs.contains($0.id) }.count
        return Adherence(done: done, planned: plannedInWindow.count, unplanned: unplanned)
    }
}
