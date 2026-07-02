//  LiftMaxesEditView.swift
//  Ravns
//
//  Enter/edit the athlete's barbell 1-rep maxes (deadlift, clean, jerk, back/front squat, bench).
//  Health can't track these, so they're athlete-entered; stored canonically in lb on UserSettings,
//  edited in the athlete's preferred weight unit.

import SwiftUI

struct LiftMaxesEditView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var unit: String { Units.weightUnit(model.settings) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Lift.allCases) { lift in
                        HStack {
                            Text(lift.label)
                            Spacer()
                            TextField("—", text: field(lift))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text(unit).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("1-rep max")
                } footer: {
                    Text("Entered in \(unit). Leave a field blank to clear it.")
                }
            }
            .navigationTitle("Lift maxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .onAppear(perform: seed)
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ lift: Lift) -> Binding<String> {
        Binding(get: { values[lift.rawValue] ?? "" },
                set: { values[lift.rawValue] = $0 })
    }

    private func seed() {
        for lift in Lift.allCases {
            if let lb = model.settings.liftMaxesLb[lift.rawValue] {
                values[lift.rawValue] = String(format: "%.0f", Units.weightValue(lb: lb, model.settings))
            }
        }
    }

    private func save() {
        for lift in Lift.allCases {
            let raw = (values[lift.rawValue] ?? "").trimmingCharacters(in: .whitespaces)
            if let v = Double(raw), v > 0 {
                model.settings.liftMaxesLb[lift.rawValue] = Units.lbFromDisplay(v, model.settings)
            } else {
                model.settings.liftMaxesLb[lift.rawValue] = nil
            }
        }
        model.saveSettings()
    }
}
