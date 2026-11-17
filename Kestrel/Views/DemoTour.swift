import SwiftUI
import KestrelCore

/// Scripted product tour for screen recordings: launch with the `-demo` argument.
///   xcrun simctl launch <device> dev.kestrel.terminal -demo
/// Commands are "typed" into the real command line and executed through the same
/// Workspace.run path a user hits, so the recording shows the actual app, not a mock.
@MainActor
enum DemoTour {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    struct Step {
        var panel: Int?
        var command: String?
        var layout: PanelLayout?
        var link: String?
        var hold: Double
    }

    static let script: [Step] = [
        Step(layout: .four, hold: 0.5),
        Step(panel: 0, command: "BTC GP", hold: 0.3),
        Step(panel: 1, command: "W", hold: 0.3),
        Step(panel: 2, command: "BTC DEPTH", hold: 0.3),
        Step(panel: 3, command: "TOP", hold: 5),
        Step(link: "ETH", hold: 4),                          // tap-to-link from the monitor
        Step(panel: 1, command: "ECO", hold: 4.5),
        Step(panel: 3, command: "HMAP", hold: 4),
        Step(panel: 1, command: "WEI", hold: 3.5),
        Step(layout: .one, hold: 0.2),
        Step(panel: 0, command: "BTC OMON", hold: 6.5),
        Step(panel: 0, command: "SPY HP", hold: 4.5),
        Step(panel: 0, command: "PORT", hold: 6),
        Step(layout: .four, hold: 0.2),
        Step(panel: 0, command: "BTC GP", hold: 4),
    ]

    /// Runs the tour, typing each command at ~14 characters per second.
    static func run(_ ws: Workspace, type: @escaping (String) -> Void) async {
        try? await Task.sleep(for: .seconds(4))          // let feeds connect and first quotes land
        for step in script {
            if let l = step.layout { ws.maximized = nil; ws.layout = l }
            if let t = step.link, let i = Universe.resolve(t) { ws.link(i, from: 1) }
            if let p = step.panel, let c = step.command {
                ws.focused = p
                var typed = ""
                for ch in c {
                    typed.append(ch)
                    type(typed)
                    try? await Task.sleep(for: .milliseconds(70))
                }
                try? await Task.sleep(for: .milliseconds(250))
                ws.run(c)
                type("")
            }
            try? await Task.sleep(for: .seconds(step.hold))
        }
    }
}
