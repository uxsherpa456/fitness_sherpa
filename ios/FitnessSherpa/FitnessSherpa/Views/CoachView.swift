//  CoachView.swift
//  Ravns
//
//  The AI Coach tab: an evidence-gated chat over the deployed Edge Function, with persistent
//  conversation history (SwiftData). A list icon (top-left) opens past chats; the pencil starts a
//  new one — like Claude. Every turn ships the freshness-stamped snapshot + recent training load.

import SwiftUI
import SwiftData

struct CoachView: View {
    let model: AppModel

    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \TrainingSession.date, order: .reverse) private var recentSessions: [TrainingSession]
    @Query(sort: \PlannedWorkout.date, order: .forward) private var planned: [PlannedWorkout]
    @Query(sort: \DailyReadiness.day, order: .reverse) private var readinessLog: [DailyReadiness]

    @State private var current: Conversation?
    @State private var input = ""
    @State private var streaming = ""
    @State private var sending = false
    @State private var showingHistory = false
    @State private var atBottom = true
    @FocusState private var inputFocused: Bool

    private let drawerWidth: CGFloat = 300

    // A slide-over history drawer (overlay, not a GeometryReader push) so it never fights the keyboard:
    // a root GeometryReader around a keyboard-bearing screen blanks/jumps as the keyboard resizes it.
    var body: some View {
        mainContent
            .overlay {
                if showingHistory {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showingHistory = false }
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .trailing) {
                if showingHistory {
                    historyDrawer
                        .frame(width: drawerWidth)
                        .background(Palette.bg)
                        .shadow(color: .black.opacity(0.4), radius: 14, x: -6)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: showingHistory)
    }

    private var mainContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                freshnessBar
                chatScroll
                inputBar
            }
            .background(Palette.bg)
            .appBar(model)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startNewChat() } label: { Image(systemName: "square.and.pencil") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { inputFocused = false; showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
            }
            .task {
                if current == nil {
                    // Clean up empty leftovers, then resume the last real conversation.
                    for c in conversations where c.isEmpty { context.delete(c) }
                    try? context.save()
                    current = conversations.first(where: { !$0.isEmpty }) ?? makeConversation()
                }
            }
        }
    }

    // MARK: - History drawer (pushes the chat to the right, like Claude)

    private var historyDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chats").font(.headline).foregroundStyle(Palette.text)
                Spacer()
                Button { startNewChat(); showingHistory = false } label: {
                    Image(systemName: "square.and.pencil").foregroundStyle(Palette.mint)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            Rectangle().fill(Palette.surfaceLine).frame(height: 1)
            List {
                ForEach(conversations.filter { !$0.isEmpty }) { c in
                    Button { selectConversation(c) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title).lineLimit(1)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(c.id == current?.id ? Palette.mint : Palette.text)
                            Text(c.updatedAt.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(Palette.textFaint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(c.id == current?.id ? Palette.surface : Palette.bg)
                    .listRowSeparatorTint(Palette.surfaceLine)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { deleteConversation(c) } label: {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.black)
                        }
                        .tint(Palette.mint)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
        .ignoresSafeArea(edges: .bottom)
    }

    private func selectConversation(_ c: Conversation) {
        current = c
        streaming = ""
        showingHistory = false
    }

    private func deleteConversation(_ c: Conversation) {
        if c.id == current?.id {
            current = conversations.first(where: { !$0.isEmpty && $0.id != c.id }) ?? makeConversation()
        }
        context.delete(c); try? context.save()
    }

    // MARK: - Freshness bar

    private var freshnessBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.reading?.readinessFresh == false ? Palette.yellow : Palette.green)
                .frame(width: 7, height: 7)
            Text(model.reading == nil
                 ? "Loading today's data…"
                 : (model.reading?.readinessFresh == true
                    ? "Primed with today's data"
                    : "Stale data — coach will flag it"))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Palette.surface)
    }

    // MARK: - Chat

    private var messages: [ChatMessageRecord] { current?.sortedMessages ?? [] }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    Color.clear.frame(height: 0).id("top")
                    if messages.isEmpty && streaming.isEmpty { emptyState }
                    ForEach(messages) { bubble($0) }
                    if !streaming.isEmpty {
                        assistantBubble(streaming)
                    } else if sending {
                        thinkingBubble.transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && !messages.isEmpty { scrollToLatest(proxy) }
            }
            .animation(.easeInOut(duration: 0.2), value: atBottom)
            .onChange(of: messages.count) { if !messages.isEmpty { withAnimation { proxy.scrollTo("bottom") } } }
            .onChange(of: sending) { if sending { withAnimation { proxy.scrollTo("bottom") } } }
            .onChange(of: streaming) { if !streaming.isEmpty { proxy.scrollTo("bottom") } }
            .onChange(of: current?.id) {
                if current?.isEmpty ?? true { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                else { proxy.scrollTo("bottom") }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo("bottom") }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 36, height: 36)
                .background(Palette.surface2, in: Circle())
                .overlay(Circle().stroke(Palette.surfaceLine, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .padding(.trailing, 14).padding(.bottom, 10)
        .transition(.scale.combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask your coach").font(.headline).foregroundStyle(Palette.text)
            ForEach(starters, id: \.self) { s in
                Button { input = s; send() } label: {
                    Text(s).font(.footnote).foregroundStyle(Palette.mint)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.surface, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(sending)
            }
        }
        .padding(.top, 24)
    }

    private let starters = [
        "Am I on track for a 1:10 finish?",
        "Given my recent training, am I recovered enough to push today?",
        "What should I eat today around the session?",
    ]

    @ViewBuilder private func bubble(_ m: ChatMessageRecord) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text).font(.subheadline).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Palette.mint, in: .rect(cornerRadius: 16))
            }
        case .assistant:
            assistantBubble(m.text)
        case .note:
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").font(.caption2)
                Text(m.text).font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
            }
            .foregroundStyle(Palette.textFaint).padding(.horizontal, 4)
        }
    }

    private func assistantBubble(_ text: String) -> some View {
        HStack {
            Text(styledMarkdown(text)).font(.subheadline).foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.surface, in: .rect(cornerRadius: 16))
            Spacer(minLength: 40)
        }
    }

    /// Shown after you send, before the first streamed token — Hugin "thinking".
    private var thinkingBubble: some View {
        HStack {
            TypingDots()
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Palette.surface, in: .rect(cornerRadius: 16))
            Spacer(minLength: 40)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message the coach…", text: $input, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.surface2, in: Capsule())
                .foregroundStyle(Palette.text)
                .focused($inputFocused)
                .disabled(sending)
            Button(action: send) {
                Image(systemName: sending ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2).foregroundStyle(canSend ? Palette.mint : Palette.textFaint)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.bg)
    }

    private var canSend: Bool { !sending && !input.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Conversation management

    private func makeConversation() -> Conversation {
        let c = Conversation()
        context.insert(c)
        try? context.save()
        return c
    }

    private func startNewChat() {
        inputFocused = false
        streaming = ""
        let previous = current
        current = makeConversation()
        // Discard the prior chat only if it was empty, so blanks don't pile up.
        if let previous, previous.isEmpty {
            context.delete(previous); try? context.save()
        }
    }

    // MARK: - Send

    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        let convo = current ?? makeConversation()
        current = convo
        input = ""

        let userMsg = ChatMessageRecord(role: .user, text: text, order: convo.nextOrder)
        userMsg.conversation = convo
        context.insert(userMsg)
        if convo.title == "New chat" { convo.title = String(text.prefix(48)) }
        convo.updatedAt = Date()
        try? context.save()

        let payload: [[String: String]] = convo.sortedMessages
            .filter { $0.role != .note }
            .map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let upcoming = planned.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
        let coachContext = model.coachContext(recentWorkouts: Array(recentSessions.prefix(40)),
                                              plan: Array(upcoming.prefix(10)),
                                              readinessLog: Array(readinessLog.prefix(30)))

        sending = true
        streaming = ""
        Task {
            do {
                for try await event in CoachClient.stream(messages: payload, context: coachContext) {
                    switch event {
                    case .text(let t): streaming += t
                    case .note(let n): flush(into: convo); append(.note, n, to: convo)
                    case .plan(let changes, let summary):
                        flush(into: convo)
                        applyPlanChanges(changes)
                        append(.note, "Updated plan" + (summary.map { ": \($0)" } ?? ""), to: convo)
                    case .goals(let items):
                        flush(into: convo)
                        applyGoalChanges(items)
                        append(.note, "Updated goal targets", to: convo)
                    case .done: flush(into: convo)
                    }
                }
                flush(into: convo)
            } catch {
                flush(into: convo)
                append(.assistant, "⚠ \(error.localizedDescription)", to: convo)
            }
            sending = false
        }
    }

    private func append(_ role: ChatRole, _ text: String, to convo: Conversation) {
        let m = ChatMessageRecord(role: role, text: text, order: convo.nextOrder)
        m.conversation = convo
        context.insert(m)
        convo.updatedAt = Date()
        try? context.save()
    }

    /// Apply coach-proposed goal targets to the athlete's focus-metric goals.
    private func applyGoalChanges(_ items: [[String: Any]]) {
        for it in items {
            guard let key = it["key"] as? String,
                  let target = it["target"] as? String,
                  let i = model.goals.firstIndex(where: { $0.key == key }) else { continue }
            model.goals[i].goal = model.goals[i].isTime ? .text(target)
                : .number(Double(target) ?? (model.goals[i].goal?.asDouble ?? 0))
        }
        model.saveGoals()
        model.pushToCloud()
    }

    /// Apply coach-proposed plan edits to the PlannedWorkout store (tagged `coach`).
    private func applyPlanChanges(_ changes: [[String: Any]]) {
        let cal = Calendar.current
        for c in changes {
            guard let action = c["action"] as? String,
                  let dateStr = c["date"] as? String,
                  let date = DateFormatters.ymd.date(from: dateStr) else { continue }
            let day = cal.startOfDay(for: date)
            let existing = planned.first { cal.isDate($0.date, inSameDayAs: day) }

            switch action {
            case "remove":
                if let e = existing { context.delete(e) }
            case "complete":
                if let e = existing { e.completed = true; e.updatedAt = Date() }
            case "upsert":
                let p = existing ?? PlannedWorkout(date: day, category: .run, type: "", name: "",
                                                   meta: "", intent: .easy, source: .coach)
                if existing == nil { context.insert(p) }
                if let v = c["category"] as? String, SessionCategory(rawValue: v) != nil { p.categoryRaw = v }
                if let v = c["type"] as? String { p.type = v }
                if let v = c["name"] as? String { p.name = v }
                if let v = c["meta"] as? String { p.meta = v }
                if let v = c["intent"] as? String { p.intentRaw = v }
                if let v = c["target_zone"] as? String { p.targetZone = v }
                if let v = c["stations"] as? String { p.stations = v }
                if let v = c["why"] as? String { p.why = v }
                p.date = day
                p.sourceRaw = PlanSource.coach.rawValue
                p.updatedAt = Date()
            default: break
            }
        }
        try? context.save()
    }

    private func flush(into convo: Conversation) {
        guard !streaming.isEmpty else { return }
        append(.assistant, streaming, to: convo)
        streaming = ""
    }

    // Cache parsed markdown so typing in the input field (which re-renders the view) doesn't re-parse
    // every message bubble on each keystroke. Capped so streaming partials can't grow it unbounded.
    private static var mdCache: [String: AttributedString] = [:]

    private func styledMarkdown(_ s: String) -> AttributedString {
        if let hit = Self.mdCache[s] { return hit }
        var attr = (try? AttributedString(
            markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
        let bold = attr.runs.compactMap { run in
            (run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false) ? run.range : nil
        }
        for range in bold { attr[range].foregroundColor = Palette.mint }
        if Self.mdCache.count > 400 { Self.mdCache.removeAll(keepingCapacity: true) }
        Self.mdCache[s] = attr
        return attr
    }
}

/// Three dots that pulse in sequence — the coach's "thinking" indicator.
private struct TypingDots: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Palette.textMuted)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1 : 0.55)
                    .opacity(animating ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                               value: animating)
            }
        }
        .onAppear { animating = true }
    }
}

