//  WorkoutModels.swift
//  Fitness Sherpa
//
//  The durable training-data layer (Becoming spec). Our store — not HealthKit — owns the data.
//  HealthKit is an input that reconciles in field-by-field: user edits and manual entries are never
//  silently overwritten. Every field carries its provenance (source / updatedAt / isEdited), and the
//  HealthKit join key (healthkitUUID) is what protects the manual layer.

import Foundation
import SwiftData

enum FieldSource: String, Codable { case user, healthkit, system }

struct FieldMeta: Codable, Equatable {
    var source: FieldSource
    var updatedAt: Date
    var isEdited: Bool
    static func mk(_ s: FieldSource) -> FieldMeta { FieldMeta(source: s, updatedAt: Date(), isEdited: s == .user) }
}

/// Per-field provenance for a session. Field-level (not workout-level) is what makes a clean merge.
struct Provenance: Codable, Equatable {
    var date: FieldMeta
    var category: FieldMeta
    var title: FieldMeta
    var durationMin: FieldMeta
    var distanceKm: FieldMeta
    var calories: FieldMeta
    var avgHR: FieldMeta
    var maxHR: FieldMeta
    var rpe: FieldMeta
    var notes: FieldMeta

    init(_ source: FieldSource) {
        let m = FieldMeta.mk(source)
        date = m; category = m; title = m; durationMin = m; distanceKm = m
        calories = m; avgHR = m; maxHR = m; rpe = m; notes = m
    }

    // Tolerant decode: fields added after older rows were stored default to .healthkit instead of
    // failing the whole decode (keeps already-persisted sessions loading after a model change).
    private enum CodingKeys: String, CodingKey {
        case date, category, title, durationMin, distanceKm, calories, avgHR, maxHR, rpe, notes
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys) -> FieldMeta { (try? c.decode(FieldMeta.self, forKey: k)) ?? .mk(.healthkit) }
        date = f(.date); category = f(.category); title = f(.title)
        durationMin = f(.durationMin); distanceKm = f(.distanceKm)
        calories = f(.calories); avgHR = f(.avgHR); maxHR = f(.maxHR)
        rpe = f(.rpe); notes = f(.notes)
    }

    var anyEdited: Bool {
        [date, category, title, durationMin, distanceKm, calories, avgHR, maxHR, rpe, notes].contains { $0.isEdited }
    }
}

/// Incoming HealthKit values that conflict with user-edited fields — held for review, not merged.
struct HKProposal: Codable, Equatable {
    var date: Date?
    var category: String?
    var title: String?
    var durationMin: Int?
    var distanceKm: Double?
    var calories: Double?
    var avgHR: Int?
    var maxHR: Int?
    var isEmpty: Bool {
        date == nil && category == nil && title == nil && durationMin == nil
            && distanceKm == nil && calories == nil && avgHR == nil && maxHR == nil
    }
}

@Model
final class TrainingSession: Identifiable {
    var id: UUID = UUID()
    var healthkitUUID: UUID?        // join key; nil = manual-only, import never reaches it
    var date: Date = Date()
    var category: String = SessionCategory.run.rawValue
    var title: String = "Workout"
    var durationMin: Int = 0
    var distanceKm: Double?
    var caloriesKcal: Double?
    var avgHR: Int?
    var maxHR: Int?
    var rpe: Int?
    var notes: String?
    var provenance: Provenance = Provenance(.user)
    var hasHKConflict: Bool = false
    var hkProposal: HKProposal?

    init(healthkitUUID: UUID?, date: Date, category: String, title: String,
         durationMin: Int, distanceKm: Double?, caloriesKcal: Double? = nil,
         avgHR: Int? = nil, maxHR: Int? = nil, rpe: Int? = nil,
         notes: String? = nil, source: FieldSource) {
        self.id = UUID()
        self.healthkitUUID = healthkitUUID
        self.date = date
        self.category = category
        self.title = title
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.caloriesKcal = caloriesKcal
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.rpe = rpe
        self.notes = notes
        self.provenance = Provenance(source)
    }

    var cat: SessionCategory { SessionCategory(rawValue: category) ?? .other }
    var isManual: Bool { healthkitUUID == nil }
    var isEdited: Bool { provenance.anyEdited }

