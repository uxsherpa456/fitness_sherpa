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
        let schema = Schema([
            Goal.self, Baseline.self, DiagnosisRecord.self,
            Session.self, Benchmark.self, HealthSnapshot.self,
            TrainingSession.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Dev recovery: if the on-disk store can't migrate to the current schema, wipe it and
            // recreate. Data re-imports from HealthKit; manual entries are dev-only at this stage.
            // (Replace with a real VersionedSchema + MigrationPlan before shipping persistent data.)
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
