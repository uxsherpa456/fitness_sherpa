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
    @State private var selectedTab = 0
    @State private var tour = false
    @State private var tourStep = 0

    static let pendingTourKey = "pendingTour"

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
            if model.settings.onboarded || DemoSeed.isDemo {   // demo seeds + lands populated; fresh athletes onboard
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
        .overlay {
            if tour { TabTourOverlay(step: tourStep, onSkip: endTour, onNext: advanceTour) }
        }
        .onAppear {   // start the welcome tour once, right after a fresh onboarding
            if UserDefaults.standard.bool(forKey: Self.pendingTourKey) {
                UserDefaults.standard.set(false, forKey: Self.pendingTourKey)
                model.showingMenu = false   // closed, so the tour overlay reads right
                selectedTab = 0; tourStep = 0; tour = true
            }
        }
    }

    private func advanceTour() {
        if tourStep < 3 { tourStep += 1; selectedTab = tourStep } else { endTour() }
    }
    private func endTour() { tour = false; selectedTab = 0 }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            TodayView(model: model)
                .tabItem { Label("Today", systemImage: "house.fill") }.tag(0)
            AthleteView(model: model)
                .tabItem { Label("Athlete", systemImage: "figure.run") }.tag(1)
            PlanView(model: model)
                .tabItem { Label("Plan", systemImage: "dumbbell.fill") }.tag(2)
            CoachView(model: model)
                .tabItem { Label("Coach", image: "coachRaven") }.tag(3)
        }
    }
}

/// Post-onboarding coach-marks — a dimmed overlay walking through the four tabs, with a card and a
/// pointer to the active tab. The tour drives `selectedTab` from RootView so each step shows its tab.
private struct TabTourOverlay: View {
    let step: Int
    let onSkip: () -> Void
    let onNext: () -> Void

    private let steps: [(title: String, body: String)] = [
        ("Today", "Your daily verdict — train hard or back off. Readiness, fuel, your last-workout read, and today's session at a glance."),
        ("Athlete", "Who you are right now — your diagnosis quadrant, training status, and Munin's memory: the metrics arcing toward race day. Re-run your baseline here anytime."),
        ("Plan", "Your plan to race day — base to taper, every session with real paces + station weights, shifting as your diagnosis changes."),
        ("Hugin", "Thought, made into a coach. Hugin already holds today's data — it cites your own numbers and won't reason off stale data."),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = steps[min(step, steps.count - 1)]
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.72).ignoresSafeArea()
                    .contentShape(Rectangle())

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(step + 1) / \(steps.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundStyle(Palette.mint)
                        Text(t.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                        Text(t.body).font(.footnote).foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Skip", action: onSkip)
                                .font(.subheadline).foregroundStyle(Palette.textFaint)
                            Spacer()
                            Button(step == steps.count - 1 ? "Got it" : "Next", action: onNext)
                                .font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 22).padding(.vertical, 9)
                                .background(Capsule().fill(Palette.mint))
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.mint).frame(width: 3).clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)

                    // pointer to the active tab (tabs are evenly spaced quarters)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 13)).foregroundStyle(Palette.surface)
                        .offset(x: w * (CGFloat(step) + 0.5) / 4 - w / 2)
                }
                .padding(.bottom, 56)
            }
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
            Text("Ravns")
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
            Text("Ravns · prototype")
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
                LabeledContent("App", value: "Ravns")
                LabeledContent("Focus", value: "HYROX readiness")
                LabeledContent("Build", value: "v0 · prototype")
                Section("How your data is handled") {
                    Text("Reads Apple Health (HRV, resting HR, sleep, workouts). Your edits and manual entries are stored locally and are never overwritten by HealthKit imports.")
                        .font(.footnote)
                }

                Section {
                    LabeledContent("Mode", value: model.inSandbox ? "Sandbox (new-user test)" : "Your data")
                    Button {
                        confirmReset = true
                    } label: { Label(model.inSandbox ? "Start over (clear sandbox)" : "Experience as a new user",
                                     systemImage: "person.crop.circle.badge.plus") }
                    if model.inSandbox {
                        Button {
                            working = true
                            Task { await model.restoreMyData(context: context); working = false; dismiss() }
                        } label: { Label("Restore my data", systemImage: "arrow.uturn.backward") }
                    }
                    if working { ProgressView() }
                } header: {
                    Text("Developer")
                } footer: {
                    Text(model.inSandbox
                         ? "You're on an isolated sandbox. Start over wipes it and runs onboarding fresh again. Your real settings + goals are safe in the cloud — restore returns you to them."
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
