//  Migrations.swift
//  Ravns
//
//  Versioned schema + migration plan so the SwiftData store survives app updates instead of being
//  wiped on any change. Additive changes migrate lightweight automatically. For a breaking change
//  (e.g. reshaping a Codable composite like Provenance), add AppSchemaV2 and a MigrationStage here
//  instead of relying on the dev wipe-recovery in RavnsApp.

import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Goal.self, Baseline.self, DiagnosisRecord.self, Session.self, Benchmark.self,
         HealthSnapshot.self, TrainingSession.self, Conversation.self, ChatMessageRecord.self,
         PlannedWorkout.self]
    }
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        AppSchemaV1.models + [DailyReadiness.self]      // additive: daily readiness log
    }
}

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        // drops the orphaned Goal / Session / Benchmark (now in LegacySchema, excluded here)
        [Baseline.self, DiagnosisRecord.self, HealthSnapshot.self, TrainingSession.self,
         Conversation.self, ChatMessageRecord.self, PlannedWorkout.self, DailyReadiness.self]
    }
}

enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        AppSchemaV3.models      // additive: PlannedWorkout.directions (per-session coaching directions)
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self, AppSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
         .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),   // drops orphan tables
         .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self)]   // adds directions field
    }
}
