#if DEBUG
import SwiftUI
import KestrelCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Debug-only visual check: launch with `-snapshot` and the real app walks every function with
/// live data, saving a PNG of its own window after each (no screen-recording permission needed).
/// It signs up a throwaway account in a temporary folder, so real accounts are never touched.
///   Files: <app container>/tmp/kestrel-snapshots/NN-name.png
@MainActor
enum SnapshotTour {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-snapshot") }

    static let folder = FileManager.default.temporaryDirectory.appending(path: "kestrel-snapshots", directoryHint: .isDirectory)

    /// Accounts live in a scratch folder for the tour.
    static func makeAuth() -> AuthService {
        let root = FileManager.default.temporaryDirectory.appending(path: "kestrel-snapshot-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AuthService(root: root, sessions: MemorySessionStore())
    }

    static let screens = [
        "PORT", "W", "BTC GP", "BTC DEPTH", "ETH TAS", "TOP", "TSLA CN", "AAPL DES", "AAPL FA", "AAPL EVTS",
        "SPY HP", "SPY BT", "BTC OMON", "ETH OSA", "ECO", "CORR", "ERN", "HMAP", "WEI", "MOST", "FX", "COMD", "RATES",
        "ALRT", "BLOT", "SOL BUY", "PREF", "PRO", "HELP",
    ]

    /// Phase 0, on the subscribe page: capture it, then unlock (debug override) to continue.
    static func subscribeStep() async {
        try? FileManager.default.removeItem(at: folder)
        try? await Task.sleep(for: .seconds(5))
        capture("00a-subscribe")
        BackgroundAlerts.store?.tourOverride = true
    }

    /// Phase 1, on the sign-in screen: capture it, then create the throwaway account.
    static func signIn(_ auth: AuthService) async {
        log("SNAPSHOT sign-in tour started")
        try? await Task.sleep(for: .seconds(5))
        capture("00-sign-in")
        do throws(AuthError) {
            try await auth.register(name: "Snapshot Tour", email: "tour@kestrel.test", password: "graphite ledger kite", confirm: "graphite ledger kite")
            log("SNAPSHOT signed in")
        } catch { log("SNAPSHOT sign-up failed: \(error)") }
    }

    /// Phase 2, in the terminal: every function full-screen, then the 4- and 6-panel layouts.
    static func run(_ ws: Workspace) async {
        log("SNAPSHOT terminal tour started")
        try? await Task.sleep(for: .seconds(4))
        ws.maximized = nil
        ws.layout = .one
        for (n, cmd) in screens.enumerated() {
            ws.focused = 0
            _ = ws.run(cmd)
            try? await Task.sleep(for: .seconds(cmd.contains("OMON") || cmd.contains("OSA") || cmd.contains("BT") || cmd == "CORR" ? 7 : 4))
            capture(String(format: "%02d-%@", n + 1, cmd.replacingOccurrences(of: " ", with: "-")))
        }
        ws.layout = .four
        for (i, c) in ["TOP", "W", "BTC DEPTH", "TOP"].enumerated() { ws.focused = i; _ = ws.run(c) }
        try? await Task.sleep(for: .seconds(6))
        capture("90-layout-4")
        ws.layout = .six
        for (i, c) in ["PORT", "W", "BTC DEPTH", "ETH TAS", "TOP", "ECO"].enumerated() { ws.focused = i; _ = ws.run(c) }
        try? await Task.sleep(for: .seconds(6))
        capture("91-layout-6")
        log("SNAPSHOT TOUR DONE \(folder.path)")
    }

    /// Appends to <folder>/log.txt (stdout is buffered or detached when launched via `open`).
    static func log(_ line: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "log.txt")
        let data = Data((Date().formatted(.iso8601) + " " + line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
    }

    static func capture(_ name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name + ".png")
        #if os(macOS)
        guard let view = (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { log("SNAPSHOT no window for \(name)"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        log("SNAPSHOT size \(name) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
        do { try rep.representation(using: .png, properties: [:])?.write(to: url); log("SNAPSHOT \(url.path)") }
        catch { log("SNAPSHOT write failed \(error)") }
        #else
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: url)
        #endif
    }
}
#else
/// Release builds never run the snapshot tour.
enum SnapshotTour { static let isEnabled = false }
#endif
