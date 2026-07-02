//
//  RavnsApp.swift
//  Ravns
//
//  Created by Ryan Lee on 6/27/26.
//

import SwiftUI
import SwiftData

@main
struct RavnsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: AppSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // One-time clean recreate on a schema bump. Our VersionedSchemas reference LIVE model types,
        // so adding a field (e.g. PlannedWorkout.directions) retroactively changes older versions and
        // can make SwiftData TRAP (uncatchably) while migrating a pre-existing store. Wiping before the
        // container is built sidesteps the migration entirely. Bump `marker` on any schema change; local
        // data self-heals (workouts re-import from Health, plan re-seeds, settings/goals are UserDefaults
        // + cloud). Only fires once per marker, so normal launches keep their data.
        let markerKey = "storeSchemaMarker", marker = "v4-directions"
        if UserDefaults.standard.string(forKey: markerKey) != marker {
            Self.wipeStore(config.url)
            UserDefaults.standard.set(marker, forKey: markerKey)
        }

        do {
            return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
            // V3 drops orphaned Goal/Session/Benchmark via a lightweight stage (no data loss).
        } catch {
            // Last-resort recovery only: a true migration failure (not handled by the plan) wipes the
            // dev store and recreates it. Real breaking changes should add an AppSchemaV2 stage instead.
            print("ModelContainer migration failed, recreating store: \(error)")
            Self.wipeStore(config.url)
            if let retry = try? ModelContainer(for: schema, configurations: [config]) { return retry }
            // Last resort: in-memory so the app still launches.
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }()

    /// Remove the SQLite store + its -wal/-shm sidecars so the next container opens a clean store.
    static func wipeStore(_ url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent(), name = url.lastPathComponent
        for path in [url, dir.appendingPathComponent(name + "-wal"), dir.appendingPathComponent(name + "-shm")] {
            try? fm.removeItem(at: path)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
