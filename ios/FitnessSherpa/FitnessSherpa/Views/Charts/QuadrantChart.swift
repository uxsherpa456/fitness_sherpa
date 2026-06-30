//  QuadrantChart.swift
//  Fitness Sherpa
//
//  The strength × running quadrant, ported from prototype/index.html (.qchart). Places the athlete
//  with a glowing "YOU" marker at (markerX, markerY) — both 0…1 — and highlights the active profile
//  cell. Y axis = strength (top = strong), X axis = running / power-to-weight (right = light & fast).

import SwiftUI

struct QuadrantChart: View {
    let markerX: Double          // 0…1, left → right — where you ARE
    let markerY: Double          // 0…1, top → bottom — where you ARE
    let active: AthleteProfile?
    var goalX: Double? = nil     // 0…1 — where your GOAL puts you (nil hides the goal marker)
    var goalY: Double? = nil

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
        Cell(profile: .heavySlowStrong, title: "Strong but\nslow", limiter: "limiter: run pace",
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
            Text(goalX != nil
                 ? "◎ GOAL is where your finish target puts you — the mint line is the gap to close."
                 : "Top-right is the complete athlete — your corner names your limiter.")
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
                    LinearGradient(colors: [Color(hex: 0x9B1F12), Color(hex: 0x12833E)],
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
                    // GOAL: the dot, plus the gap line (dashed mint) drawn between the dot CENTERS.
                    if let gx = goalX, let gy = goalY,
                       hypot(gx - markerX, gy - markerY) > 0.02 {
                        Path { p in
                            p.move(to: CGPoint(x: markerX * w, y: markerY * h))
                            p.addLine(to: CGPoint(x: gx * w, y: gy * h))
                        }
                        .stroke(Palette.mint.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                        goalDot.position(x: gx * w, y: gy * h)
                        markerLabel("GOAL").position(x: gx * w, y: gy * h + 15)
                    }
                    // YOU — dot centered on the point, label floated below so the line hits the center.
                    youDot.position(x: markerX * w, y: markerY * h)
                    markerLabel("YOU").position(x: markerX * w, y: markerY * h + 15)
                }
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.surfaceLine, lineWidth: 1))
            }
            .aspectRatio(1, contentMode: .fit)
    }


    private func cellLabel(_ c: Cell) -> some View {
        let isActive = c.profile == active
        return VStack(alignment: c.textAlign == .leading ? .leading : .trailing, spacing: 3) {
            Text(c.title)
                .font(.system(size: 12, weight: isActive ? .heavy : .bold))
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(c.textAlign)
        .padding(11)
    }

    // The filled "YOU" dot — centered exactly on its point so the gap line meets its center.
    private var youDot: some View {
        Circle().fill(Palette.mint).frame(width: 14, height: 14)
            .overlay(Circle().stroke(Palette.mint.opacity(0.18), lineWidth: 5))
            .shadow(color: Palette.mint.opacity(0.55), radius: 8)
    }

    // A hollow target ring — "where your goal puts you."
    private var goalDot: some View {
        Circle().fill(.clear).frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(Circle().fill(.white).frame(width: 4, height: 4))
    }

    private func markerLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1)
            .foregroundStyle(.white)
    }
}
