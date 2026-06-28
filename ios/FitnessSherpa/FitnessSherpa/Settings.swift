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

    static let key = "userSettings.v1"

    static func load() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(UserSettings.self, from: data) else { return UserSettings() }
        return s
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Days from today until race day (nil if the date can't be parsed).
    var daysToRace: Int? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let d = f.date(from: raceDate) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: d)).day
    }
}
