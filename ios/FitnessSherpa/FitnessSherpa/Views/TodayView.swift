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
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedWorkout.date, order: .forward) private var plan: [PlannedWorkout]
    @Query(sort: \TrainingSession.date, order: .reverse) private var sessions: [TrainingSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    greeting
                    readinessCard
                    feelingCard
                    sleepCard
                    fuelCard
                    lastWorkoutCard
                    nextSessionCard
                    coachEntryCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Palette.bg)
            .refreshable { await model.refresh(context: context) }
            .appBar(model)
        }
    }

    // MARK: - Greeting (race countdown)

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.title3.bold()).foregroundStyle(Palette.text)
            if let days = model.settings.daysToRace, days >= 0 {
                Text("\(days) days out · HYROX \(model.settings.raceLocation)")
                    .font(.caption).foregroundStyle(Palette.textMuted)
            } else {
                Text("HYROX \(model.settings.raceLocation)")
                    .font(.caption).foregroundStyle(Palette.textMuted)
            }
            Text("Goal \(model.settings.goalTimeDisplay)")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2).padding(.bottom, 2)
    }

    // MARK: - A. Readiness hero (live)

    /// Background color by readiness band: mint (high) → orange (moderate) → red (low).
    private var readinessTint: Color {
        guard let s = model.readinessScore else { return Palette.mint }
        switch s {
        case 75...:   return Palette.mint
        case 50..<75: return Palette.orange
        default:      return Palette.red
        }
    }

    private var readinessCard: some View {
        Card(style: .tinted(readinessTint)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleLabel("Readiness", onLight: true)
                    Spacer()
                    if let r = model.reading, r.readinessFresh, let s = model.readinessScore {
                        StatusPill(label: Readiness.verdict(for: s).label,
                                   dot: Palette.ink, onLight: true)
                    } else {
                        StatusPill(label: "STALE · CHECK DATA", dot: Palette.ink, onLight: true)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(model.readinessScore.map(String.init) ?? "—")
                        .font(.system(size: 60, weight: .heavy)).tracking(-2)
                    Text("/100").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.inkSoft)
                }

                Text(verdictText)
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)

                if let rec = model.readiness?.recovery {
                    recoveryReadout(rec)
                }

                HStack(spacing: 0) {
                    micro("HRV", model.reading?.hrv.map { String(format: "%.0f", $0.value) }, "ms")
                    micro("Resting HR", model.reading?.restingHR.map { String(format: "%.0f", $0.value) }, "bpm")
                    micro("Sleep", model.reading?.sleep.map { String(format: "%.1f", $0.value) }, "hrs")
                }
                .padding(.top, 2)

                Text(baselineNote)
                    .font(.caption2).foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
        }
    }

    /// Two-axis recovery readout: state, today's value vs your own normal band (the numbers to beat),
    /// and the plain-English body. Rendered in the readiness card's light style.
    @ViewBuilder private func recoveryReadout(_ rec: RecoveryResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rec.headline).font(.caption.weight(.bold)).foregroundStyle(Palette.ink)
            if let hrv = rec.hrv { axisRow("HRV", hrv, z: rec.hrvZ) }
            if let rhr = rec.rhr { axisRow("RHR", rhr, z: rec.rhrZ) }
            Text(rec.body)
                .font(.caption2).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    /// "HRV  ↓ 39 ms   normal 41–83   −1.2σ" — today's number + an arrow when it's outside your band.
    private func axisRow(_ label: String, _ a: AxisRange, z: Double?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.inkSoft).frame(width: 30, alignment: .leading)
            HStack(spacing: 2) {
                if let arrow = bandArrow(a) {
                    Text(arrow).font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.ink)
                }
                Text("\(Int(a.today.rounded())) \(a.unit)")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Palette.ink)
            }
            Text("normal \(Int(a.low.rounded()))–\(Int(a.high.rounded()))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 0)
            if let z { Text(sigma(z)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.inkSoft) }
        }
    }

    /// ↓ when below the normal band, ↑ when above; nil when inside it.
    private func bandArrow(_ a: AxisRange) -> String? {
        if a.today < a.low  { return "↓" }
        if a.today > a.high { return "↑" }
        return nil
    }

    private func sigma(_ z: Double) -> String { String(format: "%+.1fσ", z) }

    private var baselineNote: String {
        guard let rd = model.readiness else { return "Recovery model warming up…" }
        let personal = rd.components.contains { $0.personal }
        var parts = [personal ? "Relative to your recent baseline" : "Building your baseline — using norms"]
        if let pct = rd.lastHardPct, let h = rd.lastHardHoursAgo, pct >= 0.9 {
            parts.append(String(format: "%.0f%% max-HR effort %.0fh ago", pct * 100, h))
        } else if rd.ratio > 1.3 {
            parts.append(String(format: "training load high (%.1f×)", rd.ratio))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Feeling selector

    private var feelingCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("How do you feel?")
                HStack(spacing: 6) {
                    ForEach(Feeling.allCases) { f in
                        let on = model.todayFeeling == f
                        Button { model.setFeeling(f) } label: {
                            Text(f.label)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(on ? Palette.mint : Palette.surface2, in: Capsule())
                                .foregroundStyle(on ? Palette.ink : Palette.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    // MARK: - Sleep quality (live)

    private var sleepCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("Sleep · last night")
                if let s = model.reading?.sleepSummary {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f hrs", s.asleep)).font(.system(size: 28, weight: .heavy))
                        Text("\(Int((s.efficiency * 100).rounded()))% EFFICIENCY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Palette.mint)
                    }
                    HStack(spacing: 0) {
                        stageTile("REM", s.rem)
                        stageTile("CORE", s.core)
                        stageTile("DEEP", s.deep)
                    }
                    Text(String(format: "In bed %.1f hrs · %d awakening%@ · %.1f hrs awake",
                                s.inBed, s.awakenings, s.awakenings == 1 ? "" : "s", s.awake))
                        .font(.footnote).foregroundStyle(Palette.textMuted)
                } else {
                    Text("No sleep recorded in the last 36h — wear the watch to bed for recovery metrics.")
                        .font(.footnote).foregroundStyle(Palette.textMuted)
                }
            }
        }
    }

    private func stageTile(_ label: String, _ hrs: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f h", hrs)).font(.system(size: 15, weight: .bold))
            Text(label).font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textFaint)
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

    // MARK: - C. Last workout (live — most recent session of any type, from the workout store)

    private var lastWorkout: TrainingSession? { sessions.first }

    private var lastWorkoutCard: some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleLabel("Last workout")
                if let s = lastWorkout {
                    HStack(spacing: 6) {
                        Image(systemName: s.cat.icon).font(.caption).foregroundStyle(s.cat.color)
                        Text("\(s.date.formatted(.relative(presentation: .named))) — \(s.title)")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    Text(workoutDetail(s)).font(.footnote).foregroundStyle(Palette.textMuted)
                    if let (text, color) = effortChip(s) {
                        HStack(spacing: 6) { tag(text, color) }
                    }
                } else {
                    Text("No workouts logged yet — wear your watch or add one on the Plan tab.")
                        .font(.footnote).foregroundStyle(Palette.textMuted)
                }
            }
        }
    }

    private func workoutDetail(_ s: TrainingSession) -> String {
        var parts: [String] = []
        if let km = s.distanceKm, km > 0, let d = Units.displayDistance(km: km, model.settings) { parts.append(d) }
        parts.append("\(s.durationMin) min")
        if let kcal = s.caloriesKcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        if let hr = s.avgHR { parts.append("\(hr) bpm avg") }
        if let mx = s.maxHR { parts.append("\(mx) max") }
        if let rpe = s.rpe { parts.append("RPE \(rpe)") }
        return parts.joined(separator: " · ")
    }

    /// A real effort read from average HR vs the athlete's observed max — not a fabricated analysis.
    private func effortChip(_ s: TrainingSession) -> (String, Color)? {
        guard let avg = s.avgHR else { return nil }
        let hrMax = TrainingLoad.hrMaxFor(sessions: sessions, age: model.settings.age)
        guard hrMax > 0 else { return nil }
        switch Double(avg) / hrMax {
        case 0.85...:    return ("Hard effort", Palette.red)
        case 0.70..<0.85: return ("Moderate", Palette.orange)
        default:         return ("Easy · Z2", Palette.green)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - D. Next session (why-this driven by the live diagnosis)

    /// The next thing on the actual plan: earliest incomplete session from today onward, falling back
    /// to today's session even if it's already done. Same store the Plan tab renders.
    private var nextSession: PlannedWorkout? {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return plan.first { !$0.completed && $0.date >= todayStart }
            ?? plan.last { Calendar.current.isDateInToday($0.date) }
    }

    private var nextSessionCard: some View {
        Card(style: .light) {
            VStack(alignment: .leading, spacing: 8) {
                if let s = nextSession {
                    ModuleLabel(nextSessionLabel(s), onLight: true)
                    Text(s.name.isEmpty ? s.type.capitalized : s.name).font(.system(size: 17, weight: .bold))
                    if !s.meta.isEmpty {
                        Text(s.meta).font(.footnote).foregroundStyle(Palette.inkSoft)
                    }
                    Text(whyThis(s)).font(.footnote).foregroundStyle(Palette.inkSoft).padding(.top, 2)
                    if s.completed {
                        Text("✓ Logged").font(.caption2.weight(.semibold)).foregroundStyle(Palette.inkSoft)
                    }
                } else {
                    ModuleLabel("Next session", onLight: true)
                    Text("Open the Plan tab to generate your week").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    private func nextSessionLabel(_ s: PlannedWorkout) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(s.date)    { return "Next session · today" }
        if cal.isDateInTomorrow(s.date) { return "Next session · tomorrow" }
        return "Next session · \(s.date.formatted(.dateTime.weekday(.wide)))"
    }

    private func whyThis(_ s: PlannedWorkout) -> String {
        if let w = s.why, !w.isEmpty { return "Why this: \(w)" }
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
