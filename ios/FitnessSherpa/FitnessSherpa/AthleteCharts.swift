//  AthleteCharts.swift
//  Fitness Sherpa
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
    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("Readiness", p.value))
                .foregroundStyle(Palette.mint)
            PointMark(x: .value("Date", p.date), y: .value("Readiness", p.value))
                .foregroundStyle(Palette.mint).symbolSize(18)
        }
        .chartYScale(domain: 0...100)
        .darkChartAxes()
    }
}

struct FormChart: View {
    let points: [FormPoint]
    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("Load", p.ctl), series: .value("s", "Fitness"))
                .foregroundStyle(Palette.mint)
            LineMark(x: .value("Date", p.date), y: .value("Load", p.atl), series: .value("s", "Fatigue"))
                .foregroundStyle(Palette.red)
        }
        .chartForegroundStyleScale(["Fitness": Palette.mint, "Fatigue": Palette.red])
        .chartLegend(position: .top, alignment: .leading)
        .darkChartAxes()
    }
}

struct ACRChart: View {
    let points: [FormPoint]
    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("ACR", p.ratio))
                    .foregroundStyle(Palette.mint).interpolationMethod(.catmullRom)
            }
            RuleMark(y: .value("low", 0.8)).foregroundStyle(Palette.textFaint.opacity(0.5))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
            RuleMark(y: .value("high", 1.3)).foregroundStyle(Palette.yellow.opacity(0.6))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
            RuleMark(y: .value("danger", 1.5)).foregroundStyle(Palette.red.opacity(0.6))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
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
