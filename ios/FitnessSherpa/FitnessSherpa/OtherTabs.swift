//  OtherTabs.swift
//  Fitness Sherpa
//
//  Athlete / Plan / AI Coach tabs. Athlete surfaces the live diagnosis + saved history; Plan and
//  Coach are honest placeholders until those features are ported from the prototype.

import SwiftUI
import SwiftData

struct AthleteView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \DiagnosisRecord.date, order: .reverse) private var diagnoses: [DiagnosisRecord]
    @Query(sort: \HealthSnapshot.capturedAt, order: .reverse) private var snapshots: [HealthSnapshot]
    @State private var editingGoal: GoalArc?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card(style: .dark) {
                        VStack(alignment: .leading, spacing: 12) {
                            ModuleLabel("Diagnosis · quadrant")
                            if let d = model.diagnosis {
                                QuadrantChart(markerX: d.markerX, markerY: d.markerY, active: d.profile)
                                Text(d.profile.title).font(.headline)
                            } else {
                                Text("No diagnosis yet.").foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                    if let d = model.diagnosis {
                        Card(style: .dark) {
                            VStack(alignment: .leading, spacing: 10) {
                                ModuleLabel("The read")
                                kv("Limiter", d.limiter)
                                kv("Focus", d.focus)
                                kv("Evidence", d.evidence)
                            }
                        }
                    }
                    if !model.goals.isEmpty {
                        Card(style: .dark) {
                            VStack(alignment: .leading, spacing: 16) {
                                ModuleLabel("Focus metrics · arc to race day")
                                ForEach(model.goals) { goalRow($0) }
                            }
                        }
                    }
                    Card(style: .dark) {
                        VStack(alignment: .leading, spacing: 8) {
                            ModuleLabel("History (SwiftData)")
                            kv("Snapshots", "\(snapshots.count)")
                            kv("Diagnoses", "\(diagnoses.count)")
                            if let last = diagnoses.first {
                                kv("Latest", "\(last.profile.title) · \(last.date.formatted(.relative(presentation: .named)))")
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(Palette.bg)
            .refreshable { await model.refresh(context: context) }
            .appBar(model)
            .sheet(item: $editingGoal) { GoalEditView(goal: $0, model: model) }
        }
    }

    private func goalRow(_ g: GoalArc) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(g.label ?? g.key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(Palette.textFaint)
                Spacer()
                HStack(spacing: 2) {
                    Text(g.currentDisplay).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                    if let u = g.unit, !u.isEmpty { Text(u).font(.caption).foregroundStyle(Palette.textMuted) }
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2).frame(height: 5)
                GeometryReader { geo in
                    Capsule().fill(Palette.mint)
                        .frame(width: max(5, geo.size.width * (g.progress ?? 0)), height: 5)
                }
                .frame(height: 5)
            }
            HStack {
                Text("start \(g.startDisplay)").font(.caption2).foregroundStyle(Palette.textFaint)
                Spacer()
                Text("goal \(g.goalDisplay)").font(.caption2.weight(.semibold)).foregroundStyle(Palette.mint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingGoal = g }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.subheadline).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(v).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }
}

/// Shared placeholder tab body.
@ViewBuilder
private func placeholder(_ title: String, _ subtitle: String) -> some View {
    NavigationStack {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill").font(.largeTitle).foregroundStyle(Palette.mint)
            Text(title).font(.title2.bold()).foregroundStyle(Palette.text)
            Text(subtitle).font(.footnote).foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.bg, for: .navigationBar)
    }
}