    convenience init(from w: HealthData.Workout) {
        self.init(healthkitUUID: w.id, date: w.date, category: w.category.rawValue,
                  title: w.typeLabel, durationMin: w.durationMin, distanceKm: w.distanceKm,
                  caloriesKcal: w.caloriesKcal, avgHR: w.avgHR, maxHR: w.maxHR,
                  source: .healthkit)
    }

    // MARK: Import reconciliation (§5/§6)

    /// Apply an incoming HealthKit value field by field. User fields are never overwritten —
    /// a differing value is flagged for review instead. healthkit/system fields take the import.
    func applyImport(_ w: HealthData.Workout) {
        var proposal = HKProposal()

        if provenance.date.source == .user {
            if abs(date.timeIntervalSince(w.date)) > 60 { proposal.date = w.date }
        } else { date = w.date; provenance.date = .mk(.healthkit) }

        if provenance.category.source == .user {
            if category != w.category.rawValue { proposal.category = w.category.rawValue }
        } else { category = w.category.rawValue; provenance.category = .mk(.healthkit) }

        if provenance.title.source == .user {
            if title != w.typeLabel { proposal.title = w.typeLabel }
        } else { title = w.typeLabel; provenance.title = .mk(.healthkit) }

        if provenance.durationMin.source == .user {
            if durationMin != w.durationMin { proposal.durationMin = w.durationMin }
        } else { durationMin = w.durationMin; provenance.durationMin = .mk(.healthkit) }

        if provenance.distanceKm.source == .user {
            if distanceKm != w.distanceKm { proposal.distanceKm = w.distanceKm }
        } else { distanceKm = w.distanceKm; provenance.distanceKm = .mk(.healthkit) }

        if provenance.calories.source == .user {
            if caloriesKcal != w.caloriesKcal { proposal.calories = w.caloriesKcal }
        } else { caloriesKcal = w.caloriesKcal; provenance.calories = .mk(.healthkit) }

        if provenance.avgHR.source == .user {
            if avgHR != w.avgHR { proposal.avgHR = w.avgHR }
        } else { avgHR = w.avgHR; provenance.avgHR = .mk(.healthkit) }

        if provenance.maxHR.source == .user {
            if maxHR != w.maxHR { proposal.maxHR = w.maxHR }
        } else { maxHR = w.maxHR; provenance.maxHR = .mk(.healthkit) }

        if proposal.isEmpty {
            hasHKConflict = false; hkProposal = nil
        } else {
            hasHKConflict = true; hkProposal = proposal
        }
    }

    /// Resolve a conflict by taking Apple Health's values (re-stamps those fields as healthkit).
    func resolveUseHealthKit() {
        guard let p = hkProposal else { return }
        if let v = p.date { date = v; provenance.date = .mk(.healthkit) }
        if let v = p.category { category = v; provenance.category = .mk(.healthkit) }
        if let v = p.title { title = v; provenance.title = .mk(.healthkit) }
        if let v = p.durationMin { durationMin = v; provenance.durationMin = .mk(.healthkit) }
        if p.distanceKm != nil { distanceKm = p.distanceKm; provenance.distanceKm = .mk(.healthkit) }
        if p.calories != nil { caloriesKcal = p.calories; provenance.calories = .mk(.healthkit) }
        if p.avgHR != nil { avgHR = p.avgHR; provenance.avgHR = .mk(.healthkit) }
        if p.maxHR != nil { maxHR = p.maxHR; provenance.maxHR = .mk(.healthkit) }
        hasHKConflict = false; hkProposal = nil
    }

    /// Resolve a conflict by keeping the user's values (discards the proposal).
    func resolveKeepMine() { hasHKConflict = false; hkProposal = nil }

    // MARK: Import entry point

    /// Reconcile a batch of HealthKit workouts into the store (match by healthkitUUID).
    @MainActor
    static func reconcile(_ workouts: [HealthData.Workout], context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
        var byUUID: [UUID: TrainingSession] = [:]
        for s in existing { if let u = s.healthkitUUID { byUUID[u] = s } }

        for w in workouts {
            if let s = byUUID[w.id] {
                s.applyImport(w)
            } else {
                context.insert(TrainingSession(from: w))
            }
        }
        try? context.save()
    }
}
