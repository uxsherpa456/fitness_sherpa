//  PlanModels.swift
//  Fitness Sherpa
//
//  The persistent training plan. Each upcoming session is a stored, editable record (not generated
//  on the fly), with the fields the coach reasons over: intent (gates intensity vs readiness),
//  target zone, stations, phase, completed, and source (ai_generated | coach | athlete).

import Foundation
import SwiftData

enum PlanIntent: String, Codable, CaseIterable, Identifiable {
    case easy, quality, recovery, strength, race_sim, rest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy: return "Easy"; case .quality: return "Quality"; case .recovery: return "Recovery"
        case .strength: return "Strength"; case .race_sim: return "Race sim"; case .rest: return "Rest"
        }
    }
}

enum PlanSource: String, Codable { case ai_generated, coach, athlete }

@Model
final class PlannedWorkout: Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var categoryRaw: String = SessionCategory.run.rawValue
    var type: String = ""            // "TEMPO RUN"
    var name: String = ""            // "Tempo run + strides"
    var meta: String = ""            // "8 km tempo · 40 min · RPE 7"
    var intentRaw: String = PlanIntent.easy.rawValue
    var targetZone: String?          // "Z2" | "threshold" | …
    var stations: String?            // HYROX station notes
    var why: String?
    var completed: Bool = false
    var sourceRaw: String = PlanSource.ai_generated.rawValue
    var phase: String = "build"      // base | build | peak | taper
    var weekNumber: Int = 1
    var updatedAt: Date = Date()

    init(date: Date, category: SessionCategory, type: String, name: String, meta: String,
         intent: PlanIntent, targetZone: String? = nil, stations: String? = nil, why: String? = nil,
         source: PlanSource = .ai_generated, phase: String = "build", weekNumber: Int = 1) {
        self.id = UUID()
        self.date = date
        self.categoryRaw = category.rawValue
        self.type = type
        self.name = name
        self.meta = meta
        self.intentRaw = intent.rawValue
        self.targetZone = targetZone
        self.stations = stations
        self.why = why
        self.sourceRaw = source.rawValue
        self.phase = phase
        self.weekNumber = weekNumber
        self.updatedAt = Date()
    }

    var cat: SessionCategory { SessionCategory(rawValue: categoryRaw) ?? .other }
    var intent: PlanIntent { PlanIntent(rawValue: intentRaw) ?? .easy }
    var source: PlanSource { PlanSource(rawValue: sourceRaw) ?? .ai_generated }

    /// Seed the next 7 days from the diagnosis-driven template if the store has no upcoming plan.
    @MainActor
    static func seedIfNeeded(profile: AthleteProfile?, context: ModelContext) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var desc = FetchDescriptor<PlannedWorkout>(predicate: #Predicate { $0.date >= todayStart })
        desc.fetchLimit = 1
        if let existing = try? context.fetch(desc), !existing.isEmpty { return }

        for (i, p) in PlanEngine.recommendedWeek(for: profile).enumerated() {
            let date = cal.date(byAdding: .day, value: i, to: todayStart) ?? todayStart
            context.insert(PlannedWorkout(
                date: date, category: p.category, type: p.type, name: p.name, meta: p.meta,
                intent: intent(for: p), targetZone: zone(for: p), why: p.why))
        }
        try? context.save()
    }

    private static func intent(for p: PlannedSession) -> PlanIntent {
        switch p.category {
        case .rest: return .rest
        case .strength: return .strength
        case .sim: return .race_sim
        default:
            let t = p.type.uppercased()
            if t.contains("TEMPO") || t.contains("THRESHOLD") || t.contains("INTERVAL") { return .quality }
            return .easy
        }
    }
    private static func zone(for p: PlannedSession) -> String? {
        let t = p.type.uppercased()
        if t.contains("Z2") || t.contains("EASY") || t.contains("LONG") { return "Z2" }
        if t.contains("THRESHOLD") { return "threshold" }
        if t.contains("TEMPO") { return "tempo" }
        return nil
    }
}
