//  DailyReadiness.swift
//  Fitness Sherpa
//
//  One row per day, logged on refresh — the readiness score over time (the one trend that can't be
//  reconstructed from Apple Health, because it includes the subjective "how you feel" input).

import Foundation
import SwiftData

@Model
final class DailyReadiness {
    var day: Date = Date()       // start of day
    var score: Int = 0
    var hrv: Double = 0
    var ctl: Double = 0
    var atl: Double = 0
    var form: Double = 0
    var acr: Double = 1

    init(day: Date, score: Int, hrv: Double, ctl: Double, atl: Double, form: Double, acr: Double) {
        self.day = day; self.score = score; self.hrv = hrv
        self.ctl = ctl; self.atl = atl; self.form = form; self.acr = acr
    }
}
