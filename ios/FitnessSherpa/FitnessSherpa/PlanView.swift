//  PlanView.swift
//  Fitness Sherpa
//
//  The training timeline (Becoming spec): one continuous chronological list — past above, today
//  pinned as the anchor, recommended future below. Past sessions come from our durable store
//  (HealthKit reconciled in, manual entries + edits preserved). Every past row is editable.

import SwiftUI
import SwiftData

struct PlanView: View {
    let model: AppModel

    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.date, order: .forward) private var sessions: [TrainingSession]

    @State private var loadError: String?
    @State private var loaded = false
    @State private var didScroll = false
    @State private var editing: TrainingSession?
    @State private var showingAdd = false
    @State private var conflict: TrainingSession?

    private let cal = Calendar.current
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let loadError { Text("⚠ \(loadError)").font(.caption).foregroundStyle(Palette.red) }
                        ForEach(entries) { entry($0) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .background(Palette.bg)
                .refreshable { await load() }
                .onChange(of: sessions.count) { if !didScroll { proxy.scrollTo("today", anchor: .top); didScroll = true } }
                .task {
                    await load()
                    proxy.scrollTo("today", anchor: .top)
                }
            }
            .appBar(model)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { SessionEditView(session: $0) }
            .sheet(isPresented: $showingAdd) { SessionEditView(session: nil) }
            .confirmationDialog("Apple Health has updated values for this session.",
                                isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
                                presenting: conflict) { s in
                Button("Use Apple Health's data") { s.resolveUseHealthKit(); try? context.save(); conflict = nil }
                Button("Keep mine", role: .cancel) { s.resolveKeepMine(); try? context.save(); conflict = nil }
            }
        }
    }

    // MARK: - Timeline entries

    private enum Entry: Identifiable {
        case month(String)
        case actual(TrainingSession)
        case lastLogged(Date)
        case planBegins
        case planned(PlannedSession, Date, today: Bool)

        var id: String {
            switch self {
            case .month(let m): return "m-\(m)"
            case .actual(let s): return "a-\(s.id)"
            case .lastLogged: return "lastlogged"
            case .planBegins: return "planbegins"
            case .planned(_, let d, let t): return t ? "today" : "p-\(d.timeIntervalSince1970)"
            }
        }
    }

    private func monthKey(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year()).uppercased()
    }

    /// Chronological timeline: actuals (time-ordered, month-bucketed) → LAST LOGGED → PLAN → future.
    private var entries: [Entry] {
        var out: [Entry] = []
        var lastMonth = ""

        let actuals = sessions.sorted { $0.date < $1.date }   // ascending = time-of-day order within a day
        for s in actuals {
            let m = monthKey(s.date)
            if m != lastMonth { out.append(.month(m)); lastMonth = m }
            out.append(.actual(s))
        }
        if let last = actuals.last { out.append(.lastLogged(last.date)) }

        out.append(.planBegins)
        let week = PlanEngine.recommendedWeek(for: model.diagnosis?.profile)
        for (i, p) in week.enumerated() {
            let date = cal.date(byAdding: .day, value: i, to: todayStart) ?? todayStart
            let m = monthKey(date)
            if m != lastMonth { out.append(.month(m)); lastMonth = m }
            out.append(.planned(p, date, today: i == 0))
        }
        return out
    }

    @ViewBuilder private func entry(_ e: Entry) -> some View {
        switch e {
        case .month(let m): monthHeader(m)
        case .actual(let s): actualRow(s)
        case .lastLogged(let d): divider("LAST LOGGED · \(d.formatted(.relative(presentation: .named)))", color: Palette.textFaint)
        case .planBegins: divider("PLAN", color: Palette.mint)
        case .planned(let p, let date, let today): plannedRow(p, date: date, today: today)
        }
    }

    private func monthHeader(_ m: String) -> some View {
        Text(m)
            .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.5)
            .foregroundStyle(Palette.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14).padding(.bottom, 2)
    }

    private func divider(_ label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                .foregroundStyle(color).fixedSize()
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        do {
            try await HealthData.requestAuthorization()
            let workouts = try await HealthData.recentWorkouts(days: 365)
            TrainingSession.reconcile(workouts, context: context)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        loaded = true
    }

    // MARK: - Rows

    private func dateColumn(_ date: Date, highlight: Bool) -> some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.textFaint)
            Text(date.formatted(.dateTime.day()))
                .font(.headline).foregroundStyle(highlight ? Palette.mint : Palette.text)
        }
        .frame(width: 36)
    }

    private func actualRow(_ s: TrainingSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            dateColumn(s.date, highlight: false)
            Button {
                editing = s
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: s.cat.icon).font(.caption).foregroundStyle(s.cat.color)
                        Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        sourceChip(s)
                    }
                    Text(detail(s)).font(.caption).foregroundStyle(Palette.textMuted)
                    if s.hasHKConflict {
                        Button { conflict = s } label: {
                            Label("Apple Health update — review", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(Palette.yellow)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .leading) {
                    Rectangle().fill(s.cat.color).frame(width: 3).frame(maxHeight: .infinity)
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func plannedRow(_ p: PlannedSession, date: Date, today: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            dateColumn(date, highlight: today)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.type).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(p.category.color)
                    Spacer()
                    if today {
                        Text("TODAY").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.mint, in: Capsule())
                    }
                }
                Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                Text(p.meta).font(.caption).foregroundStyle(Palette.textMuted)
                if let why = p.why { Text(why).font(.caption2).foregroundStyle(Palette.textFaint) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(today ? Palette.mint.opacity(0.10) : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(today ? Palette.mint.opacity(0.5) : .clear, lineWidth: 1))
            .overlay(alignment: .leading) {
                Rectangle().fill(p.category.color).frame(width: 3).frame(maxHeight: .infinity).clipShape(Capsule())
            }
        }
    }

    private func sourceChip(_ s: TrainingSession) -> some View {
        let text = s.isManual ? "MANUAL" : (s.isEdited ? "EDITED" : "HEALTH")
        return Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.textFaint)
    }

    private func detail(_ s: TrainingSession) -> String {
        var parts: [String] = []
        if let km = s.distanceKm, km > 0 { parts.append(String(format: "%.1f km", km)) }
        parts.append("\(s.durationMin) min")
        if let kcal = s.caloriesKcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        if let hr = s.avgHR { parts.append("\(hr) bpm avg") }
        if let mx = s.maxHR { parts.append("\(mx) max") }
        if let rpe = s.rpe { parts.append("RPE \(rpe)") }
        return parts.joined(separator: " · ")
    }
}
