//  DiagnosisGuideView.swift
//  Ravns
//
//  A reference page (from the hamburger menu) explaining the four athlete profiles on the strength ×
//  running quadrant — what limits each, and the training week each one gets. Static guide; the
//  athlete's own live diagnosis lives on the Athlete tab.

import SwiftUI

struct DiagnosisGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Every athlete lands in one of four profiles on the strength × running map. Your profile names your limiter — and the plan attacks it. Re-diagnose anytime on the Athlete tab.")
                        .font(.subheadline).foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(AthleteProfile.allCases, id: \.self) { profileCard($0) }
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("The four profiles").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func profileCard(_ p: AthleteProfile) -> some View {
        Card(style: .dark) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    miniQuad(p)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.title).font(.headline).foregroundStyle(Palette.text)
                        Text("Limiter: \(p.limiter)").font(.caption).foregroundStyle(Palette.mint)
                    }
                    Spacer(minLength: 0)
                }
                Text(p.focus).font(.subheadline).foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Palette.surfaceLine).frame(height: 1)
                Text("A TYPICAL WEEK")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Palette.textFaint)
                VStack(spacing: 8) {
                    ForEach(PlanEngine.recommendedWeek(for: p)) { sessionRow($0) }
                }
            }
        }
    }

    private func sessionRow(_ s: PlannedSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(s.dow)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.textFaint).frame(width: 34, alignment: .leading)
            Image(systemName: s.category.icon)
                .font(.caption).foregroundStyle(s.category.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.subheadline).foregroundStyle(Palette.text)
                if let why = s.why {
                    Text(why).font(.caption2).foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 2×2 mini-quadrant with this profile's cell lit (top = stronger, right = faster).
    private func miniQuad(_ p: AthleteProfile) -> some View {
        let active: (col: Int, row: Int) = {
            switch p {
            case .heavySlowStrong:  return (0, 0)   // strong (top) · slow (left)
            case .goodAtEverything: return (1, 0)   // strong · fast
            case .weakAtEverything: return (0, 1)   // weak (bottom) · slow
            case .lightFastWeak:    return (1, 1)   // weak · fast
            }
        }()
        return VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(col == active.col && row == active.row ? Palette.mint : Palette.surfaceLine)
                            .frame(width: 13, height: 13)
                    }
                }
            }
        }
    }
}
