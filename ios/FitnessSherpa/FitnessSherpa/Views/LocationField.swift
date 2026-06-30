//  LocationField.swift
//  Fitness Sherpa
//
//  A location picker with city/location type-ahead (MapKit MKLocalSearchCompleter). Used for home +
//  race location so the athlete picks a real place instead of free-typing. Tapping opens a full
//  search sheet — the keyboard sits at the bottom and results fill the space above it, so suggestions
//  are never hidden behind the keyboard.

import SwiftUI
import MapKit
import Combine

final class LocationSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address          // cities / addresses, not POIs
    }
    func update(_ query: String) {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { results = []; return }
        completer.queryFragment = t
    }
    func clear() { results = [] }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }
}

/// "City, Region" — keep the city + the first subtitle token (state/region), drop country noise.
func locationLabel(for r: MKLocalSearchCompletion) -> String {
    let region = r.subtitle.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    if let region, !region.isEmpty, !region.lowercased().contains("united states") {
        return "\(r.title), \(region)"
    }
    return r.title
}

struct LocationField: View {
    let placeholder: String
    @Binding var text: String

    @State private var presenting = false

    var body: some View {
        Button { presenting = true } label: {
            HStack(spacing: 8) {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? Palette.textFaint : Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textMuted)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presenting) { LocationSearchSheet(text: $text) }
    }
}

/// Full-screen search: a focused field at the top, live results filling the sheet above the keyboard.
private struct LocationSearchSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var search = LocationSearch()
    @FocusState private var focused: Bool
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.textMuted)
                    TextField("Start typing a city…", text: $query)
                        .focused($focused).autocorrectionDisabled().submitLabel(.search)
                        .foregroundStyle(Palette.text)
                    if !query.isEmpty {
                        Button { query = ""; search.clear() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textMuted)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
                .padding(.horizontal, 16).padding(.top, 12)
                .onChange(of: query) { _, v in search.update(v) }

                List {
                    ForEach(search.results.prefix(15), id: \.self) { r in
                        Button { text = locationLabel(for: r); dismiss() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle").foregroundStyle(Palette.textMuted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).foregroundStyle(Palette.text)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle).font(.caption).foregroundStyle(Palette.textMuted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Palette.bg)
                        .listRowSeparatorTint(Palette.surfaceLine)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.never)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Search location").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear { query = text; focused = true }
    }
}
