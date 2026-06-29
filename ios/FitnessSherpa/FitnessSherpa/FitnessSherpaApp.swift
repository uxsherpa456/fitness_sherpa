//
//  FitnessSherpaApp.swift
//  FitnessSherpa
//
//  Created by Ryan Lee on 6/27/26.
//

import SwiftUI
import SwiftData

@main
struct FitnessSherpaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: AppSchemaV3.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
            // V3 drops orphaned Goal/Session/Benchmark via a lightweight stage (no data loss).
        } catch {
            // Last-resort recovery only: a true migration failure (not handled by the plan) wipes the
            // dev store and recreates it. Real breaking changes should add an AppSchemaV2 stage instead.
            print("ModelContainer migration failed, recreating store: \(error)")
            let fm = FileManager.default
            let url = config.url
            let dir = url.deletingLastPathComponent()
            let name = url.lastPathComponent
            for path in [url,
                         dir.appendingPathComponent(name + "-wal"),
                         dir.appendingPathComponent(name + "-shm")] {
                try? fm.removeItem(at: path)
            }
            if let retry = try? ModelContainer(for: schema, configurations: [config]) { return retry }
            // Last resort: in-memory so the app still launches.
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
