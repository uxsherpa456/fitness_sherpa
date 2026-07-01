//  AthleteView.swift
//  Ravns
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
                            ModuleLabel("Diagnosis · quadrant", tint: Palette.text)
                            if let d = model.diagnosis {
                                QuadrantChart(markerX: d.markerX, markerY: d.markerY, active: d.profile)
                                Text(d.profile.title).font(.headline)
                                Text(d.profile.verdict)
                                    .font(.subheadline).foregroundStyle(Palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    Text("\(Int((d.goalReadiness * 100).rounded()))% to your \(model.settings.goalTimeDisplay) goal")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
                                    Text("· run \(Int((d.runReadiness * 100).rounded()))% · strength \(Int((d.strengthReadiness * 100).rounded()))%")
                                        .font(.caption).foregroundStyle(Palette.textMuted)
                                }
                            } else {
                                Text("No diagnosis yet.").foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                    if let d = model.diagnosis {
                        Card(style: .dark) {
                            VStack(alignment: .leading, spacing: 10) {
                                ModuleLabel("The read")
                                kv("Focus", d.goalFocus)
                                kv("Limiter", d.limiter)
                                kv("Evidence", d.evidence)
                                if let m = model.settings.mobilityFlag, m != .mobile {   // only when it's a limiter
                                    kv("Mobility", m.label)
                                    Text(m.read).font(.caption).foregroundStyle(Palette.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    economySection
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
                    HStack(spacing: 6) {
                        Image(systemName: "bird.fill").font(.system(size: 10))
                        Text("MUNIN · WHAT YOU'VE TRAINED, REMEMBERED")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.2)
                    }
                    .foregroundStyle(Palette.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
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
                if model.settings.noRace {
                    kv("Goal date", raceDateText)
                } else {
                    kv("Race", "\(raceDateText) · \(model.settings.raceLocation)")
                }
                kv("Goal", model.settings.goalTimeDisplay)
            }
        }
    }

    // MARK: - Running economy

    private var economy: EconomyResult {
        RunningEconomy.compute(sessions: sessions, restingHR: model.reading?.restingHR?.value,
                               age: model.settings.age, recent5k: DiagnosisEngine.parse5k(model.settings.recent5k))
    }
    private var goalEasyPaceSecPerKm: Double? {
        PlanEngine.goalFresh5kSeconds(model.settings).map { $0 / 5 + 70 }   // easy = goal-5k pace + 70 s/km
    }
    private var goalVdot: Double {
        DiagnosisEngine.vdot(seconds: PlanEngine.goalFresh5kSeconds(model.settings) ?? 22 * 60)
    }

    @ViewBuilder private var economySection: some View {
        let eco = economy
        economyCard(eco)
        economyExplainer(eco)
        economyTrendCard(eco)
    }

    private func economyCard(_ eco: EconomyResult) -> some View {
        let unit = Units.distanceUnit(model.settings)
        return Card(style: .dark) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleLabel("Running economy")
                    Spacer()
                    if let d = eco.deltaPts, abs(d) >= 0.5 {
                        let up = d > 0
                        HStack(spacing: 3) {
                            Image(systemName: up ? "arrow.up" : "arrow.down")
                            Text("\(up ? "+" : "")\(Int(d.rounded())) pts")
                        }
                        .font(.caption.weight(.bold)).foregroundStyle(up ? Palette.green : Palette.red)
                    }
                }
                if eco.validCount == 0 {
                    Text("Log an easy run (≥ 2 km) with heart rate and your economy unlocks here — pace per heartbeat, trending against your own baseline.")
                        .font(.subheadline).foregroundStyle(Palette.textMuted).fixedSize(horizontal: false, vertical: true)
                } else if eco.building {
                    Text("Building your baseline — \(eco.validCount)/\(RunningEconomy.minValidSamples) valid runs. Keep logging easy (Z2) runs with HR; your Economy Index unlocks at \(RunningEconomy.minValidSamples).")
                        .font(.subheadline).foregroundStyle(Palette.textMuted).fixedSize(horizontal: false, vertical: true)
                } else if let idx = eco.index {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Economy Index").font(.subheadline).foregroundStyle(Palette.textMuted)
                        Spacer()
                        Text("\(Int(idx.rounded())) / 100").font(.headline).foregroundStyle(Palette.text)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surfaceLine)
                            Capsule().fill(Palette.mint).frame(width: g.size.width * idx / 100)
                        }
                    }.frame(height: 8)
                    VStack(spacing: 8) {
                        if let z2 = eco.z2PaceSecPerKm {
                            economyRow("Z2 pace", RunningEconomy.paceLabel(z2, unit: unit),
                                       goal: goalEasyPaceSecPerKm.map { RunningEconomy.paceLabel($0, unit: unit) })
                        }
                        economyRow("VDOT", "\(Int(eco.vdot.rounded()))", goal: "need ~\(Int(goalVdot.rounded()))")
                        if let hr = eco.hrAtZ2 { economyRow("HR @ Z2", "\(hr) bpm", goal: nil) }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func economyRow(_ label: String, _ current: String, goal: String?) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(current).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            if let goal {
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Palette.textFaint)
                Text(goal).font(.subheadline).foregroundStyle(Palette.mint)
            }
        }
    }

    // §5C — plain-language explainer, anchored to THIS athlete's numbers (never population averages).
    @ViewBuilder private func economyExplainer(_ eco: EconomyResult) -> some View {
        if !eco.building, let idx = eco.index {
            Card(style: .ai) {
                VStack(alignment: .leading, spacing: 6) {
                    ModuleLabel("What this means")
                    Text(economyExplainerText(eco, idx)).font(.subheadline).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func economyExplainerText(_ eco: EconomyResult, _ idx: Double) -> String {
        let unit = Units.distanceUnit(model.settings)
        let i = Int(idx.rounded())
        var out: [String] = []
        if let d = eco.deltaPts, abs(d) >= 1 {
            out.append("Your economy index is \(i) — \(d > 0 ? "up" : "down") \(abs(Int(d.rounded()))) points in the last few weeks.")
            out.append(d > 0
                ? "Your body's moving more efficiently at the same heart rate."
                : "You're a touch less efficient at the same heart rate — usually fatigue or under-fueling, not lost fitness.")
        } else {
            out.append("Your economy index is \(i), holding near your own baseline.")
        }
        if let z2 = eco.z2PaceSecPerKm {
            var s = "Your easy (Z2) pace is around \(RunningEconomy.paceLabel(z2, unit: unit))"
            if let g = goalEasyPaceSecPerKm { s += " (goal \(RunningEconomy.paceLabel(g, unit: unit)))" }
            s += ", and your VDOT sits at \(Int(eco.vdot.rounded()))."
            out.append(s)
        }
        out.append("To hit your \(model.settings.goalTimeDisplay) target you're aiming for about VDOT \(Int(goalVdot.rounded()))"
                   + (goalEasyPaceSecPerKm.map { " and a Z2 pace near \(RunningEconomy.paceLabel($0, unit: unit))" } ?? "")
                   + ". Keep the Z2 volume consistent — that's the lever.")
        return out.joined(separator: " ")
    }

    // §5B — dual-axis trend: Economy Index + (inverted) Z2 pace over the recent weeks.
    @ViewBuilder private func economyTrendCard(_ eco: EconomyResult) -> some View {
        let idxWeeks = eco.weeks.filter { $0.avgIndex != nil }
        if idxWeeks.count >= 2 {
            ChartCard(title: "Economy trend", subtitle: "index + Z2 pace", isEmpty: false) {
                EconomyTrendChart(weeks: Array(eco.weeks.suffix(16)),
                                  unit: Units.distanceUnit(model.settings),
                                  raceDate: DateFormatters.ymd.date(from: model.settings.raceDate))
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
