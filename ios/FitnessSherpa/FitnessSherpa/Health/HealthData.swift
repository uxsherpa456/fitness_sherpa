//  HealthData.swift
//  Ravns
//
//  HealthKit authorization layer. The app is read-only from HealthKit — manual entries
//  live in SwiftData, not HealthKit. See DATA_MAP.md §6 for the metric set and rationale.

import HealthKit

enum HealthData {
    static let store = HKHealthStore()

    /// Everything the app reads — used for the authorization request.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
            .distanceWalkingRunning, .runningSpeed, .runningPower,
            .activeEnergyBurned, .basalEnergyBurned,
            .bodyMass, .bodyFatPercentage, .height,
            .stepCount, .respiratoryRate,
            .appleSleepingWristTemperature, .oxygenSaturation
        ]
        for id in quantities {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
}
