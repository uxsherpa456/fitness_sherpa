//  Models.swift
//  Fitness Sherpa
//
//  SwiftData schema — the local source of truth (offline-first) that the diagnosis,
//  trends, and coach reason over. A "goal" is modeled as a concept with HYROX as the
//  only instance for now, structured to extend later.
//
//  NOTE: the live schema is AppSchemaV2 in Migrations.swift. Goal / Session / Benchmark below are
//  legacy/orphaned (superseded by TrainingSession / PlannedWorkout / GoalArc); slated for removal
//  in a future schema version.

import Foundation
import SwiftData

/// The fixed race goal — the point everything reasons against.
@Model final class Goal {
    var sport: String          // "HYROX"
    var targetTime: String     // "1:10:00"
    var raceDate: Date
    var location: String       // "Washington DC"
    var createdAt: Date

    init(sport: String = "HYROX", targetTime: String, raceDate: Date,
         location: String, createdAt: Date = .now) {
        self.sport = sport
        self.targetTime = targetTime
        self.raceDate = raceDate
        self.location = location
        self.createdAt = createdAt
    }
}

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

    /// Build the engine input from this baseline (with sensible fallbacks).
    func asInput() -> DiagnosisInput {
        DiagnosisInput(bodyweightLb: bodyweightLb ?? 214,
                       recent5k: recent5kSeconds ?? DiagnosisEngine.parse5k("25:45"),
                       stationsHold: stationsHold ?? true)
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

/// A confirmed cardio workout (imported from HealthKit) or a manual session.
@Model final class Session {
    var date: Date
    var type: String           // "run" | "strength" | "station" | "sim" | "recovery"
    var durationMin: Int
    var distanceKm: Double?
    var avgPace: String?       // "5:18/km"
    var avgHR: Int?
    var hrDriftPct: Double?     // the "did the aerobic base hold" read
    var rpe: Int?
    var source: String         // "healthkit" | "manual"

    init(date: Date = .now, type: String, durationMin: Int, distanceKm: Double? = nil,
         avgPace: String? = nil, avgHR: Int? = nil, hrDriftPct: Double? = nil,
         rpe: Int? = nil, source: String = "manual") {
        self.date = date
        self.type = type
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.avgPace = avgPace
        self.avgHR = avgHR
        self.hrDriftPct = hrDriftPct
        self.rpe = rpe
        self.source = source
    }
}

/// A manual station / strength benchmark HealthKit can't capture.
@Model final class Benchmark {
    var date: Date
    var name: String           // "Wall balls" | "Sled push" | "Back squat 5RM"
    var value: String          // "100 reps" | "2:10" | "120 kg"
    var underFatigue: String?  // "held" | "slipped" | "blew up"

    init(date: Date = .now, name: String, value: String, underFatigue: String? = nil) {
        self.date = date
        self.name = name
        self.value = value
        self.underFatigue = underFatigue
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
