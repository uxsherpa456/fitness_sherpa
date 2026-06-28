//  HealthRead.swift
//  Fitness Sherpa
//
//  Minimal HealthKit read helpers for the first milestone (SETUP.md §6): pull the latest
//  recovery metrics + most recent run so the DiagnosisEngine can reason over real numbers.
//  Freshness-stamped queries and the full metric set come later — this proves the pipeline.

import HealthKit

extension HealthData {

    /// A one-shot read of the metrics the first milestone needs.
    struct Reading {
        var hrv: Double?            // HRV SDNN, ms
        var restingHR: Double?      // bpm
        var bodyMassLb: Double?     // lb
        var lastRunDate: Date?
        var lastRunKm: Double?
        var lastRunMinutes: Double?
    }

    /// Latest single sample for a quantity type, expressed in `unit`. `nil` if none/unauthorized.
    static func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Most recent running workout, or `nil`.
    static func latestRun() async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForWorkouts(with: .running)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
    }

    /// Read the milestone metrics in one call.
    static func readSnapshot() async throws -> Reading {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hrv  = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let rhr  = latestQuantity(.restingHeartRate, unit: bpm)
        async let mass = latestQuantity(.bodyMass, unit: .pound())

        let run = try await latestRun()
        var km: Double? = nil
        if let run, let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
           let dist = run.statistics(for: distType)?.sumQuantity() {
            km = dist.doubleValue(for: .meterUnit(with: .kilo))
        }

        return Reading(
            hrv: try await hrv,
            restingHR: try await rhr,
            bodyMassLb: try await mass,
            lastRunDate: run?.endDate,
            lastRunKm: km,
            lastRunMinutes: run.map { $0.duration / 60 }
        )
    }
}
