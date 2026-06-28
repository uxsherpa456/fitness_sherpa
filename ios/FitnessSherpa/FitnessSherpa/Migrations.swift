//  Migrations.swift
//  Fitness Sherpa
//
//  Versioned schema + migration plan so the SwiftData store survives app updates instead of being
//  wiped on any change. Additive changes migrate lightweight automatically. For a breaking change
//  (e.g. reshaping a Codable composite like Provenance), add AppSchemaV2 and a MigrationStage here
//  instead of relying on the dev wipe-recovery in FitnessSherpaApp.

import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Goal.self, Baseline.self, DiagnosisRecord.self, Session.self, Benchmark.self,
         HealthSnapshot.self, TrainingSession.self, Conversation.self, ChatMessageRecord.self,
         PlannedWorkout.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }   // add stages here when bumping to V2
}
