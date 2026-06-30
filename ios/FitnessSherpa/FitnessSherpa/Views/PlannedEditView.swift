//  PlannedEditView.swift
//  Ravns
//
//  Edit a planned session. Any athlete edit re-stamps the source as `athlete` so the coach knows
//  it was hand-set; the coach can still propose changes (which arrive tagged `coach`).

import SwiftUI
import SwiftData

struct PlannedEditView: View {
    let plan: PlannedWorkout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: SessionCategory
    @State private var date: Date
    @State private var type: String
    @State private var name: String
    @State private var meta: String
    @State private var intent: PlanIntent
    @State private var targetZone: String
    @State private var stations: String
    @State private var why: String
    @State private var completed: Bool

    init(plan: PlannedWorkout) {
        self.plan = plan
        _category = State(initialValue: plan.cat)
        _date = State(initialValue: plan.date)
        _type = State(initialValue: plan.type)
        _name = State(initialValue: plan.name)
        _meta = State(initialValue: plan.meta)
        _intent = State(initialValue: plan.intent)
        _targetZone = State(initialValue: plan.targetZone ?? "")
        _stations = State(initialValue: plan.stations ?? "")
        _why = State(initialValue: plan.why ?? "")
        _completed = State(initialValue: plan.completed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if plan.source == .coach {
                        Label("Proposed by your AI coach", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Completed", isOn: $completed)
                }
                Section("Session") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    Picker("Type", selection: $category) {
                        ForEach(SessionCategory.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Intent", selection: $intent) {
                        ForEach(PlanIntent.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Label") { TextField("TEMPO RUN", text: $type).multilineTextAlignment(.trailing) }
                    LabeledContent("Name") { TextField("Tempo run + strides", text: $name).multilineTextAlignment(.trailing) }
                    LabeledContent("Detail") { TextField("8 km tempo · 40 min", text: $meta).multilineTextAlignment(.trailing) }
                    LabeledContent("Target zone") { TextField("Z2 / threshold", text: $targetZone).multilineTextAlignment(.trailing) }
                    LabeledContent("Stations") { TextField("optional", text: $stations).multilineTextAlignment(.trailing) }
                    TextField("Why this session", text: $why, axis: .vertical).lineLimit(1...4)
                }
                Section {
                    Button("Delete session", role: .destructive) {
                        context.delete(plan); try? context.save(); dismiss()
                    }
                }
            }
            .navigationTitle("Edit plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        plan.categoryRaw = category.rawValue
        plan.date = date
        plan.type = type
        plan.name = name
        plan.meta = meta
        plan.intentRaw = intent.rawValue
        plan.targetZone = targetZone.isEmpty ? nil : targetZone
        plan.stations = stations.isEmpty ? nil : stations
        plan.why = why.isEmpty ? nil : why
        plan.completed = completed
        plan.sourceRaw = PlanSource.athlete.rawValue
        plan.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
