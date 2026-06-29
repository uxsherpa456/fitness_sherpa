//  SettingsView.swift
//  Fitness Sherpa
//
//  Settings sheet ported from the prototype: profile (location, race format/division/weights, age),
//  the race (goal time, date, location), and units. Saves to AppModel.settings (UserDefaults).

import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var s: UserSettings
    @State private var goalH: Int
    @State private var goalM: Int
    @State private var goalS: Int
    @State private var raceDate: Date

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        _s = State(initialValue: settings)
        let parts = settings.goalTime.split(separator: ":").map { Int($0) ?? 0 }
        _goalH = State(initialValue: parts.count > 0 ? parts[0] : 1)
        _goalM = State(initialValue: parts.count > 1 ? parts[1] : 10)
        _goalS = State(initialValue: parts.count > 2 ? parts[2] : 0)
        _raceDate = State(initialValue: DateFormatters.ymd.date(from: settings.raceDate) ?? Date())
    }

    private var genderOptions: [(String, String)] {
        switch s.format {
        case "doubles", "relay": return [("mens", "Men's"), ("womens", "Women's"), ("mixed", "Mixed")]
        default: return [("mens", "Men's"), ("womens", "Women's")]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Home location") {
                        TextField("e.g. Washington, DC", text: $s.location).multilineTextAlignment(.trailing)
                    }
                    Picker("Format", selection: $s.format) {
                        Text("Singles").tag("singles")
                        Text("Doubles").tag("doubles")
                        Text("Relay").tag("relay")
                        Text("Elite 15").tag("elite15")
                    }
                    Picker("Division", selection: $s.gender) {
                        ForEach(genderOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    if s.format == "singles" {
                        Picker("Weights", selection: $s.tier) {
                            Text("Open").tag("open")
                            Text("Pro").tag("pro")
                        }
                    }
                    Stepper("Age: \(s.age)", value: $s.age, in: 14...90)
                }

                Section("The race") {
                    HStack {
                        Text("Goal finish time"); Spacer()
                        Picker("H", selection: $goalH) { ForEach(0...3, id: \.self) { Text("\($0)").tag($0) } }
                            .labelsHidden().frame(width: 50)
                        Text("h").foregroundStyle(.secondary)
                        Picker("M", selection: $goalM) { ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                            .labelsHidden().frame(width: 56)
                        Text("m").foregroundStyle(.secondary)
                        Picker("S", selection: $goalS) { ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                            .labelsHidden().frame(width: 56)
                        Text("s").foregroundStyle(.secondary)
                    }
                    DatePicker("Race date", selection: $raceDate, displayedComponents: [.date])
                    LabeledContent("Race location") {
                        TextField("City", text: $s.raceLocation).multilineTextAlignment(.trailing)
                    }
                    if let days = s.daysToRace {
                        LabeledContent("Days out", value: "\(days)")
                    }
                }

                Section("Units") {
                    Picker("Weight", selection: $s.weightUnit) {
                        Text("LB").tag("lb"); Text("KG").tag("kg")
                    }.pickerStyle(.segmented)
                    Picker("Distance", selection: $s.distanceUnit) {
                        Text("MI").tag("mi"); Text("KM").tag("km")
                    }.pickerStyle(.segmented)
                }

                Section {
                    Text("Fitness Sherpa").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        s.goalTime = "\(goalH):\(String(format: "%02d", goalM)):\(String(format: "%02d", goalS))"
        s.raceDate = DateFormatters.ymd.string(from: raceDate)
        // Division must be valid for the chosen format (mixed only for doubles/relay).
        if !genderOptions.contains(where: { $0.0 == s.gender }) { s.gender = "mens" }
        model.settings = s
        model.saveSettings()
        model.pushToCloud()
        dismiss()
    }
}
