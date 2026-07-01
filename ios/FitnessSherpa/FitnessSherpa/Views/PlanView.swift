//  PlanView.swift
//  Ravns
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
    @Query(sort: \PlannedWorkout.date, order: .forward) private var planned: [PlannedWorkout]

    @State private var loadError: String?
    @State private var didScroll = false
    @State private var editing: TrainingSession?
    @State private var editingPlan: PlannedWorkout?
    @State private var showingAdd = false
    @State private var conflict: TrainingSession?
    @State private var tab: PlanTab = .plan

    private enum PlanTab { case plan, history }

    private let cal = Calendar.current
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    var exportContent = false        // render bare, non-lazy content for full-length image export

    var body: some View {
        if exportContent { exportBody } else { fullBody }
    }

    /// Full-length export: a regular VStack (not Lazy) so every entry lays out and the height is real.
    private var exportBody: some View {
        VStack(spacing: 0) {
            Picker("", selection: .constant(PlanTab.plan)) {
                Text("Plan").tag(PlanTab.plan)
                Text("History").tag(PlanTab.history)
            }
            .pickerStyle(.segmented).tint(Palette.mint)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12).background(Palette.bg)
            VStack(alignment: .leading, spacing: 10) {
                roadmapCard
                ForEach(Array(planEntries.prefix(8))) { entry($0) }   // cap the export so the view height stays under the drawHierarchy render ceiling
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Palette.bg)
        .task {
            PlannedWorkout.seedIfNeeded(profile: model.diagnosis?.profile, settings: model.settings, context: context)
            await load(force: false)
        }
    }

    private var fullBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Plan").tag(PlanTab.plan)
                    Text("History").tag(PlanTab.history)
                }
                .pickerStyle(.segmented).tint(Palette.mint)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
                .background(Palette.bg)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if let loadError { Text("⚠ \(loadError)").font(.caption).foregroundStyle(Palette.red) }
                            if tab == .plan {
                                roadmapCard
                                ForEach(planEntries) { entry($0) }
                            } else if historyEntries.isEmpty {
                                Text("No workouts logged yet — wear your watch or add one with +.")
                                    .font(.footnote).foregroundStyle(Palette.textMuted).padding(.top, 30)
                            } else {
                                ForEach(historyEntries) { entry($0) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .background(Palette.bg)
                    .refreshable { await load(force: true) }
                    .onChange(of: sessions.count) { if !didScroll, tab == .plan { proxy.scrollTo("today", anchor: .top); didScroll = true } }
                    .task {
                        PlannedWorkout.seedIfNeeded(profile: model.diagnosis?.profile, settings: model.settings, context: context)
                        await load(force: false)
                        if tab == .plan { proxy.scrollTo("today", anchor: .top) }
                    }
                }
            }
            .appBar(model)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAdd = true } label: { Label("Add session", systemImage: "plus") }
                        Button {
                            PlannedWorkout.regeneratePlan(profile: model.diagnosis?.profile,
                                                          settings: model.settings, context: context)
                        } label: { Label("Regenerate plan", systemImage: "arrow.triangle.2.circlepath") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $editing) { SessionEditView(session: $0, unitSettings: model.settings) }
            .sheet(item: $editingPlan) { PlannedEditView(plan: $0) }
            .sheet(isPresented: $showingAdd) { SessionEditView(session: nil, unitSettings: model.settings) }
            .confirmationDialog("Apple Health has updated values for this session.",
                                isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
                                presenting: conflict) { s in
                Button("Use Apple Health's data") { s.resolveUseHealthKit(); try? context.save(); conflict = nil }
                Button("Keep mine", role: .cancel) { s.resolveKeepMine(); try? context.save(); conflict = nil }
            }
        }
    }

    // MARK: - Periodization roadmap

    private var roadmap: [PhaseBlock] {
        Periodization.roadmap(daysToRace: model.settings.daysToRace, profile: model.diagnosis?.profile)
    }

    @ViewBuilder private var roadmapCard: some View {
        let blocks = roadmap
        let totalWeeks = max(1, blocks.reduce(0) { $0 + $1.weeks })
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.settings.noRace ? "PHASES TO GOAL DATE" : "PHASES TO RACE DAY")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Palette.textMuted)
                    Spacer()
                    if let n = model.settings.daysToRace, n > 0 {
                        Text("\(n) days").font(.caption.weight(.semibold)).foregroundStyle(Palette.textFaint)
                    }
                }
                // Proportional phase bar.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(blocks) { b in
                            b.phase.color.opacity(b.isCurrent ? 1 : 0.45)
                                .frame(width: max(3, (geo.size.width - CGFloat(blocks.count - 1) * 2) * CGFloat(b.weeks) / CGFloat(totalWeeks)))
                        }
                    }
                }
                .frame(height: 7).clipShape(Capsule())

                ForEach(blocks) { phaseRow($0) }
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 4)
        }
    }

    private func phaseRow(_ b: PhaseBlock) -> some View {
        let (s, e) = b.range(from: todayStart)
        let endShown = cal.date(byAdding: .day, value: -1, to: e) ?? e
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(b.phase.color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(b.phase.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(b.isCurrent ? Palette.text : Palette.textMuted)
                    Text("· \(b.weeks) wk").font(.caption).foregroundStyle(Palette.textFaint)
                    if b.isCurrent {
                        Text("NOW").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(b.phase.color, in: Capsule())
                    }
                    Spacer()
                    Text("\(s.formatted(.dateTime.month(.abbreviated).day())) – \(endShown.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption2.monospaced()).foregroundStyle(Palette.textFaint)
                }
                Text(b.focus).font(.caption).foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(b.isCurrent ? 1 : 0.9)
    }

    // MARK: - Timeline entries

    private enum Entry: Identifiable {
        case month(String)
        case actual(TrainingSession)
        case lastLogged(Date)
        case planBegins
        case planned(PlannedWorkout, today: Bool)

        var id: String {
            switch self {
            case .month(let m): return "m-\(m)"
            case .actual(let s): return "a-\(s.id)"
            case .lastLogged: return "lastlogged"
            case .planBegins: return "planbegins"
            case .planned(let p, let t): return t ? "today" : "p-\(p.id)"
            }
        }
    }

    private func monthKey(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year()).uppercased()
    }

    /// Plan tab: upcoming planned sessions, month-bucketed, today pinned (scroll anchor "today").
    private var planEntries: [Entry] {
        var out: [Entry] = []
        var lastMonth = ""
        let upcoming = planned.filter { $0.date >= todayStart }.sorted { $0.date < $1.date }
        for p in upcoming {
            let m = monthKey(p.date)
            if m != lastMonth { out.append(.month(m)); lastMonth = m }
            out.append(.planned(p, today: cal.isDateInToday(p.date)))
        }
        return out
    }

    /// History tab: logged workouts, most recent first, month-bucketed.
    private var historyEntries: [Entry] {
        var out: [Entry] = []
        var lastMonth = ""
        for s in sessions.sorted(by: { $0.date > $1.date }) {
            let m = monthKey(s.date)
            if m != lastMonth { out.append(.month(m)); lastMonth = m }
            out.append(.actual(s))
        }
        return out
    }

    @ViewBuilder private func entry(_ e: Entry) -> some View {
        switch e {
        case .month(let m): monthHeader(m)
        case .actual(let s): actualRow(s)
        case .lastLogged(let d): divider("LAST LOGGED · \(d.formatted(.relative(presentation: .named)))", color: Palette.textFaint)
        case .planBegins: divider("PLAN", color: Palette.mint)
        case .planned(let p, let today): plannedRow(p, today: today)
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

    private func load(force: Bool) async {
        do {
            try await HealthData.requestAuthorization()
            await model.importWorkouts(context: context, force: force)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
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

    private func plannedRow(_ p: PlannedWorkout, today: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            dateColumn(p.date, highlight: today)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.type).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(p.cat.color)
                    if p.source == .coach {
                        Text("COACH").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundStyle(Palette.mint)
                    }
                    Spacer()
                    if today {
                        Text("TODAY").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.mint, in: Capsule())
                    }
                    Button {
                        p.completed.toggle(); p.updatedAt = Date(); try? context.save()
                    } label: {
                        Image(systemName: p.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.completed ? Palette.green : Palette.textFaint)
                    }
                    .buttonStyle(.plain)
                }
                Text(p.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.completed ? Palette.textMuted : Palette.text)
                    .strikethrough(p.completed)
                Text(p.meta).font(.caption).foregroundStyle(Palette.textMuted)
                if let z = p.targetZone {
                    Text("\(p.intent.label) · \(z)").font(.caption2).foregroundStyle(Palette.textFaint)
                }
                if let why = p.why { Text(why).font(.caption2).foregroundStyle(Palette.textFaint) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(today ? Palette.mint.opacity(0.10) : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(today ? Palette.mint.opacity(0.5) : .clear, lineWidth: 1))
            .overlay(alignment: .leading) {
                Rectangle().fill(p.cat.color).frame(width: 3).frame(maxHeight: .infinity).clipShape(Capsule())
            }
            .contentShape(Rectangle())
            .onTapGesture { editingPlan = p }
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
        if let km = s.distanceKm, km > 0, let d = Units.displayDistance(km: km, model.settings) { parts.append(d) }
        parts.append("\(s.durationMin) min")
        if let kcal = s.caloriesKcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        if let hr = s.avgHR { parts.append("\(hr) bpm avg") }
        if let mx = s.maxHR { parts.append("\(mx) max") }
        if let rpe = s.rpe { parts.append("RPE \(rpe)") }
        return parts.joined(separator: " · ")
    }
}
