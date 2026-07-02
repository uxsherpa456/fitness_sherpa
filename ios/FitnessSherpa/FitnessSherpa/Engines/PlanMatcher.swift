//  PlanMatcher.swift
//  Ravns
//
//  RAVN-12 — match synced workouts to planned sessions (runtime; decisions in UserDefaults, no schema).
//  HIGH confidence (same day + same category) auto-applies silently and pings a toast. LOW confidence
//  (±1 day or interchangeable conditioning) is held back as a suggestion the athlete confirms or
//  rejects; their decision persists so it isn't re-asked. Feeds the plan card actuals, the "Unplanned"
//  tag, and trailing-7-day adherence — derived each render, so it self-corrects as data syncs.

import Foundation

enum MatchConfidence { case high, low }

/// Persisted athlete decisions about low-confidence matches + which applied matches they've been shown.
struct MatchDecisions: Codable {
    var confirmed: [String: String] = [:]   // plannedID → sessionID (accepted a low-confidence match)
    var rejected: Set<String> = []          // pairKey(plannedID, sessionID) the athlete said no to
    var seen: Set<String> = []              // applied-match pairKeys already toasted

    static let key = "planMatchDecisions.v1"
    static func load() -> MatchDecisions {
        guard let d = UserDefaults.standard.data(forKey: key),
              let m = try? JSONDecoder().decode(MatchDecisions.self, from: d) else { return MatchDecisions() }
        return m
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }
}

enum PlanMatcher {

    static func pairKey(_ planned: UUID, _ session: UUID) -> String { "\(planned.uuidString)|\(session.uuidString)" }

    /// A workout can close a same-category planned session; HIIT/sim/row are interchangeable conditioning.
    static func compatible(planned: SessionCategory, actual: SessionCategory) -> Bool {
        if planned == actual { return true }
        let conditioning: Set<SessionCategory> = [.hiit, .sim, .row]
        return conditioning.contains(planned) && conditioning.contains(actual)
    }

    static func confidence(_ p: PlannedWorkout, _ s: TrainingSession) -> MatchConfidence {
        Calendar.current.isDate(p.date, inSameDayAs: s.date) && p.cat == s.cat ? .high : .low
    }

    /// The full resolution: applied matches (auto-high + athlete-confirmed) and pending low-confidence
    /// suggestions to confirm. Greedy, one-to-one, deterministic by date; confirmations win first.
    static func resolve(planned: [PlannedWorkout], sessions: [TrainingSession], decisions: MatchDecisions)
        -> (applied: [UUID: TrainingSession], suggestions: [(planned: PlannedWorkout, session: TrainingSession)]) {
        let cal = Calendar.current
        let targets = planned.filter { $0.intent != .rest && $0.cat != .rest }.sorted { $0.date < $1.date }
        let byID = Dictionary(sessions.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var used = Set<UUID>()
        var applied: [UUID: TrainingSession] = [:]
        var suggestions: [(planned: PlannedWorkout, session: TrainingSession)] = []

        func candidates(_ p: PlannedWorkout) -> [TrainingSession] {
            let pday = cal.startOfDay(for: p.date)
            return sessions
                .filter { s in
                    !used.contains(s.id)
                        && compatible(planned: p.cat, actual: s.cat)
                        && abs(cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: pday).day ?? 99) <= 1
                        && !decisions.rejected.contains(pairKey(p.id, s.id))
                }
                .sorted { abs($0.date.timeIntervalSince(p.date)) < abs($1.date.timeIntervalSince(p.date)) }
        }

        // 1) athlete-confirmed matches win.
        for p in targets {
            if let sid = decisions.confirmed[p.id.uuidString], let s = byID[sid], !used.contains(s.id),
               compatible(planned: p.cat, actual: s.cat) {
                applied[p.id] = s; used.insert(s.id)
            }
        }
        // 2) high-confidence auto-match.
        for p in targets where applied[p.id] == nil {
            if let s = candidates(p).first(where: { confidence(p, $0) == .high }) {
                applied[p.id] = s; used.insert(s.id)
            }
        }
        // 3) remaining best candidate is low-confidence → a suggestion (reserve the session).
        for p in targets where applied[p.id] == nil {
            if let s = candidates(p).first {
                suggestions.append((p, s)); used.insert(s.id)
            }
        }
        return (applied, suggestions)
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
        let done: Int; let planned: Int; let unplanned: Int
        var pct: Int { planned == 0 ? 0 : Int((Double(done) / Double(planned) * 100).rounded()) }
        var hasPlan: Bool { planned > 0 }
    }

    /// Trailing-7-day adherence (through today) — meaningful mid-week, unlike a whole-week ratio.
    static func adherence(planned: [PlannedWorkout], sessions: [TrainingSession],
                          applied: [UUID: TrainingSession], now: Date = Date()) -> Adherence {
        let cal = Calendar.current
        let end = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -6, to: end) else {
            return Adherence(done: 0, planned: 0, unplanned: 0)
        }
        let inWindow: (Date) -> Bool = { let d = cal.startOfDay(for: $0); return d >= start && d <= end }
        let plannedInWindow = planned.filter { $0.intent != .rest && $0.cat != .rest && inWindow($0.date) }
        let done = plannedInWindow.filter { $0.completed || applied[$0.id] != nil }.count
        let matchedIDs = Set(applied.values.map(\.id))
        let unplanned = sessions.filter { inWindow($0.date) && !matchedIDs.contains($0.id) }.count
        return Adherence(done: done, planned: plannedInWindow.count, unplanned: unplanned)
    }
}
