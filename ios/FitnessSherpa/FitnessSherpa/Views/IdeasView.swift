//  IdeasView.swift
//  Ravns
//
//  The in-app view of Hugin's product-idea ledger (behind the hamburger menu). Each idea shows its
//  RAVN ref + build status; tap through for the full spec Hugin wrote and to change the status.

import SwiftUI

struct IdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ideas: [Idea] = []
    @State private var loading = true

    // Hide dropped by default; sort building → queued → built, newest first within each.
    private var visible: [Idea] {
        let order = ["building": 0, "proposed": 1, "built": 2]
        return ideas.filter { $0.status != "dropped" }
            .sorted { (order[$0.status] ?? 3, $1.created ?? .distantPast) < (order[$1.status] ?? 3, $0.created ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && ideas.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visible.isEmpty {
                    ContentUnavailableView("No ideas yet", systemImage: "lightbulb",
                        description: Text("In Coach, talk through an app idea with Hugin, then say “log this idea.”"))
                } else {
                    List {
                        ForEach(visible) { idea in
                            NavigationLink { IdeaDetailView(idea: idea, onChange: { reload() }) } label: { row(idea) }
                                .listRowBackground(Palette.bg)
                                .listRowSeparatorTint(Palette.surfaceLine)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background(Palette.bg)
            .navigationTitle("Hugin's ideas").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(idea.ref).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.mint)
                Spacer()
                StatusBadge(status: idea.status)
            }
            Text(idea.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let d = idea.created {
                Text(d.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(Palette.textFaint)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async { ideas = await IdeasClient.list(); loading = false }
    private func reload() { Task { await load() } }
}

/// A colored status pill — gray Queued, amber Building, green Built.
struct StatusBadge: View {
    let status: String
    private var color: Color {
        switch status {
        case "building": return Palette.yellow
        case "built":    return Palette.green
        case "dropped":  return Palette.textFaint
        default:         return Palette.textMuted
        }
    }
    var body: some View {
        Text((IdeaStatus(rawValue: status)?.label ?? status).uppercased())
            .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The full idea: the buildable spec Hugin wrote, plus a status changer.
struct IdeaDetailView: View {
    let idea: Idea
    var onChange: () -> Void
    @State private var status: String

    init(idea: Idea, onChange: @escaping () -> Void) {
        self.idea = idea; self.onChange = onChange
        _status = State(initialValue: idea.status)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(idea.ref).font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Palette.mint)
                    Spacer()
                    Menu {
                        ForEach(IdeaStatus.allCases, id: \.self) { s in
                            Button(s.label) { setStatus(s) }
                        }
                    } label: { StatusBadge(status: status) }
                }
                Text(idea.title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                Text(idea.detail).font(.callout).foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("Logged by \(idea.source)" + (idea.created.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""))
                    .font(.caption2).foregroundStyle(Palette.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(Palette.bg)
        .navigationTitle("Idea").navigationBarTitleDisplayMode(.inline)
    }

    private func setStatus(_ s: IdeaStatus) {
        status = s.rawValue
        Task { await IdeasClient.update(ref: idea.ref, status: s); onChange() }
    }
}
