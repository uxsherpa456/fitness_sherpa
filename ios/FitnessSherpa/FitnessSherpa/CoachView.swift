//  CoachView.swift
//  Fitness Sherpa
//
//  The AI Coach tab: an evidence-gated chat over the deployed Edge Function. Every turn ships the
//  freshness-stamped snapshot (AppModel.coachContext) so the coach reasons off current, real data;
//  agent actions (re-diagnosis, fuel, goals) surface inline as notes.

import SwiftUI
import SwiftData

struct CoachView: View {
    let model: AppModel

    @Query(sort: \TrainingSession.date, order: .reverse) private var recentSessions: [TrainingSession]
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var streaming = ""        // current assistant partial
    @State private var sending = false
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        enum Role { case user, assistant, note }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                freshnessBar
                chatScroll
                inputBar
            }
            .background(Palette.bg)
            .navigationTitle("AI Coach").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.bg, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
        }
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
                    : "Stale data — coach will flag it: \(model.reading?.staleMetrics.joined(separator: ", ") ?? "")"))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Palette.surface)
    }

    // MARK: - Chat

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty && streaming.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { bubble($0) }
                    if !streaming.isEmpty {
                        bubble(ChatMessage(role: .assistant, text: streaming))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: streaming) { proxy.scrollTo("bottom") }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask your coach").font(.headline).foregroundStyle(Palette.text)
            ForEach(starters, id: \.self) { s in
                Button { input = s; send() } label: {
                    Text(s).font(.footnote).foregroundStyle(Palette.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.surface, in: .rect(cornerRadius: 12))
                }
                .disabled(sending)
            }
        }
        .padding(.top, 24)
    }

    private let starters = [
        "Am I on track for a 1:10 finish?",
        "What should I eat today around the session?",
        "What would my profile be at 195 lb?",
    ]

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .font(.subheadline).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Palette.mint, in: .rect(cornerRadius: 16))
            }
        case .assistant:
            HStack {
                Text(styledMarkdown(m.text))
                    .font(.subheadline).foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Palette.surface, in: .rect(cornerRadius: 16))
                Spacer(minLength: 40)
            }
        case .note:
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").font(.caption2)
                Text(m.text).font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
            }
            .foregroundStyle(Palette.textFaint)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message the coach…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.surface2, in: Capsule())
                .foregroundStyle(Palette.text)
                .focused($inputFocused)
                .disabled(sending)
            Button(action: send) {
                Image(systemName: sending ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Palette.mint : Palette.textFaint)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.bg)
    }

    private var canSend: Bool { !sending && !input.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Send

    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: text))

        // Conversation payload: user/assistant only, content as a string.
        let convo: [[String: String]] = messages.filter { $0.role != .note }.map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        let context = model.coachContext(recentWorkouts: Array(recentSessions.prefix(12)))

        sending = true
        streaming = ""
        Task {
            do {
                for try await event in CoachClient.stream(messages: convo, context: context) {
                    switch event {
                    case .text(let t):
                        streaming += t
                    case .note(let n):
                        flush()
                        messages.append(ChatMessage(role: .note, text: n))
                    case .done:
                        flush()
                    }
                }
                flush()
            } catch {
                flush()
                messages.append(ChatMessage(role: .assistant, text: "⚠ \(error.localizedDescription)"))
            }
            sending = false
        }
    }

    /// Render markdown with **bold** runs colored mint, matching the web prototype.
    private func styledMarkdown(_ s: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
        let boldRanges = attr.runs.compactMap { run in
            (run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false) ? run.range : nil
        }
        for range in boldRanges { attr[range].foregroundColor = Palette.mint }
        return attr
    }

    /// Commit any buffered assistant text as a finalized message (keeps note ordering correct).
    private func flush() {
        guard !streaming.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, text: streaming))
        streaming = ""
    }
}
