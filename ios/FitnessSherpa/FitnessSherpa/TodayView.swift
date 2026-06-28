//  TodayView.swift
//  Fitness Sherpa
//
//  The Today tab, ported from prototype/index.html (lines 1102–1222): readiness verdict, fuel,
//  last-workout read, next session, AI coach entry. Live data (HRV/resting HR + freshness, the
//  diagnosis, last run) is wired in; cards backed by features not yet built (fuel, HR-drift
//  analysis) keep the prototype copy and are marked "sample" so test data isn't mistaken for real.

import SwiftUI
import SwiftData

struct TodayView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    readinessCard
                    fuelCard
                    lastWorkoutCard
                    nextSessionCard
                    coachEntryCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Palette.bg)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.bg, for: .navigationBar)
        }
    }

    // MARK: - A. Readiness hero (live)

    private var readinessCard: some View {
        Card(style: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleLabel("Readiness", onLight: true)
                    Spacer()
                    if let r = model.reading, r.readinessFresh, let s = model.readinessScore {
                        StatusPill(label: Readiness.verdict(for: s).label,
                                   dot: Readiness.verdict(for: s).color, onLight: true)
                    } else {
                        StatusPill(label: "STALE · CHECK DATA", dot: Palette.yellow, onLight: true)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(model.readinessScore.map(String.init) ?? "—")
                        .font(.system(size: 60, weight: .heavy)).tracking(-2)
                    Text("/100").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.inkSoft)
                }

                Text(verdictText)
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)

                HStack(spacing: 0) {
                    micro("HRV", model.reading?.hrv.map { String(format: "%.0f", $0.value) }, "ms")
                    micro("Resting HR", model.reading?.restingHR.map { String(format: "%.0f", $0.value) }, "bpm")
                    micro("Sleep", model.reading?.sleep.map { String(format: "%.1f", $0.value) }, "hrs")
                }
                .padding(.top, 2)

                Text("v0 readiness score — provisional until the baseline model lands.")
                    .font(.caption2).foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
        }
    }

    private var verdictText: String {
        guard let r = model.reading else { return "Reading your recovery data…" }
        guard r.readinessFresh, let s = model.readinessScore else {
            return "Won't call readiness off stale data. Open Health / wear the watch and re-read."
        }
        let hrv = r.hrv.map { String(format: "%.0f ms", $0.value) } ?? "—"
        switch s {
        case 75...:   return "Recovered and ready. HRV \(hrv). Push the session that moves your limiter."
        case 50..<75: return "Middling recovery (HRV \(hrv)). Train, but hold intensity in check."
        default:      return "Low recovery — HRV \(hrv). Favor easy work or recovery today."
        }
    }

    private func micro(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.system(size: 20, weight: .bold))
            Text("\(label) · \(unit)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - B. Fuel (sample — no nutrition engine yet)

    private var fuelCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("What to eat today")
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("2,820 kcal").font(.system(size: 28, weight: .heavy))
                    Text("QUALITY DAY · DEFICIT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.mint)
                }
                Text("A ~500 kcal deficit to drop toward 200 lb — but fuel today's quality run: carbs before, protein after. Keep protein high to hold strength while the weight comes off.")
                    .font(.footnote).foregroundStyle(Palette.textMuted)
                HStack(spacing: 0) {
                    macro("PROTEIN", "203 g"); macro("CARBS", "349 g"); macro("FAT", "68 g")
                }
                sampleCaption("Sample — fuel engine not wired yet")
            }
        }
    }

    private func macro(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .bold))
            Text(label).font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - C. Last workout read (last run is live; drift analysis pending)

    private var lastWorkoutCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("Last workout · the read")
                Text(lastRunHeading).font(.system(size: 15, weight: .semibold))
                Text("Base is solid — HR drift only 3.2%. Strength holds under fatigue, so the stations aren't the leak. The time you're leaving out there is bodyweight and run pace.")
                    .font(.footnote).foregroundStyle(Palette.textMuted)
                HStack(spacing: 6) {
                    tag("✓ Base held", Palette.green)
                    tag("Strength holds", Palette.green)
                    tag("Pace vs goal", Palette.red)
                }
                sampleCaption("Last run is live; HR-drift analysis pending")
            }
        }
    }

    private var lastRunHeading: String {
        guard let r = model.reading, let date = r.lastRunDate else { return "No recent run found" }
        let km = r.lastRunKm.map { String(format: "%.1f km", $0) } ?? "run"
        return "\(date.formatted(.relative(presentation: .named))) — \(km)"
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - D. Next session (why-this driven by the live diagnosis)

    private var nextSessionCard: some View {
        Card(style: .light) {
            VStack(alignment: .leading, spacing: 8) {
                ModuleLabel("Next session · today", onLight: true)
                Text("Tempo run + strides").font(.system(size: 17, weight: .bold))
                Text("8 km tempo · 40 min · RPE 7").font(.footnote).foregroundStyle(Palette.inkSoft)
                Text(whyThis).font(.footnote).foregroundStyle(Palette.inkSoft).padding(.top, 2)
                sampleCaption("Sample session — plan engine pending", onLight: true)
            }
        }
    }

    private var whyThis: String {
        if let d = model.diagnosis {
            return "Why this, today: your limiter is \(d.limiter). Focus — \(d.focus)."
        }
        return "Why this, today: a quality tempo sharpens 5k pace and strips weight."
    }

    // MARK: - E. AI coach entry (live limiter + verdict)

    private var coachEntryCard: some View {
        Card(style: .ai) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("AI Coach").font(.system(size: 15, weight: .bold))
                        Text("✓ primed").font(.caption2).foregroundStyle(Palette.green)
                    }
                    Text(coachBlurb).font(.footnote).foregroundStyle(Palette.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textFaint)
            }
        }
    }

    private var coachBlurb: String {
        let verdict = model.readinessScore.map { "you're \(Readiness.verdict(for: $0).label.split(separator: " ").first.map(String.init) ?? "set") at \($0)" } ?? "ready"
        let limiter = model.diagnosis?.limiter ?? "your binding constraint"
        return "\(verdict.capitalized) and your limiter's \(limiter). Tap to talk it through — it has today's data."
    }

    // MARK: - shared

    private func sampleCaption(_ text: String, onLight: Bool = false) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle((onLight ? Palette.inkSoft : Palette.textFaint).opacity(0.8))
    }
}
