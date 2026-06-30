//  PlanModels.swift
//  Ravns
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

    /// Generate the full periodized plan to race day if the store has no upcoming plan.
    @MainActor
    static func seedIfNeeded(profile: AthleteProfile?, settings: UserSettings, context: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var desc = FetchDescriptor<PlannedWorkout>(predicate: #Predicate { $0.date >= todayStart })
        desc.fetchLimit = 1
        if let existing = try? context.fetch(desc), !existing.isEmpty { return }
        insertGeneratedPlan(profile: profile, settings: settings, context: context)
    }

    /// Rebuild the future plan from scratch (after a re-diagnosis / changed race date). Preserves
    /// coach- and athlete-authored sessions; only the auto-generated future ones are replaced.
    @MainActor
    static func regeneratePlan(profile: AthleteProfile?, settings: UserSettings, context: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let aiRaw = PlanSource.ai_generated.rawValue
        let desc = FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= todayStart && $0.sourceRaw == aiRaw })
        if let existing = try? context.fetch(desc) { existing.forEach { context.delete($0) } }
        insertGeneratedPlan(profile: profile, settings: settings, context: context)
    }

    @MainActor
    private static func insertGeneratedPlan(profile: AthleteProfile?, settings: UserSettings, context: ModelContext) {
        let generated = PlanEngine.generate(profile: profile, settings: settings, startDate: Date())
        for g in generated {
            context.insert(PlannedWorkout(
                date: g.date, category: g.category, type: g.type, name: g.name, meta: g.meta,
                intent: g.intent, targetZone: g.zone, why: g.why, phase: g.phase.rawValue, weekNumber: g.weekNumber))
        }
        try? context.save()
    }
}
