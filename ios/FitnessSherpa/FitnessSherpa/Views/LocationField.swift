//  LocationField.swift
//  Fitness Sherpa
//
//  A text field with city/location type-ahead (MapKit MKLocalSearchCompleter). Used for home + race
//  location so the athlete picks a real place instead of free-typing. Dark-styled for onboarding.

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

struct LocationField: View {
    let placeholder: String
    @Binding var text: String

    @StateObject private var search = LocationSearch()
    @FocusState private var focused: Bool
    @State private var suppress = false          // skip a search after we set the text from a pick

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text)
                .foregroundStyle(Palette.text)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
                .onChange(of: text) { _, newValue in
                    if suppress { suppress = false; return }
                    search.update(newValue)
                }
                .onChange(of: focused) { _, isFocused in if !isFocused { search.clear() } }

            if focused, !search.results.isEmpty {
                let shown = Array(search.results.prefix(5))
                VStack(spacing: 0) {
                    ForEach(shown, id: \.self) { r in
                        Button {
                            suppress = true
                            text = label(for: r)
                            search.clear()
                            focused = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle").foregroundStyle(Palette.textMuted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.subheadline).foregroundStyle(Palette.text)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle).font(.caption2).foregroundStyle(Palette.textMuted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if r != shown.last { Divider().overlay(Palette.surfaceLine) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
            }
        }
    }

    /// "City, Region" — keep the city + the first subtitle token (state/region), drop country noise.
    private func label(for r: MKLocalSearchCompletion) -> String {
        let region = r.subtitle.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        if let region, !region.isEmpty, !region.lowercased().contains("united states") {
            return "\(r.title), \(region)"
        }
        return r.title
    }
}
