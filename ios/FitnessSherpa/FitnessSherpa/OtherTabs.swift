//  OtherTabs.swift
//  Fitness Sherpa
//
//  Athlete / Plan / AI Coach tabs. Athlete surfaces the live diagnosis + saved history; Plan and
//  Coach are honest placeholders until those features are ported from the prototype.

import SwiftUI
import SwiftData
import HealthKit

struct AthleteView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \DiagnosisRecord.date, order: .reverse) private var diagnoses: [DiagnosisRecord]
    @Query(sort: \HealthSnapshot.capturedAt, order: .reverse) private var snapshots: [HealthSnapshot]
    @Query(sort: \TrainingSession.date, order: .forward) private var sessions: [TrainingSession]
    @Query(sort: \DailyReadiness.day, order: .forward) private var readinessLog: [DailyReadiness]
    @State private var editingGoal: GoalArc?
    @State private var hrvTrend: [TrendPoint] = []
    @State private var sleepNights: [SleepNight] = []

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
                            VStack(alignment: .leading, spacing: 14) {
                                ModuleLabel("Focus metrics · race log")
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 16) {
                                    GridRow {
                                        colHead("START"); colHead("CURRENT"); colHead("GOAL")
                                    }
                                    GridRow {
                                        Rectangle().fill(Palette.surfaceLine).frame(height: 1).gridCellColumns(3)
                                    }
                                    ForEach(model.goals) { g in
                                        GridRow {
                                            metricCell(g.startDisplay, color: Color(hex: 0x7C8088), label: g.label)
                                            metricCell(g.currentDisplay, color: Palette.text, label: g.label, arrow: arrowFor(g))
                                            metricCell(g.goalDisplay, color: Palette.mint, label: g.label)
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture { editingGoal = g }
                                    }
                                }
                            }
                        }
                    }
                    trendCharts
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(Palette.bg)
            .refreshable { await model.refresh(context: context); await loadTrends() }
            .task { await loadTrends() }
            .appBar(model)
            .sheet(item: $editingGoal) { GoalEditView(goal: $0, model: model) }
        }
    }

    // MARK: - Trend charts

    private var formSeries: [FormPoint] {
        TrainingLoad.series(sessions: sessions, restingHR: model.reading?.restingHR?.value, age: model.settings.age)
    }
    private var readinessSeries: [TrendPoint] {
        readinessLog.map { TrendPoint(date: $0.day, value: Double($0.score)) }
    }

    private func loadTrends() async {
        hrvTrend = (try? await HealthData.dailySeries(.heartRateVariabilitySDNN,
                    unit: .secondUnit(with: .milli), days: 30, options: .discreteAverage)) ?? []
        sleepNights = (try? await HealthData.sleepNights(days: 21)) ?? []
    }

    @ViewBuilder private var trendCharts: some View {
        ChartCard(title: "Form · fresh vs fatigued", subtitle: "TSB", isEmpty: formSeries.count < 3) {
            FormChart(points: formSeries)
        }
        ChartCard(title: "HRV trend", subtitle: "30 days", isEmpty: hrvTrend.count < 2) {
            HRVTrendChart(points: hrvTrend)
        }
        ChartCard(title: "Acute : chronic load", subtitle: "ratio", isEmpty: formSeries.count < 3) {
            ACRChart(points: formSeries)
        }
        ChartCard(title: "Sleep quality", subtitle: "deep / REM / light", isEmpty: sleepNights.count < 2) {
            SleepChart(nights: sleepNights)
        }
        ChartCard(title: "Readiness over time", subtitle: "logged daily", isEmpty: readinessSeries.count < 2) {
            ReadinessTrendChart(points: readinessSeries)
        }
    }

    private func colHead(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
            .foregroundStyle(Palette.textMuted)
    }

    private func metricCell(_ value: String, color: Color, label: String?, arrow: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                if let arrow { Text(arrow).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.mint) }
                Text(value).font(.system(size: 20, weight: .heavy)).tracking(-0.5).foregroundStyle(color)
            }
            Text(label ?? "").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                .foregroundStyle(Palette.textFaint).lineLimit(1)
        }
    }

    private func arrowFor(_ g: GoalArc) -> String? {
        guard let s = g.start?.asDouble, let c = g.current?.asDouble, c != s else { return nil }
        return c < s ? "↓" : "↑"
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
