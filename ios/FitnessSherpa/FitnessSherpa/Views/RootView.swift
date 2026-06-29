//  RootView.swift
//  Fitness Sherpa
//
//  The app shell: a four-tab TabView over a shared AppModel, wrapped in a global hamburger menu
//  (Settings + App Info) that slides in from the left. Each tab's nav bar shows the global menu
//  button (left) and a persistent "data updated" indicator (center) instead of a title.

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var model = AppModel()

    var body: some View {
        Group {
            if model.settings.onboarded {
                shell
            } else {
                OnboardingView(model: model)
            }
        }
        .tint(Palette.mint)
        .task {
            await model.bootstrapCloud()          // pull durable settings first (cloud wins if it has data)
            if model.settings.onboarded {         // a fresh athlete refreshes at the end of onboarding instead
                await model.refresh(context: context)
            }
        }
    }

    private var shell: some View {
        GeometryReader { geo in
            let menuWidth = min(300, geo.size.width * 0.82)
            HStack(spacing: 0) {
                GlobalMenu(model: model)
                    .frame(width: menuWidth, height: geo.size.height)
                tabs
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay {
                        if model.showingMenu {
                            Color.black.opacity(0.3).contentShape(Rectangle())
                                .onTapGesture { model.showingMenu = false }
                        }
                    }
            }
            .frame(width: menuWidth + geo.size.width, alignment: .leading)
            .offset(x: model.showingMenu ? 0 : -menuWidth)
            .animation(.easeInOut(duration: 0.28), value: model.showingMenu)
        }
    }

    private var tabs: some View {
        TabView {
            TodayView(model: model)
                .tabItem { Label("Today", systemImage: "house.fill") }
            AthleteView(model: model)
                .tabItem { Label("Athlete", systemImage: "figure.run") }
            PlanView(model: model)
                .tabItem { Label("Plan", systemImage: "dumbbell.fill") }
            CoachView(model: model)
                .tabItem { Label("AI Coach", systemImage: "sparkles") }
        }
    }
}

/// Global left-side menu — app-level destinations (Settings, App Info). Grows over time.
struct GlobalMenu: View {
    let model: AppModel
    @State private var showingSettings = false
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fitness Sherpa")
                .font(.title3.bold()).foregroundStyle(Palette.text)
                .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 14)
            Rectangle().fill(Palette.surfaceLine).frame(height: 1)

            List {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape").foregroundStyle(Palette.text)
                }
                .listRowBackground(Palette.bg)
                Button { showingInfo = true } label: {
                    Label("App info", systemImage: "info.circle").foregroundStyle(Palette.text)
                }
                .listRowBackground(Palette.bg)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)

            Spacer()
            Text("Fitness Sherpa · prototype")
                .font(.caption2).foregroundStyle(Palette.textFaint)
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $showingInfo) { AppInfoView() }
    }
}

struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("App", value: "Fitness Sherpa")
                LabeledContent("Focus", value: "HYROX readiness")
                LabeledContent("Build", value: "v0 · prototype")
                Section("How your data is handled") {
                    Text("Reads Apple Health (HRV, resting HR, sleep, workouts). Your edits and manual entries are stored locally and are never overwritten by HealthKit imports.")
                        .font(.footnote)
                }
            }
            .navigationTitle("App info").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
