//
//  ContentView.swift
//  FitnessSherpa
//
//  First-milestone harness (SETUP.md §6): request HealthKit authorization, read recovery
//  metrics + last run, build a Baseline, run the DiagnosisEngine, and show the result.
//  This is a proof-of-pipeline screen — the real TabView replaces it next.
//

import SwiftUI
import SwiftData
import HealthKit

struct ContentView: View {
    /// Chip-timed 5k PR — manual for now (comes from a race, not HealthKit). Moves to onboarding later.
    static let manual5k = "24:31"

    @State private var status = "Tap to read Health…"
    @State private var reading: HealthData.Reading?
    @State private var diagnosis: Diagnosis?
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let r = reading {
                    Section("HealthKit") {
                        row("HRV (SDNN)", r.hrv.map { String(format: "%.0f ms", $0) })
                        row("Resting HR", r.restingHR.map { String(format: "%.0f bpm", $0) })
                        row("Bodyweight", r.bodyMassLb.map { String(format: "%.0f lb", $0) })
                        row("5k PR (manual)", Self.manual5k)
                        row("Last run", lastRunText(r))
                    }
                }

                if let d = diagnosis {
                    Section("Diagnosis") {
                        row("Profile", d.profile.title)
                        row("Limiter", d.limiter)
                        row("Focus", d.focus)
                        row("Marker", String(format: "x %.2f · y %.2f", d.markerX, d.markerY))
                        row("Evidence", d.evidence)
                    }
                }
            }
            .navigationTitle("Fitness Sherpa")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Read") { Task { await runMilestone() } }
                        .disabled(running)
                }
            }
        }
        .task { await runMilestone() }   // also run once on launch
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func lastRunText(_ r: HealthData.Reading) -> String? {
        guard let date = r.lastRunDate else { return nil }
        let when = date.formatted(.relative(presentation: .named))
        let km = r.lastRunKm.map { String(format: "%.2f km", $0) } ?? "—"
        let min = r.lastRunMinutes.map { String(format: "%.0f min", $0) } ?? "—"
        return "\(km), \(min) (\(when))"
    }

    private func runMilestone() async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            status = "Requesting authorization…"
            try await HealthData.requestAuthorization()

            status = "Reading Health…"
            let r = try await HealthData.readSnapshot()
            reading = r

            // Build a Baseline from real bodyweight + the chip-timed 5k PR (manual: it comes
            // from a race, not the watch). Both move to the Train logger / onboarding later.
            let baseline = Baseline(bodyweightLb: r.bodyMassLb,
                                    recent5kSeconds: DiagnosisEngine.parse5k(Self.manual5k),
                                    stationsHold: true)
            let dx = DiagnosisEngine.diagnose(baseline.asInput())
            diagnosis = dx

            status = HKHealthStore.isHealthDataAvailable()
                ? "Read OK — \(missingNote(r))"
                : "Health data not available on this device."

            // Console proof (SETUP §6: "print them").
            print("""
            ── Fitness Sherpa milestone ──
            HRV: \(r.hrv.map { String(format: "%.0f ms", $0) } ?? "nil")
            Resting HR: \(r.restingHR.map { String(format: "%.0f bpm", $0) } ?? "nil")
            Bodyweight: \(r.bodyMassLb.map { String(format: "%.0f lb", $0) } ?? "nil")
            Last run: \(lastRunText(r) ?? "none")
            → Profile: \(dx.profile.title)
            → Limiter: \(dx.limiter)
            → Marker: x \(String(format: "%.2f", dx.markerX)) y \(String(format: "%.2f", dx.markerY))
            → Evidence: \(dx.evidence)
            ──────────────────────────────
            """)
        } catch {
            status = "Error: \(error.localizedDescription)"
            print("Milestone error: \(error)")
        }
    }

    /// Flags which metrics came back empty (no data yet, or permission withheld).
    private func missingNote(_ r: HealthData.Reading) -> String {
        var missing: [String] = []
        if r.hrv == nil { missing.append("HRV") }
        if r.restingHR == nil { missing.append("resting HR") }
        if r.bodyMassLb == nil { missing.append("bodyweight") }
        if r.lastRunDate == nil { missing.append("runs") }
        return missing.isEmpty ? "all metrics present." : "missing: \(missing.joined(separator: ", "))."
    }
}

#Preview {
    ContentView()
}
