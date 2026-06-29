//  LegacySchema.swift
//  Fitness Sherpa
//
//  Orphaned @Models kept ONLY so AppSchemaV1/V2 (Migrations.swift) still describe the shape that
//  created existing stores. They are excluded from AppSchemaV3; the V2→V3 lightweight stage drops
//  their (empty) tables without touching real data. Do not use these — superseded by TrainingSession
//  (workouts), GoalArc (goals), and the manual Benchmark plan was never wired up. Delete once no
//  installed build still sits on schema ≤ V2.

import Foundation
import SwiftData

@Model final class Goal {
    var sport: String = "HYROX"
    var targetTime: String = ""
    var raceDate: Date = Date()
    var location: String = ""
    var createdAt: Date = Date()
    init() {}
}

@Model final class Session {
    var date: Date = Date()
    var type: String = ""
    var durationMin: Int = 0
    var distanceKm: Double?
    var avgPace: String?
    var avgHR: Int?
    var hrDriftPct: Double?
    var rpe: Int?
    var source: String = "manual"
    init() {}
}

@Model final class Benchmark {
    var date: Date = Date()
    var name: String = ""
    var value: String = ""
    var underFatigue: String?
    init() {}
}
