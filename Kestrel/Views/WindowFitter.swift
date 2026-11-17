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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { Self.fit(window) }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.fit(window) }
            }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        static func fit(_ window: NSWindow) {
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame,
                  let target = WindowFit.fitted(window.frame, in: visible) else { return }
            window.setFrame(target, display: true, animate: false)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
#endif
