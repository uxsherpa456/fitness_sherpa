//  RootView.swift
//  Fitness Sherpa
//
//  The app shell: a four-tab TabView (Today · Athlete · Plan · AI Coach) over a shared AppModel.
//  Reads Health once on launch; each tab observes the same model.

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var model = AppModel()

    var body: some View {
        TabView {
            TodayView(model: model)
                .tabItem { Label("Today", systemImage: "house.fill") }
            AthleteView(model: model)
                .tabItem { Label("Athlete", systemImage: "figure.run") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "dumbbell.fill") }
            CoachView(model: model)
                .tabItem { Label("AI Coach", systemImage: "sparkles") }
        }
        .tint(Palette.mint)
        .task { await model.refresh(context: context) }
    }
}
