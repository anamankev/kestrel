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
        "SPY HP", "SPY BT", "BTC OMON", "ETH OSA", "ECO", "ECST JAPAN", "CORR", "ERN", "SECF TOYOTA", "NVDA BETA", "MSFT FACT", "NVDA EVST", "KO DVD", "COMP", "MVO", "EQS", "HMAP", "WEI", "MOST", "FX", "COMD", "RATES",
        "ALRT", "BLOT", "SOL BUY", "PREF", "PRO", "HELP",
    ]

    /// `-guide "q1|q2"`: open the guide, ask each question, capture the panel.
    static var guideQuestions: [String]? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-guide"), i + 1 < a.count else { return nil }
        return a[i + 1].split(separator: "|").map(String.init)
    }
    static weak var guide: GuideService?

    static var grids: [[String]] {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-grids"), i + 1 < a.count else { return [] }
        return a[i + 1].split(separator: ";").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// `-screens "SECF TOYOTA,7203.T DES"` captures just those commands.
    static var chosen: [String] {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("-grids") || a.contains("-guide"), !a.contains("-screens") { return [] }
        guard let i = a.firstIndex(of: "-screens"), i + 1 < a.count else { return screens }
        return a[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Phase 2, on the subscribe page after sign-up: capture it, then unlock (debug override).
    static func subscribeStep() async {
        try? await Task.sleep(for: .seconds(4))
        capture("00a-subscribe")
        BackgroundAlerts.store?.tourOverride = true
    }

    /// Phase 1, on the sign-in screen: capture it, then create the throwaway account.
    static func signIn(_ auth: AuthService) async {
        try? FileManager.default.removeItem(at: folder)
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
        for (n, cmd) in chosen.enumerated() {
            ws.focused = 0
            _ = ws.run(cmd)
            try? await Task.sleep(for: .seconds(cmd.contains("OMON") || cmd.contains("OSA") || cmd.contains("BT") || cmd == "CORR" || cmd.hasPrefix("ECST") || cmd == "EQS" || cmd.contains("EVST") ? 7 : 4))
            capture(String(format: "%02d-%@", n + 1, cmd.replacingOccurrences(of: " ", with: "-")))
        }
        if let qs = guideQuestions, let g = guide {
            g.isOpen = true
            try? await Task.sleep(for: .seconds(1.5))
            capture("70-guide-open")
            for (n, q) in qs.enumerated() {
                g.ask(q)
                try? await Task.sleep(for: .seconds(1))
                capture(String(format: "7%d-guide", n + 1))
                log("GUIDE Q: \(q) -> \(g.messages.last?.text ?? "") \(g.messages.last?.commands ?? [])")
            }
            if let cmd = g.messages.last?.commands.first { _ = g.run(cmd); try? await Task.sleep(for: .seconds(4)); capture("79-guide-ran") }
        }
        // `-grids "A,B,C,D;E,F,G,H,I,J"`: each group fills a 4- or 6-panel layout and is captured.
        for (g, group) in grids.enumerated() {
            ws.layout = group.count > 4 ? .six : group.count > 2 ? .four : .two
            for (i, c) in group.enumerated() { ws.focused = i; _ = ws.run(c) }
            try? await Task.sleep(for: .seconds(10))
            capture(String(format: "8%d-grid-%d", g, group.count))
        }
        guard grids.isEmpty, guideQuestions == nil else { finish(); return }
        ws.layout = .four
        for (i, c) in ["TOP", "W", "BTC DEPTH", "TOP"].enumerated() { ws.focused = i; _ = ws.run(c) }
        try? await Task.sleep(for: .seconds(6))
        capture("90-layout-4")
        ws.layout = .six
        for (i, c) in ["PORT", "W", "BTC DEPTH", "ETH TAS", "TOP", "ECO"].enumerated() { ws.focused = i; _ = ws.run(c) }
        try? await Task.sleep(for: .seconds(6))
        capture("91-layout-6")
        finish()
    }

    /// Logs completion; on Mac the tour instance quits so repeated tours don't pile up windows.
    static func finish() {
        log("SNAPSHOT TOUR DONE \(folder.path)")
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
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
enum SnapshotTour {
    static let isEnabled = false
    static let guideQuestions: [String]? = nil
}
#endif
