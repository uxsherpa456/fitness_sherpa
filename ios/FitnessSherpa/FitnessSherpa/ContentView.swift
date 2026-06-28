//
//  ContentView.swift
//  FitnessSherpa
//
//  First-milestone harness (SETUP.md §6) + freshness (DATA_MAP.md §5): request HealthKit
//  authorization, read recovery metrics + last run (each stamped with sample age), build a
//  Baseline, run the DiagnosisEngine, and show the result. The real TabView replaces this next.
//

import SwiftUI
import SwiftData
import HealthKit

struct ContentView: View {
    /// Chip-timed 5k PR — manual for now (comes from a race, not HealthKit). Moves to onboarding later.
    static let manual5k = "24:31"

    @Environment(\.modelContext) private var context
    @Query(sort: \DiagnosisRecord.date, order: .reverse) private var diagnoses: [DiagnosisRecord]
    @Query(sort: \HealthSnapshot.capturedAt, order: .reverse) private var snapshots: [HealthSnapshot]

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
                        .foregroundStyle(reading?.readinessFresh == false ? .orange : .secondary)
                }

                if let r = reading {
                    Section("HealthKit") {
                        metricRow(.hrv, unit: "ms", in: r)
                        metricRow(.restingHR, unit: "bpm", in: r)
                        metricRow(.bodyweight, unit: "lb", in: r)
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

                Section("Saved (SwiftData)") {
                    row("Snapshots", "\(snapshots.count)")
                    row("Diagnoses", "\(diagnoses.count)")
                    if let last = diagnoses.first {
                        row("Latest", "\(last.profile.title) · \(last.date.formatted(.relative(presentation: .named)))")
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

    // MARK: - Rows

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    /// A freshness-aware metric row: value + "Xh ago", flagged orange when stale or missing.
    @ViewBuilder private func metricRow(_ m: HealthData.Reading.Metric, unit: String, in r: HealthData.Reading) -> some View {
        let stale = r.isStale(m)
        HStack(alignment: .firstTextBaseline) {
            Text(m.rawValue).foregroundStyle(.secondary)
            Spacer()
            if let s = r.sample(for: m) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.0f %@", s.value, unit))
                    Text(ageText(s.date, asOf: r.queriedAt) + (stale ? " · stale" : ""))
                        .font(.caption2)
                        .foregroundStyle(stale ? .orange : .secondary)
                }
            } else {
                Text("no data").foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Formatting

    private func ageText(_ date: Date, asOf: Date) -> String {
        let s = max(0, asOf.timeIntervalSince(date))
        switch s {
        case ..<90:        return "just now"
        case ..<3600:      return "\(Int(s / 60))m ago"
        case ..<86400:     return "\(Int(s / 3600))h ago"
        default:           return "\(Int(s / 86400))d ago"
        }
    }

    private func lastRunText(_ r: HealthData.Reading) -> String? {
        guard let date = r.lastRunDate else { return nil }
        let when = date.formatted(.relative(presentation: .named))
        let km = r.lastRunKm.map { String(format: "%.2f km", $0) } ?? "—"
        let min = r.lastRunMinutes.map { String(format: "%.0f min", $0) } ?? "—"
        return "\(km), \(min) (\(when))"
    }

    // MARK: - Milestone

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
            let baseline = Baseline(bodyweightLb: r.bodyMass?.value,
                                    recent5kSeconds: DiagnosisEngine.parse5k(Self.manual5k),
                                    stationsHold: true)
            let dx = DiagnosisEngine.diagnose(baseline.asInput())
            diagnosis = dx

            // Persist to the local store (deduped) so trends + re-diagnosis have history.
            persist(reading: r, baseline: baseline, diagnosis: dx)

            // Freshness gate: readiness is only trustworthy when recovery metrics are current.
            if !HKHealthStore.isHealthDataAvailable() {
                status = "Health data not available on this device."
            } else if r.readinessFresh {
                status = "Recovery data fresh ✓ — read \(ageText(r.queriedAt, asOf: Date())) ago."
            } else {
                status = "Readiness not trusted — stale/missing: \(r.staleMetrics.joined(separator: ", "))."
            }

            // Console proof (SETUP §6: "print them") + freshness stamps.
            print("""
            ── Fitness Sherpa milestone ──
            HRV: \(stampText(r, .hrv, "ms"))
            Resting HR: \(stampText(r, .restingHR, "bpm"))
            Bodyweight: \(stampText(r, .bodyweight, "lb"))
            Last run: \(lastRunText(r) ?? "none")
            Readiness fresh: \(r.readinessFresh)  stale/missing: \(r.staleMetrics)
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

    // MARK: - Persistence

    /// Save a snapshot + diagnosis (+ baseline), skipping inserts when nothing meaningful changed
    /// so repeated launches don't pile up duplicate rows.
    private func persist(reading r: HealthData.Reading, baseline: Baseline, diagnosis dx: Diagnosis) {
        // HealthSnapshot — skip if the latest stored one has the same recovery values.
        let lastSnap = snapshots.first
        if lastSnap?.hrv != r.hrv?.value || lastSnap?.restingHR != r.restingHR?.value {
            context.insert(HealthSnapshot(
                capturedAt: r.queriedAt,
                hrv: r.hrv?.value,
                restingHR: r.restingHR?.value,
                staleMetrics: r.staleMetrics
            ))
        }

        // DiagnosisRecord — skip if the latest stored one is the same placement + evidence.
        let lastDx = diagnoses.first
        if lastDx?.profileRaw != dx.profile.rawValue || lastDx?.evidence != dx.evidence {
            context.insert(DiagnosisRecord(dx))
            context.insert(baseline)   // keep the input that produced this diagnosis
        }

        do { try context.save() }
        catch { print("Persist error: \(error)") }
    }

    private func stampText(_ r: HealthData.Reading, _ m: HealthData.Reading.Metric, _ unit: String) -> String {
        guard let s = r.sample(for: m) else { return "nil" }
        return String(format: "%.0f %@ (%@%@)", s.value, unit,
                      ageText(s.date, asOf: r.queriedAt), r.isStale(m) ? ", stale" : "")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Goal.self, Baseline.self, DiagnosisRecord.self,
                              Session.self, Benchmark.self, HealthSnapshot.self], inMemory: true)
}
