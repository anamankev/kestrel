#if os(macOS)
import AppKit
import SwiftUI

/// Keeps a window on its screen. A frame saved by an older build (or restored from another,
/// larger display) can be wider than the visible screen; at launch and on every screen change
/// the window is shrunk and moved so all of it is visible.
enum WindowFit {
    /// The frame to use, or nil when `frame` already fits inside `visible`.
    static func fitted(_ frame: CGRect, in visible: CGRect, minSize: CGSize = CGSize(width: 1100, height: 700)) -> CGRect? {
        guard frame.width > visible.width || frame.height > visible.height ||
              !visible.contains(frame) else { return nil }
        let w = min(frame.width, visible.width), h = min(frame.height, visible.height)
        let size = CGSize(width: max(min(w, visible.width), min(minSize.width, visible.width)),
                          height: max(min(h, visible.height), min(minSize.height, visible.height)))
        let x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

struct WindowFitter: NSViewRepresentable {
    final class Probe: NSView {
        nonisolated(unsafe) private var observer: NSObjectProtocol?   // only touched on the main thread and in deinit
        nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { Self.fit(window) }
            #if DEBUG
            // `-capture`: save what this real window shows (your account, layout, data) 10 s after launch.
            if ProcessInfo.processInfo.arguments.contains("-capture") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    Self.trace(window, "capture")
                    guard let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appending(path: "kestrel-live.png"))
                }
            }
            #endif
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.fit(window) }
            }
            #if DEBUG
            resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.trace(window, "resized") }
            }
            #endif
        }
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }

        #if DEBUG
        /// Debug builds record every window size change with the screen and the content's demands,
        /// to diagnose sizing reports from real use. File: <container>/tmp/kestrel-window.log
        static func trace(_ window: NSWindow, _ event: String) {
            let url = FileManager.default.temporaryDirectory.appending(path: "kestrel-window.log")
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let fit = window.contentView?.fittingSize ?? .zero
            let line = "\(Date().formatted(.iso8601)) \(event) frame=\(Int(window.frame.minX)),\(Int(window.frame.minY)) \(Int(window.frame.width))x\(Int(window.frame.height)) screen=\(Int(screen.width))x\(Int(screen.height)) contentMin=\(Int(window.contentMinSize.width))x\(Int(window.contentMinSize.height)) fitting=\(Int(fit.width))x\(Int(fit.height)) zoomed=\(window.isZoomed) fullscreen=\(window.styleMask.contains(.fullScreen)) windows=\(NSApp.windows.filter(\.isVisible).count)\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? Data(line.utf8).write(to: url) }
        }
        #endif

        static func fit(_ window: NSWindow) {
            #if DEBUG
            trace(window, "launch-before")
            defer { trace(window, "launch-after") }
            #endif
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame,
                  let target = WindowFit.fitted(window.frame, in: visible) else { return }
            window.setFrame(target, display: true, animate: false)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
#endif
