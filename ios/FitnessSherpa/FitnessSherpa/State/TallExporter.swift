//  TallExporter.swift
//  Ravns
//
//  Full-length screen capture for the web prototype. Renders a tab's bare scroll content in a REAL
//  hosted UIView (UIHostingController added off-screen to the key window), so live SwiftData / @Query
//  / Swift Charts all render — unlike the detached ImageRenderer, which can't. Captures the whole
//  intrinsic height via drawHierarchy and writes PNGs to Documents/export (pulled off with simctl).

import SwiftUI
import SwiftData
import UIKit

@MainActor
enum TallExporter {
    private static let width: CGFloat = 393       // iPhone logical width

    /// Host the bare tab content at its full intrinsic height in a real (off-screen) window, then
    /// render its layer tree — layer.render avoids drawHierarchy's "can't snapshot" placeholder that
    /// GeometryReader/Charts trigger.
    static func snapshot<V: View>(_ content: V, container: ModelContainer) async -> UIImage? {
        let root = content
            .frame(width: width)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = UIColor(Palette.bg)

        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return nil }

        let fit = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: max(fit.height, 1))
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.alpha = 0
        window.addSubview(host.view)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 900_000_000)   // let .task-loaded charts settle

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        host.view.removeFromSuperview()
        return image
    }

    static func exportTabs(model: AppModel, container: ModelContainer) async {
        let dir = URL.documentsDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ img: UIImage?) {
            if let d = img?.pngData() { try? d.write(to: dir.appendingPathComponent("\(name).png")) }
        }
        save("today", await snapshot(TodayView(model: model, exportContent: true), container: container))
        save("athlete", await snapshot(AthleteView(model: model, exportContent: true), container: container))
        save("plan", await snapshot(PlanView(model: model, exportContent: true), container: container))
    }
}
