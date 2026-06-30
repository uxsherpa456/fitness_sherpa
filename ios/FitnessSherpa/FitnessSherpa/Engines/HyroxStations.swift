//  HyroxStations.swift
//  Ravns
//
//  Official HYROX implement weights by division (gender × Open/Pro), in kg as the sport specifies.
//  Lets the plan prescribe the exact loads the athlete will race — division-scaled station work,
//  not a generic "sled push."

import Foundation

struct StationWeights {
    let sledKg: Int        // sled push (total, incl. sled)
    let farmersKg: Int     // farmers carry, per hand
    let sandbagKg: Int     // sandbag lunges
    let wallBallKg: Int    // wall ball
}

enum HyroxStations {
    // Keyed the same way as StrengthStandards ("men_open" … "women_pro").
    private static let grid: [String: StationWeights] = [
        "men_open":   StationWeights(sledKg: 152, farmersKg: 24, sandbagKg: 20, wallBallKg: 6),
        "men_pro":    StationWeights(sledKg: 202, farmersKg: 32, sandbagKg: 30, wallBallKg: 9),
        "women_open": StationWeights(sledKg: 102, farmersKg: 16, sandbagKg: 10, wallBallKg: 4),
        "women_pro":  StationWeights(sledKg: 152, farmersKg: 24, sandbagKg: 20, wallBallKg: 6),
    ]

    static func weights(for s: UserSettings) -> StationWeights {
        grid[StrengthStandards.key(for: s)] ?? grid["men_open"]!
    }
}
