//  AthleteView.swift
//  Fitness Sherpa
//
//  The Athlete tab: live diagnosis + quadrant, focus-metric goals (race log), and trend charts.

import SwiftUI
import SwiftData
import HealthKit

struct AthleteView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.date, order: .forward) private var sessions: [TrainingSession]
    @Query(sort: \DailyReadiness.day, order: .forward) private var readinessLog: [DailyReadiness]
    @Query(sort: \DiagnosisRecord.date, order: .forward) private var dxHistory: [DiagnosisRecord]
    @State private var editingGoal: GoalArc?
    @State private var hrvTrend: [TrendPoint] = []
    @State private var sleepNights: [SleepNight] = []
    @State private var formTrend: [FormPoint] = []
    @State private var vo2max: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    athleteFactsCard
                    Card(style: .dark) {
                        VStack(alignment: .leading, spacing: 12) {
                            ModuleLabel("Diagnosis · quadrant")
                            if let d = model.diagnosis {
                                QuadrantChart(markerX: d.markerX, markerY: d.markerY, active: d.profile, trail: diagnosisTrail)
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
                                if let m = model.settings.mobilityFlag, m != .mobile {   // only when it's a limiter
                                    kv("Mobility", m.label)
                                    Text(m.read).font(.caption).foregroundStyle(Palette.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
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
                    statsCard
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

    private var readinessSeries: [TrendPoint] {
        readinessLog.map { TrendPoint(date: $0.day, value: Double($0.score)) }
    }

    /// Path of past quadrant positions (oldest → newest), de-duped, ending at where you are now.
    private var diagnosisTrail: [CGPoint] {
        var pts: [CGPoint] = []
        for r in dxHistory {
            let p = CGPoint(x: r.markerX, y: r.markerY)
            if pts.last.map({ hypot($0.x - p.x, $0.y - p.y) > 0.01 }) ?? true { pts.append(p) }
        }
        if let d = model.diagnosis {
            let cur = CGPoint(x: d.markerX, y: d.markerY)
            if pts.last.map({ hypot($0.x - cur.x, $0.y - cur.y) > 0.001 }) ?? true { pts.append(cur) }
        }
        return pts
    }

    private func loadTrends() async {
        formTrend = TrainingLoad.series(sessions: sessions, restingHR: model.reading?.restingHR?.value, age: model.settings.age)
        hrvTrend = (try? await HealthData.dailySeries(.heartRateVariabilitySDNN,
                    unit: .secondUnit(with: .milli), days: 30, options: .discreteAverage)) ?? []
        sleepNights = (try? await HealthData.sleepNights(days: 21)) ?? []
        vo2max = (try? await HealthData.latestSample(.vo2Max, unit: HKUnit(from: "mL/kg*min")))??.value
    }

    // MARK: - Athlete facts

    private func fmt(_ s: String, _ map: [String: String]) -> String { map[s] ?? s.capitalized }
    private var formatLabel: String {
        fmt(model.settings.format, ["singles": "Singles", "doubles": "Doubles", "relay": "Relay", "elite15": "Elite 15"])
    }
    private var genderLabel: String {
        fmt(model.settings.gender, ["mens": "Men's", "womens": "Women's", "mixed": "Mixed"])
    }
    private var divisionText: String {
        var parts = [formatLabel, genderLabel]
        if model.settings.format == "singles" { parts.append(fmt(model.settings.tier, ["open": "Open", "pro": "Pro"])) }
        return parts.joined(separator: " · ")
    }
    private var raceDateText: String {
        guard let d = DateFormatters.ymd.date(from: model.settings.raceDate) else { return model.settings.raceDate }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var athleteFactsCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("Athlete")
                kv("Division", divisionText)
                kv("Age", "\(model.settings.age)")
                kv("Race", "\(raceDateText) · \(model.settings.raceLocation)")
                kv("Goal", model.settings.goalTimeDisplay)
            }
        }
    }

    // MARK: - Training stats (from the workout store)

    private var runs: [TrainingSession] { sessions.filter { $0.cat == .run } }
    private func inThisMonth(_ d: Date) -> Bool { Calendar.current.isDate(d, equalTo: Date(), toGranularity: .month) }
    private var monthRunKm: Double { runs.filter { inThisMonth($0.date) }.compactMap(\.distanceKm).reduce(0, +) }
    private var monthRunMin: Int { runs.filter { inThisMonth($0.date) }.reduce(0) { $0 + $1.durationMin } }
    private var monthWorkouts: Int { sessions.filter { inThisMonth($0.date) }.count }
    private var yearRunKm: Double {
        let cutoff = Date().addingTimeInterval(-365 * 86400)
        return runs.filter { $0.date >= cutoff }.compactMap(\.distanceKm).reduce(0, +)
    }
    private var longestRunKm: Double { runs.compactMap(\.distanceKm).max() ?? 0 }
    private var paceDisplay: String {
        guard monthRunKm > 0, monthRunMin > 0 else { return "—" }
        let perKm = Double(monthRunMin) / monthRunKm
        let per = model.settings.distanceUnit == "mi" ? perKm * 1.609344 : perKm
        let sec = Int((per * 60).rounded())
        return String(format: "%d:%02d /%@", sec / 60, sec % 60, Units.distanceUnit(model.settings))
    }

    private var statsCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleLabel("Training · this month")
                HStack(spacing: 0) {
                    statTile("RUN", Units.displayDistance(km: monthRunKm, model.settings) ?? "—")
                    statTile("AVG PACE", paceDisplay)
                    statTile("WORKOUTS", "\(monthWorkouts)")
                }
                Rectangle().fill(Palette.surfaceLine).frame(height: 1)
                kv("Run · last 12 mo", Units.displayDistance(km: yearRunKm, model.settings) ?? "—")
                kv("Longest run", Units.displayDistance(km: longestRunKm, model.settings) ?? "—")
                if let v = vo2max { kv("VO₂max", String(format: "%.0f mL/kg·min", v)) }
                if let rhr = model.reading?.restingHR?.value { kv("Resting HR", "\(Int(rhr)) bpm") }
            }
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 18, weight: .heavy)).foregroundStyle(Palette.text)
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.5)
                .foregroundStyle(Palette.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trendCharts: some View {
        ChartCard(title: "Form · fresh vs fatigued", subtitle: "TSB", isEmpty: formTrend.count < 3) {
            FormChart(points: formTrend)
        }
        ChartCard(title: "HRV trend", subtitle: "30 days", isEmpty: hrvTrend.count < 2) {
            HRVTrendChart(points: hrvTrend)
        }
        ChartCard(title: "Acute : chronic load", subtitle: "ratio", isEmpty: formTrend.count < 3) {
            ACRChart(points: formTrend)
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
