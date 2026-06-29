//  Trends.swift
//  Fitness Sherpa
//
//  Time-series points for the Athlete trend charts. HRV / sleep / form / acute:chronic are
//  reconstructed from Apple Health history (no logging needed); readiness comes from a daily log.

import Foundation

struct TrendPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct FormPoint: Identifiable {
    let date: Date
    let ctl: Double      // chronic (fitness)
    let atl: Double      // acute (fatigue)
    let form: Double     // ctl - atl
    let ratio: Double    // atl / ctl  (acute:chronic)
    var id: Date { date }
}

struct SleepNight: Identifiable {
    let date: Date       // the morning you woke
    let asleep: Double   // hours
    let deep: Double
    let rem: Double
    var id: Date { date }
}

/// Everything the Athlete charts need.
struct AthleteTrends {
    var hrv: [TrendPoint] = []
    var sleep: [SleepNight] = []
    var form: [FormPoint] = []
    var readiness: [TrendPoint] = []
}
