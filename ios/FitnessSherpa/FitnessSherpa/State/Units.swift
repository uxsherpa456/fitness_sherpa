//  Units.swift
//  Ravns
//
//  Display + entry conversion for the athlete's unit preferences (lb/kg, mi/km). Data is stored
//  canonically (km, lb); these convert only at the UI edges.

import Foundation

enum Units {
    static func distanceUnit(_ s: UserSettings) -> String { s.distanceUnit == "mi" ? "mi" : "km" }
    static func weightUnit(_ s: UserSettings) -> String { s.weightUnit == "kg" ? "kg" : "lb" }

    /// "8.0 km" / "5.0 mi"
    static func displayDistance(km: Double?, _ s: UserSettings) -> String? {
        guard let km else { return nil }
        let v = s.distanceUnit == "mi" ? km * 0.621371 : km
        return String(format: "%.1f %@", v, distanceUnit(s))
    }
    /// "214 lb" / "97 kg"
    static func displayWeight(lb: Double?, _ s: UserSettings) -> String? {
        guard let lb else { return nil }
        let v = s.weightUnit == "kg" ? lb * 0.453592 : lb
        return String(format: "%.0f %@", v, weightUnit(s))
    }

    /// Canonical km → the preferred unit's numeric value (for edit fields).
    static func distanceValue(km: Double, _ s: UserSettings) -> Double {
        s.distanceUnit == "mi" ? km * 0.621371 : km
    }
    /// A value typed in the preferred unit → canonical km.
    static func kmFromDisplay(_ value: Double, _ s: UserSettings) -> Double {
        s.distanceUnit == "mi" ? value / 0.621371 : value
    }
}
