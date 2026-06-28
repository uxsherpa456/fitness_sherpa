//  CoachView.swift
//  Fitness Sherpa
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

    @State private var current: Conversation?
    @State private var input = ""
    @State private var streaming = ""
    @State private var sending = false
    @State private var showingHistory = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(310, geo.size.width * 0.86)
            HStack(spacing: 0) {
                mainContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay {
                        if showingHistory {
                            Color.black.opacity(0.3)
                                .contentShape(Rectangle())
                                .onTapGesture { showingHistory = false }
                        }
                    }
                historyDrawer
                    .frame(width: drawerWidth, height: geo.size.height)
            }
            .frame(width: geo.size.width + drawerWidth, alignment: .leading)
            .offset(x: showingHistory ? -drawerWidth : 0)
            .animation(.easeInOut(duration: 0.28), value: showingHistory)
        }
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
                    Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
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
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { if !messages.isEmpty { withAnimation { proxy.scrollTo("bottom") } } }
            .onChange(of: streaming) { if !streaming.isEmpty { proxy.scrollTo("bottom") } }
            .onChange(of: current?.id) {
                if current?.isEmpty ?? true { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                else { proxy.scrollTo("bottom") }
            }
        }
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
        let coachContext = model.coachContext(recentWorkouts: Array(recentSessions.prefix(12)),
                                              plan: Array(upcoming.prefix(10)))

        sending = true
        streaming = ""
        Task {
            do {
                for try await event in CoachClient.stream(messages: payload, context: coachContext) {
                    switch event {
                    case .text(let t): streaming += t
                    case .note(let n): flush(into: convo); append(.note, n, to: convo)
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

    private func flush(into convo: Conversation) {
        guard !streaming.isEmpty else { return }
        append(.assistant, streaming, to: convo)
        streaming = ""
    }

    private func styledMarkdown(_ s: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
        let bold = attr.runs.compactMap { run in
            (run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false) ? run.range : nil
        }
        for range in bold { attr[range].foregroundColor = Palette.mint }
        return attr
    }
}

