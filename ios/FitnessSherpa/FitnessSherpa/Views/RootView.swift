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
            await model.bootstrapCloud(context: context)   // pull durable settings + history first (cloud wins)
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
        .sheet(isPresented: $showingInfo) { AppInfoView(model: model) }
    }
}

struct AppInfoView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmReset = false
    @State private var working = false

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

                Section {
                    if model.inSandbox {
                        LabeledContent("Mode", value: "Sandbox (new-user test)")
                        Button {
                            working = true
                            Task { await model.restoreMyData(context: context); working = false; dismiss() }
                        } label: { Label("Restore my data", systemImage: "arrow.uturn.backward") }
                    } else {
                        LabeledContent("Mode", value: "Your data")
                        Button {
                            confirmReset = true
                        } label: { Label("Experience as a new user", systemImage: "person.crop.circle.badge.plus") }
                    }
                    if working { ProgressView() }
                } header: {
                    Text("Developer")
                } footer: {
                    Text(model.inSandbox
                         ? "You're on an isolated sandbox. Your real settings + goals are safe in the cloud — restore returns you to them."
                         : "Backs your settings + goals up to the cloud, then resets to a fresh onboarding on an isolated sandbox. Reversible. Local workout/plan/readiness history is cleared (workouts re-import from Apple Health).")
                }
            }
            .navigationTitle("App info").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Start a fresh new-user experience?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Back up & start fresh", role: .destructive) {
                    working = true
                    Task { await model.resetToFreshUser(context: context); working = false; dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your settings + goals are saved to the cloud first and can be restored. Local history is cleared.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
