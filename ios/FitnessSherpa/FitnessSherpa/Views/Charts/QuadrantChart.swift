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
            HStack(spacing: 6) {
                // strength axis — spans the chart height: WEAKER pinned to the bottom, STRONGER to the top.
                // Built horizontally across a width = the chart's height, then rotated so the ends land
                // on the top and bottom edges.
                GeometryReader { g in
                    // built horizontally (WEAKER → STRONGER), rotated so it runs bottom → top
                    axisBar("WEAKER", "STRONGER")
                        .frame(width: g.size.height)
                        .rotationEffect(.degrees(-90))
                        .frame(width: g.size.width, height: g.size.height)
                }
                .frame(width: 22)

                chart
            }
            // run axis — SLOWER pinned left, FASTER pinned right
            axisBar("SLOWER", "FASTER").padding(.leading, 28)
            Text("Top-right is the complete athlete — your corner names your limiter.")
                .font(.system(size: 10)).foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 1)
        }
    }

    /// A directional axis bar: solid dark background, white labels + arrow.
    private func axisBar(_ from: String, _ to: String) -> some View {
        HStack(spacing: 6) {
            Text(from)
            Rectangle().fill(.white.opacity(0.7)).frame(height: 1)
            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 6))
            Text(to)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(1).foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                    // negative→positive gradient (darkened): weak+slow (bottom-left, red) →
                    // ideal (top-right, green); dark enough that labels + marker stay readable
                    LinearGradient(colors: [Color(hex: 0x9B1F12), Color(hex: 0xA8590C), Color(hex: 0x12833E)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing)
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
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.surfaceLine, lineWidth: 1))
            }
            .aspectRatio(1, contentMode: .fit)
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
                .foregroundStyle(Palette.mint)
        }
    }
}
