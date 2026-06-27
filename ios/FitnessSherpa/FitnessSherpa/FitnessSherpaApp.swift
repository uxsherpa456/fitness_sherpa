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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
