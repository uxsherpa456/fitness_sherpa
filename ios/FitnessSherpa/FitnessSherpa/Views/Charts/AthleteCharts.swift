//  AthleteCharts.swift
//  Ravns
//
//  Trend charts for the Athlete tab. HRV / sleep / form / acute:chronic come from Apple Health
//  history (reconstructed); readiness comes from the daily log.

import SwiftUI
import Charts

private let chartHeight: CGFloat = 130

/// Card wrapper with a label + a chart (or an empty note).
struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let isEmpty: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    ModuleLabel(title)
                    Spacer()
                    if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Palette.textMuted) }
                }
                if isEmpty {
                    Text("Not enough history yet.").font(.footnote).foregroundStyle(Palette.textFaint)
                        .frame(height: chartHeight, alignment: .center).frame(maxWidth: .infinity)
                } else {
                    content().frame(height: chartHeight)
                }
            }
        }
    }
}

private extension View {
    func darkChartAxes() -> some View {
        self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel().foregroundStyle(Palette.textFaint) } }
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Palette.surfaceLine.opacity(0.5)); AxisValueLabel().foregroundStyle(Palette.textFaint) } }
    }
}

struct HRVTrendChart: View {
    let points: [TrendPoint]
    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("HRV", p.value))
                .foregroundStyle(Palette.mint).interpolationMethod(.catmullRom)
            AreaMark(x: .value("Date", p.date), y: .value("HRV", p.value))
                .foregroundStyle(.linearGradient(colors: [Palette.mint.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
        }
        .darkChartAxes()
    }
}

struct ReadinessTrendChart: View {
    let points: [TrendPoint]
    private func band(_ v: Double) -> Color { v >= 75 ? Palette.green : (v >= 50 ? Palette.yellow : Palette.red) }
    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Readiness", p.value))
                    .foregroundStyle(Palette.textMuted).interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                PointMark(x: .value("Date", p.date), y: .value("Readiness", p.value))
                    .foregroundStyle(band(p.value)).symbolSize(28)
            }
        }
        .chartYScale(domain: 0...100)
        .darkChartAxes()
    }
}

/// Form (TSB = CTL − ATL): bars up/green when fresh, down/red when fatigued, orange when neutral.
struct FormChart: View {
    let points: [FormPoint]
    private func color(_ f: Double) -> Color { f >= 5 ? Palette.green : (f <= -10 ? Palette.red : Palette.orange) }
    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Date", p.date, unit: .day), y: .value("Form", p.form))
                    .foregroundStyle(color(p.form))
            }
            RuleMark(y: .value("zero", 0)).foregroundStyle(Palette.textFaint.opacity(0.7))
                .lineStyle(.init(lineWidth: 1))
        }
        .darkChartAxes()
    }
}

struct ACRChart: View {
    let points: [FormPoint]
    private func color(_ r: Double) -> Color { r <= 1.3 ? Palette.green : (r <= 1.5 ? Palette.orange : Palette.red) }
    var body: some View {
        Chart {
            if let x0 = points.first?.date, let x1 = points.last?.date {
                RectangleMark(xStart: .value("", x0), xEnd: .value("", x1), yStart: .value("", 0.8), yEnd: .value("", 1.3))
                    .foregroundStyle(Palette.green.opacity(0.10))
                RectangleMark(xStart: .value("", x0), xEnd: .value("", x1), yStart: .value("", 1.3), yEnd: .value("", 1.5))
                    .foregroundStyle(Palette.orange.opacity(0.12))
                RectangleMark(xStart: .value("", x0), xEnd: .value("", x1), yStart: .value("", 1.5), yEnd: .value("", 2.2))
                    .foregroundStyle(Palette.red.opacity(0.12))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("ACR", p.ratio))
                    .foregroundStyle(Palette.text).interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                PointMark(x: .value("Date", p.date), y: .value("ACR", p.ratio))
                    .foregroundStyle(color(p.ratio)).symbolSize(16)
            }
        }
        .darkChartAxes()
    }
}

