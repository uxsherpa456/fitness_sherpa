//  Models.swift
//  Fitness Sherpa
//
//  SwiftData schema — the local source of truth (offline-first) that the diagnosis,
//  trends, and coach reason over. A "goal" is modeled as a concept with HYROX as the
//  only instance for now, structured to extend later.
//
//  NOTE: the live schema is AppSchemaV3 in Migrations.swift. The orphaned Goal / Session / Benchmark
//  models moved to LegacySchema.swift (kept only for migration history).

import Foundation
import SwiftData

/// A baseline assessment entry the diagnosis reasons over (from onboarding or re-runs).
@Model final class Baseline {
    var date: Date
    var bodyweightLb: Double?
    var bodyFatPct: Double?
    var recent5kSeconds: Double?
    var stationsHold: Bool?     // self-assessed strength-axis input

    init(date: Date = .now, bodyweightLb: Double? = nil, bodyFatPct: Double? = nil,
         recent5kSeconds: Double? = nil, stationsHold: Bool? = nil) {
        self.date = date
        self.bodyweightLb = bodyweightLb
        self.bodyFatPct = bodyFatPct
        self.recent5kSeconds = recent5kSeconds
        self.stationsHold = stationsHold
    }

    /// Build the engine input from this baseline (with sensible fallbacks). `stationsHold` is the
    /// stored boolean snapshot; the live diagnosis prefers `settings.strengthAxis` for full precision.
    func asInput() -> DiagnosisInput {
        DiagnosisInput(bodyweightLb: bodyweightLb ?? 214,
                       bodyFatPct: bodyFatPct ?? 0,
                       recent5k: recent5kSeconds ?? DiagnosisEngine.parse5k("25:45"),
                       strengthAxis: (stationsHold ?? true) ? 0.78 : 0.30)
    }
}

/// A stored diagnosis result. Re-runs over time so the limiter can be tracked.
@Model final class DiagnosisRecord {
    var date: Date
    var profileRaw: Int
    var limiter: String
    var focus: String
    var runAxis: Double
    var strengthAxis: Double
    var markerX: Double
    var markerY: Double
    var evidence: String

    var profile: AthleteProfile { AthleteProfile(rawValue: profileRaw) ?? .weakAtEverything }

    init(_ d: Diagnosis, date: Date = .now) {
        self.date = date
        self.profileRaw = d.profile.rawValue
        self.limiter = d.limiter
        self.focus = d.focus
        self.runAxis = d.runAxis
        self.strengthAxis = d.strengthAxis
        self.markerX = d.markerX
        self.markerY = d.markerY
        self.evidence = d.evidence
    }
}

/// A point-in-time HealthKit read — the freshness-stamped snapshot sent to the coach.
@Model final class HealthSnapshot {
    var capturedAt: Date
    var hrv: Double?
    var restingHR: Double?
    var sleepHrs: Double?
    var vo2max: Double?
    var activeEnergyKcal: Double?
    var staleMetrics: [String]  // names the freshness guardrail flags this turn

    init(capturedAt: Date = .now, hrv: Double? = nil, restingHR: Double? = nil,
         sleepHrs: Double? = nil, vo2max: Double? = nil, activeEnergyKcal: Double? = nil,
         staleMetrics: [String] = []) {
        self.capturedAt = capturedAt
        self.hrv = hrv
        self.restingHR = restingHR
        self.sleepHrs = sleepHrs
        self.vo2max = vo2max
        self.activeEnergyKcal = activeEnergyKcal
        self.staleMetrics = staleMetrics
    }

    var isFresh: Bool { staleMetrics.isEmpty }
}
