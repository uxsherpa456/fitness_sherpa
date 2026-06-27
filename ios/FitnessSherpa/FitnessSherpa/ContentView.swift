//
//  ContentView.swift
//  FitnessSherpa
//
//  Temporary placeholder. Replaced by the real TabView (Today · Athlete · Plan · AI Coach)
//  ported from ../../prototype/index.html — see SETUP.md "First real milestone".
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Fitness Sherpa")
                .font(.title.bold())
            Text("Scaffold wired. Engine, models, sync, and HealthKit auth are in the target.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