struct SleepChart: View {
    let nights: [SleepNight]
    var body: some View {
        Chart(nights) { n in
            BarMark(x: .value("Date", n.date, unit: .day), y: .value("Deep", n.deep))
                .foregroundStyle(by: .value("Stage", "Deep"))
            BarMark(x: .value("Date", n.date, unit: .day), y: .value("REM", n.rem))
                .foregroundStyle(by: .value("Stage", "REM"))
            BarMark(x: .value("Date", n.date, unit: .day), y: .value("Light", max(0, n.asleep - n.deep - n.rem)))
                .foregroundStyle(by: .value("Stage", "Light"))
        }
        .chartForegroundStyleScale(["Deep": Palette.mint, "REM": Palette.yellow, "Light": Palette.surface2])
        .chartLegend(position: .top, alignment: .leading)
        .darkChartAxes()
    }
}

/// Dual-axis economy trend: Economy Index (left, 0–100) + Z2 pace (right, inverted so faster reads
/// higher — alongside the index). Pace is normalized into the index's plot space, with the trailing
/// axis labelled in real pace via the inverse map. Baseline (50) and the race/goal date are marked.
struct EconomyTrendChart: View {
    let weeks: [EconomyWeek]
    let unit: String
    var raceDate: Date? = nil

    private var idxPts: [(Date, Double)] { weeks.compactMap { w in w.avgIndex.map { (w.weekStart, $0) } } }
    private var pacePts: [(Date, Double)] { weeks.compactMap { w in w.z2PaceSecPerKm.map { (w.weekStart, $0) } } }
    private var hasPace: Bool { pacePts.count >= 2 }

    private var paceBounds: (lo: Double, hi: Double) {
        let ps = pacePts.map(\.1)
        guard let mn = ps.min(), let mx = ps.max() else { return (300, 420) }
        let pad = max(8, (mx - mn) * 0.25)
        return (mn - pad, mx + pad)   // seconds/km; lo = faster end, hi = slower end
    }
    private func plot(_ p: Double) -> Double {           // pace → 0…100, faster (smaller p) higher
        let b = paceBounds; guard b.hi > b.lo else { return 50 }
        return min(max(100 * (b.hi - p) / (b.hi - b.lo), 0), 100)
    }
    private func paceAt(_ y: Double) -> Double {          // inverse, for the trailing labels
        let b = paceBounds; return b.hi - (y / 100) * (b.hi - b.lo)
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("baseline", 50))
                .foregroundStyle(Palette.textFaint.opacity(0.5))
                .lineStyle(.init(lineWidth: 1, dash: [4, 3]))

            if hasPace {
                ForEach(pacePts, id: \.0) { pt in
                    LineMark(x: .value("Week", pt.0), y: .value("Z2 pace", plot(pt.1)),
                             series: .value("s", "Z2 pace"))
                        .foregroundStyle(Palette.orange).interpolationMethod(.catmullRom)
                        .lineStyle(.init(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            ForEach(idxPts, id: \.0) { pt in
                LineMark(x: .value("Week", pt.0), y: .value("Index", pt.1), series: .value("s", "Economy"))
                    .foregroundStyle(Palette.mint).interpolationMethod(.catmullRom)
                PointMark(x: .value("Week", pt.0), y: .value("Index", pt.1))
                    .foregroundStyle(Palette.mint).symbolSize(24)
            }
            if let rd = raceDate, let first = idxPts.first?.0, let last = idxPts.last?.0,
               rd >= first, rd <= last.addingTimeInterval(21 * 86400) {
                RuleMark(x: .value("Race", rd))
                    .foregroundStyle(Palette.red.opacity(0.65)).lineStyle(.init(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .trailing) { Text("🏁").font(.caption2) }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) {
                AxisGridLine().foregroundStyle(Palette.surfaceLine.opacity(0.5))
                AxisValueLabel().foregroundStyle(Palette.mint.opacity(0.85))
            }
            if hasPace {
                AxisMarks(position: .trailing, values: [15.0, 50.0, 85.0]) { v in
                    if let y = v.as(Double.self) {
                        AxisValueLabel {
                            Text(RunningEconomy.paceLabel(paceAt(y), unit: unit))
                                .foregroundStyle(Palette.orange.opacity(0.85))
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(Palette.textFaint)
            }
        }
    }
}
