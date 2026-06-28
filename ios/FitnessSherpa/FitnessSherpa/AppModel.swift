//  AppModel.swift
//  Fitness Sherpa
//
//  Shared observable state: reads HealthKit, runs the DiagnosisEngine, persists to SwiftData,
//  and exposes the current reading + diagnosis to every tab. Replaces the per-view logic that
//  lived in the old ContentView milestone harness.

import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppModel {
    /// Chip-timed 5k PR — manual for now (a race result, not in HealthKit). Moves to onboarding later.
    static let manual5k = "24:31"

    var reading: HealthData.Reading?
    var diagnosis: Diagnosis?
    var status = "Reading Health…"
    var loading = false

    var readinessScore: Int? {
        Readiness.score(hrv: reading?.hrv?.value, restingHR: reading?.restingHR?.value)
    }

    /// Read Health, diagnose, persist (deduped). Safe to call repeatedly.
    func refresh(context: ModelContext) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            try await HealthData.requestAuthorization()
            let r = try await HealthData.readSnapshot()
            reading = r

            let baseline = Baseline(bodyweightLb: r.bodyMass?.value,
                                    recent5kSeconds: DiagnosisEngine.parse5k(Self.manual5k),
                                    stationsHold: true)
            let dx = DiagnosisEngine.diagnose(baseline.asInput())
            diagnosis = dx

            persist(reading: r, baseline: baseline, diagnosis: dx, context: context)

            status = r.readinessFresh
                ? "Recovery data fresh ✓"
                : "Readiness not trusted — stale/missing: \(r.staleMetrics.joined(separator: ", "))."
        } catch {
            status = "Error: \(error.localizedDescription)"
            print("AppModel.refresh error: \(error)")
        }
    }

    /// Save a snapshot + (on change) a diagnosis & its baseline, skipping unchanged dupes.
    private func persist(reading r: HealthData.Reading, baseline: Baseline,
                         diagnosis dx: Diagnosis, context: ModelContext) {
        var snapDesc = FetchDescriptor<HealthSnapshot>(sortBy: [.init(\.capturedAt, order: .reverse)])
        snapDesc.fetchLimit = 1
        let lastSnap = try? context.fetch(snapDesc).first
        if lastSnap?.hrv != r.hrv?.value || lastSnap?.restingHR != r.restingHR?.value {
            context.insert(HealthSnapshot(capturedAt: r.queriedAt,
                                          hrv: r.hrv?.value,
                                          restingHR: r.restingHR?.value,
                                          staleMetrics: r.staleMetrics))
        }

        var dxDesc = FetchDescriptor<DiagnosisRecord>(sortBy: [.init(\.date, order: .reverse)])
        dxDesc.fetchLimit = 1
        let lastDx = try? context.fetch(dxDesc).first
        if lastDx?.profileRaw != dx.profile.rawValue || lastDx?.evidence != dx.evidence {
            context.insert(DiagnosisRecord(dx))
            context.insert(baseline)
        }

        do { try context.save() } catch { print("Persist error: \(error)") }
    }
}
