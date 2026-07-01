//  Theme.swift
//  Ravns
//
//  Design tokens + reusable card chrome, ported from prototype/index.html (:root).
//  Design language: dark canvas + mint accent; cards use a flat left edge with a 3px accent
//  stripe and a rounded right edge; monospace for technical labels.

import SwiftUI

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Palette {
    static let bg          = Color(hex: 0x0E0F11)
    static let surface     = Color(hex: 0x1A1B1E)
    static let surface2    = Color(hex: 0x232427)
    static let surfaceLine = Color(hex: 0x2A2C30)
    static let mint        = Color(hex: 0xC7F0E3)
    static let sand        = Color(hex: 0xEFEEE9)
    static let ink         = Color(hex: 0x0E0F11)
    static let inkSoft     = Color(hex: 0x44474C)
    static let text        = Color(hex: 0xF4F5F4)
    static let textMuted   = Color(hex: 0x8A8E95)
    static let textFaint   = Color(hex: 0x5A5E65)
    static let green       = Color(hex: 0x7CE3A2)
    static let yellow      = Color(hex: 0xF2D484)
    static let orange      = Color(hex: 0xF2B27A)
    static let red         = Color(hex: 0xF0917B)
}

/// A small uppercased technical label (monospace), like the prototype's `.module-label`.
struct ModuleLabel: View {
    let text: String
    var onLight = false
    var tint: Color? = nil
    init(_ text: String, onLight: Bool = false, tint: Color? = nil) {
        self.text = text; self.onLight = onLight; self.tint = tint
    }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(tint ?? (onLight ? Palette.inkSoft : Palette.textFaint))
    }
}

/// The card convention: flat left edge + 3px accent stripe, rounded right edge.
struct Card<Content: View>: View {
    /// `tinted` paints a custom background (dark ink text + translucent stripe), like `mint`.
    enum Style { case dark, mint, light, ai, tinted(Color) }
    var style: Style = .dark
    @ViewBuilder var content: () -> Content

    private var onLightBackground: Bool {
        switch style { case .mint, .light, .tinted: return true; default: return false }
    }
    private var background: AnyShapeStyle {
        switch style {
        case .dark:          return AnyShapeStyle(Palette.surface)
        case .mint:          return AnyShapeStyle(Palette.mint)
        case .light:         return AnyShapeStyle(Palette.sand)
        case .tinted(let c): return AnyShapeStyle(c)
        case .ai:            return AnyShapeStyle(LinearGradient(
            colors: [Color(hex: 0x1F2A27), Palette.surface],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    private var foreground: Color { onLightBackground ? Palette.ink : Palette.text }
    private var stripe: Color { onLightBackground ? Palette.ink.opacity(0.18) : Palette.mint }
    private var shape: UnevenRoundedRectangle {
        .rect(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 22, topTrailingRadius: 22)
    }
    @ViewBuilder private var aiStroke: some View {
        if case .ai = style { shape.stroke(Color(hex: 0x28403A), lineWidth: 1) }
    }

    var body: some View {
        content()
            .foregroundStyle(foreground)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: shape)
            .overlay(alignment: .leading) {
                Rectangle().fill(stripe).frame(width: 3)
                    .clipShape(shape)
            }
            .overlay(aiStroke)
    }
}

/// Persistent "when was the data last read" indicator shown in each tab's nav bar center.
struct UpdatedIndicator: View {
    let model: AppModel
    var body: some View {
        let dot: Color = model.reading == nil
            ? Palette.textFaint
            : (model.reading?.readinessFresh == true ? Palette.green : Palette.yellow)
        HStack(spacing: 6) {
            if model.loading {
                ProgressView().controlSize(.mini).tint(Palette.textMuted)
            } else {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
        }
    }
    private var text: String {
        if model.loading { return "Updating…" }
        guard let d = model.reading?.queriedAt else { return "No data yet" }
        return "Updated " + d.formatted(.relative(presentation: .named))
    }
}

/// Shared nav-bar chrome: global hamburger (left) + the updated indicator (center), no title.
private struct AppBar: ViewModifier {
    let model: AppModel
    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showingMenu = true } label: { Image(systemName: "line.3.horizontal") }
                }
                ToolbarItem(placement: .principal) { UpdatedIndicator(model: model) }
            }
    }
}

extension View {
    func appBar(_ model: AppModel) -> some View { modifier(AppBar(model: model)) }
}

/// A status pill (dot + label), like the readiness verdict pill.
struct StatusPill: View {
    let label: String
    var dot: Color = Palette.green
    var onLight = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.5)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((onLight ? Palette.ink : Palette.text).opacity(0.08), in: Capsule())
    }
}
