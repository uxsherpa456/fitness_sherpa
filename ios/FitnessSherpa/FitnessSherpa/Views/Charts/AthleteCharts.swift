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
