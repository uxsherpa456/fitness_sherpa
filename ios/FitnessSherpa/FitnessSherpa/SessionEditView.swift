//  SessionEditView.swift
//  Fitness Sherpa
//
//  Add or edit a training session. Per the Becoming spec, editing any field stamps it user-sourced
//  (and isEdited), which then protects it from being overwritten by future HealthKit imports.

import SwiftUI
import SwiftData

struct SessionEditView: View {
    let session: TrainingSession?      // nil = add new manual session

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: SessionCategory
    @State private var date: Date
    @State private var durationMin: Int
    @State private var distanceText: String
    @State private var caloriesText: String
    @State private var avgHRText: String
    @State private var maxHRText: String
    @State private var rpe: Int
    @State private var notes: String

    init(session: TrainingSession?) {
        self.session = session
        _category = State(initialValue: session?.cat ?? .run)
        _date = State(initialValue: session?.date ?? Date())
        _durationMin = State(initialValue: session?.durationMin ?? 45)
        _distanceText = State(initialValue: session?.distanceKm.map { String(format: "%.2f", $0) } ?? "")
        _caloriesText = State(initialValue: session?.caloriesKcal.map { String(Int($0)) } ?? "")
        _avgHRText = State(initialValue: session?.avgHR.map(String.init) ?? "")
        _maxHRText = State(initialValue: session?.maxHR.map(String.init) ?? "")
        _rpe = State(initialValue: session?.rpe ?? 0)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var isHealthKit: Bool { session?.isManual == false }

    var body: some View {
        NavigationStack {
            Form {
                if isHealthKit {
                    Section {
                        Label("Imported from Apple Health. Edits become yours and survive future imports.",
                              systemImage: "applelogo")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Workout") {
                    Picker("Type", selection: $category) {
                        ForEach(SessionCategory.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Stepper("Duration: \(durationMin) min", value: $durationMin, in: 0...300, step: 5)
                    TextField("Distance km (optional)", text: $distanceText).keyboardType(.decimalPad)
                    TextField("Calories kcal (optional)", text: $caloriesText).keyboardType(.numberPad)
                    TextField("Avg HR bpm (optional)", text: $avgHRText).keyboardType(.numberPad)
                    TextField("Max HR bpm (optional)", text: $maxHRText).keyboardType(.numberPad)
                    Picker("RPE / effort (optional)", selection: $rpe) {
                        Text("—").tag(0)
                        ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(1...4)
                }
                if session != nil {
                    Section {
                        Button("Delete session", role: .destructive) {
                            if let s = session { context.delete(s); try? context.save() }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(session == nil ? "Add workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let km = Double(distanceText.replacingOccurrences(of: ",", with: "."))
        let kcal = Double(caloriesText)
        let hr = Int(avgHRText)
        let mhr = Int(maxHRText)
        let r = rpe == 0 ? nil : rpe
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes

        if let s = session {
            if s.date != date { s.date = date; s.provenance.date = .mk(.user) }
            if s.category != category.rawValue {
                s.category = category.rawValue; s.title = category.label
                s.provenance.category = .mk(.user); s.provenance.title = .mk(.user)
            }
            if s.durationMin != durationMin { s.durationMin = durationMin; s.provenance.durationMin = .mk(.user) }
            if s.distanceKm != km { s.distanceKm = km; s.provenance.distanceKm = .mk(.user) }
            if s.caloriesKcal != kcal { s.caloriesKcal = kcal; s.provenance.calories = .mk(.user) }
            if s.avgHR != hr { s.avgHR = hr; s.provenance.avgHR = .mk(.user) }
            if s.maxHR != mhr { s.maxHR = mhr; s.provenance.maxHR = .mk(.user) }
            if s.rpe != r { s.rpe = r; s.provenance.rpe = .mk(.user) }
            if s.notes != n { s.notes = n; s.provenance.notes = .mk(.user) }
        } else {
            context.insert(TrainingSession(
                healthkitUUID: nil, date: date, category: category.rawValue, title: category.label,
                durationMin: durationMin, distanceKm: km, caloriesKcal: kcal,
                avgHR: hr, maxHR: mhr, rpe: r, notes: n, source: .user))
        }
        try? context.save()
        dismiss()
    }
}
