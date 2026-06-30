//  GoalEditView.swift
//  Ravns
//
//  Edit a focus-metric goal's current + target. Data-backed currents (weight, body fat) refresh
//  from HealthKit; the target is yours to set. Saves locally and mirrors to the cloud app_state row.

import SwiftUI

struct GoalEditView: View {
    let goal: GoalArc
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentText: String
    @State private var goalText: String

    init(goal: GoalArc, model: AppModel) {
        self.goal = goal
        self.model = model
        _currentText = State(initialValue: goal.current?.display ?? "")
        _goalText = State(initialValue: goal.goal?.display ?? "")
    }

    private var dataBacked: Bool { goal.key == "weight" || goal.key == "bodyfat" }

    var body: some View {
        NavigationStack {
            Form {
                Section(goal.label ?? goal.key) {
                    LabeledContent("Current") {
                        TextField(goal.isTime ? "mm:ss" : "value", text: $currentText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(goal.isTime ? .numbersAndPunctuation : .decimalPad)
                            .disabled(dataBacked)
                    }
                    LabeledContent("Target") {
                        TextField(goal.isTime ? "mm:ss" : "value", text: $goalText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(goal.isTime ? .numbersAndPunctuation : .decimalPad)
                    }
                }
                if dataBacked {
                    Section {
                        Text("Current updates automatically from Apple Health.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit goal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func value(_ s: String) -> GoalValue {
        goal.isTime ? .text(s) : .number(Double(s) ?? 0)
    }

    private func save() {
        guard let i = model.goals.firstIndex(where: { $0.key == goal.key }) else { dismiss(); return }
        if !dataBacked { model.goals[i].current = value(currentText) }
        model.goals[i].goal = value(goalText)
        model.saveGoals()
        model.pushToCloud()
        dismiss()
    }
}
