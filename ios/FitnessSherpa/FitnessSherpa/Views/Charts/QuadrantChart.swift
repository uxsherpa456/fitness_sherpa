//  QuadrantChart.swift
//  Fitness Sherpa
//
//  The strength × running quadrant, ported from prototype/index.html (.qchart). Places the athlete
//  with a glowing "YOU" marker at (markerX, markerY) — both 0…1 — and highlights the active profile
//  cell. Y axis = strength (top = strong), X axis = running / power-to-weight (right = light & fast).

import SwiftUI

struct QuadrantChart: View {
    let markerX: Double          // 0…1, left → right
    let markerY: Double          // 0…1, top → bottom
    let active: AthleteProfile?

    private struct Cell {
        let profile: AthleteProfile
        let title: String
        let limiter: String
        let cx: Double            // quadrant-center fraction
        let cy: Double
        let inner: Alignment
        let textAlign: TextAlignment
    }

    private let cells: [Cell] = [
        Cell(profile: .heavySlowStrong, title: "Heavy & slow,\nstrong enough", limiter: "limiter: weight + pace",
             cx: 0.25, cy: 0.25, inner: .topLeading, textAlign: .leading),
        Cell(profile: .goodAtEverything, title: "Good at\neverything", limiter: "limiter: integration",
             cx: 0.75, cy: 0.25, inner: .topTrailing, textAlign: .trailing),
        Cell(profile: .weakAtEverything, title: "Weak at\neverything", limiter: "limiter: general base",
             cx: 0.25, cy: 0.75, inner: .bottomLeading, textAlign: .leading),
        Cell(profile: .lightFastWeak, title: "Light & fast,\nnot strong", limiter: "limiter: station capacity",
             cx: 0.75, cy: 0.75, inner: .bottomTrailing, textAlign: .trailing),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            axisLabel("STRENGTH / STATIONS  ·  stronger ↑")
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    // the ideal corner — a faint glow in the top-right (strong + fast)
                    RadialGradient(colors: [Palette.mint.opacity(0.12), .clear], center: .topTrailing,
                                   startRadius: 0, endRadius: w * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    // active quadrant highlight
                    if let active, let c = cells.first(where: { $0.profile == active }) {
                        Rectangle().fill(Palette.mint.opacity(0.10))
                            .frame(width: w / 2, height: h / 2)
                            .position(x: c.cx * w, y: c.cy * h)
                    }
                    // center cross
                    Rectangle().fill(Palette.surfaceLine).frame(width: 1, height: h - 16).position(x: w / 2, y: h / 2)
                    Rectangle().fill(Palette.surfaceLine).frame(width: w - 16, height: 1).position(x: w / 2, y: h / 2)
                    // corner labels
                    ForEach(cells.indices, id: \.self) { i in
                        cellLabel(cells[i])
                            .frame(width: w / 2, height: h / 2, alignment: cells[i].inner)
                            .position(x: cells[i].cx * w, y: cells[i].cy * h)
                    }
                    // YOU marker
                    marker.position(x: markerX * w, y: markerY * h)
                }
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.surfaceLine, lineWidth: 1))
            }
            .aspectRatio(1, contentMode: .fit)
            // run axis — both ends, in plain language
            HStack {
                axisLabel("← heavier · slower")
                Spacer()
                axisLabel("faster · lighter →")
            }
            Text("Up = stronger · right = faster. Top-right is the complete athlete; your corner names your limiter.")
                .font(.system(size: 10)).foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 1)
        }
    }

    private func axisLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.5).foregroundStyle(Palette.textFaint)
    }

    private func cellLabel(_ c: Cell) -> some View {
        let isActive = c.profile == active
        let isIdeal = c.profile == .goodAtEverything
        return VStack(alignment: c.textAlign == .leading ? .leading : .trailing, spacing: 3) {
            if isIdeal {
                Text("✦ IDEAL")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Palette.mint.opacity(0.8))
            }
            Text(c.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? Palette.mint : Palette.text)
            Text(c.limiter)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textFaint)
        }
        .multilineTextAlignment(c.textAlign)
        .padding(11)
    }

    private var marker: some View {
        VStack(spacing: 4) {
            Circle().fill(Palette.mint).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Palette.mint.opacity(0.18), lineWidth: 5))
                .shadow(color: Palette.mint.opacity(0.55), radius: 8)
            Text("YOU")
                .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Palette.mint, in: Capsule())
        }
    }
}
