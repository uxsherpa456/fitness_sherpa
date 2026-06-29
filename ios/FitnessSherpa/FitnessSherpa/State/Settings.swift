//  Settings.swift
//  Fitness Sherpa
//
//  User-editable profile / race / units settings, ported from the prototype's Settings screen.
//  Persisted to UserDefaults for now; mirrors StateSync.AppSettings so it can sync to the cloud
//  `app_state` row later. Feeds the coach context (division, age, race) so advice is tailored.

import Foundation

struct UserSettings: Codable, Equatable {
    var location = "Washington, DC"
    var format = "singles"        // singles | doubles | relay | elite15
    var gender = "mens"           // mens | womens | mixed
    var tier = "open"             // open | pro   (singles only)
    var age = 37
    var goalTime = "1:10:00"      // H:MM:SS
    var raceDate = "2026-09-04"   // yyyy-MM-dd
    var raceLocation = "Washington DC"
    var weightUnit = "lb"         // lb | kg
    var distanceUnit = "mi"       // mi | km
    var recent5k = "24:31"        // chip-timed 5k PR (baseline input)
    var bodyweightLb = 0.0        // manual / confirmed bodyweight (lb); 0 = unset → use Apple Health
    var bodyFatPct = 0.0          // manual body fat %; 0 = unset → use Apple Health
    var strengthAxis = 0.78       // 0…1 strength + station capacity, averaged from onboarding (the Health-blind axis)
    var stationsHold = true       // legacy boolean snapshot, kept in sync with strengthAxis for the coach context
    var mobilityScore = -1.0      // 0…1 squat-depth / ankle / posterior-chain range; <0 = not assessed
    var onboarded = false

    /// Advisory mobility flag (nil until assessed in onboarding). Does not affect the quadrant/score.
    var mobilityFlag: MobilityFlag? { mobilityScore >= 0 ? Mobility.flag(score: mobilityScore) : nil }

    static let key = "userSettings.v1"

    /// Tolerant decode — every field is optional with a default, so adding or removing a field never
    /// wipes a saved profile. `strengthAxis` back-fills from the legacy `stationsHold` boolean.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: k)) ?? def }
        location      = v(.location, "Washington, DC")
        format        = v(.format, "singles")
        gender        = v(.gender, "mens")
        tier          = v(.tier, "open")
        age           = v(.age, 37)
        goalTime      = v(.goalTime, "1:10:00")
        raceDate      = v(.raceDate, "2026-09-04")
        raceLocation  = v(.raceLocation, "Washington DC")
        weightUnit    = v(.weightUnit, "lb")
        distanceUnit  = v(.distanceUnit, "mi")
        recent5k      = v(.recent5k, "24:31")
        bodyweightLb  = v(.bodyweightLb, 0.0)
        bodyFatPct    = v(.bodyFatPct, 0.0)
        stationsHold  = v(.stationsHold, true)
        strengthAxis  = v(.strengthAxis, stationsHold ? 0.78 : 0.30)
        mobilityScore = v(.mobilityScore, -1.0)
        onboarded     = v(.onboarded, false)
    }

    init() {}

    static func load() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(UserSettings.self, from: data) else { return UserSettings() }
        return s
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: Cloud mapping (StateSync.AppState — the same row the prototype writes)

    func toAppSettings() -> AppSettings {
        AppSettings(location: location, goalTime: goalTime, raceDate: raceDate, raceLoc: raceLocation,
                    weightUnit: weightUnit, distUnit: distanceUnit, format: format, gender: gender,
                    tier: tier, age: age,
                    weightLb: bodyweightLb > 0 ? bodyweightLb : nil,
                    bodyFatPct: bodyFatPct > 0 ? bodyFatPct : nil)
    }
    func toProfile() -> ProfileData {
        ProfileData(format: format, gender: gender, tier: tier, age: age)
    }
    mutating func apply(_ s: AppSettings) {
        if let v = s.location { location = v }
        if let v = s.goalTime { goalTime = v }
        if let v = s.raceDate { raceDate = v }
        if let v = s.raceLoc { raceLocation = v }
        if let v = s.weightUnit { weightUnit = v }
        if let v = s.distUnit { distanceUnit = v }
        if let v = s.format { format = v }
        if let v = s.gender { gender = v }
        if let v = s.tier { tier = v }
        if let v = s.age { age = v }
        if let v = s.weightLb { bodyweightLb = v }
        if let v = s.bodyFatPct { bodyFatPct = v }
    }

    /// Goal finish as H:MM — seconds dropped (HYROX targets are minute-level). Tolerates a stored
    /// "H:MM:SS" from before seconds were removed.
    var goalTimeDisplay: String {
        let p = goalTime.split(separator: ":")
        return p.count >= 2 ? "\(p[0]):\(p[1])" : goalTime
    }

    /// Days from today until race day (nil if the date can't be parsed).
    var daysToRace: Int? {
        guard let d = DateFormatters.ymd.date(from: raceDate) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: d)).day
    }
}
