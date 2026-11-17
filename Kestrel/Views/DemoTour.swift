import SwiftUI
import KestrelCore

/// Scripted product walkthrough for screen recordings: launch a Debug build with `-demo`.
///   xcrun simctl launch <device> dev.kestrel.terminal -demo
/// It signs up a throwaway account in a temporary folder (real accounts are never touched),
/// opens on the subscribe page, then types every function into the real command line through the
/// same Workspace.run path a user hits, with a caption for each. Writes DEMO DONE to the
/// snapshot log (tmp/kestrel-snapshots/log.txt) when finished.
@MainActor
enum DemoTour {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    /// The caption shown over the app while the demo runs.
    @Observable final class Caption {
        static let shared = Caption()
        var text: String?
    }

    struct Step {
        var panel: Int?
        var command: String?
        var layout: PanelLayout?
        var link: String?
        var caption: String?
        var hold: Double
    }

    static func go(_ command: String, _ caption: String, _ hold: Double, panel: Int = 0) -> Step {
        Step(panel: panel, command: command, caption: caption, hold: hold)
    }

    static let script: [Step] = [
        // Workspace
        Step(layout: .four, caption: "Four linked panels · live Coinbase crypto", hold: 0.3),
        Step(panel: 0, command: "BTC GP", hold: 0.2),
        Step(panel: 1, command: "W", hold: 0.2),
        Step(panel: 2, command: "BTC DEPTH", hold: 0.2),
        Step(panel: 3, command: "ETH TAS", hold: 4.5),
        Step(link: "ETH", caption: "Tap a security to load it into every linked panel", hold: 4),
        Step(layout: .one, hold: 0.2),
        // Any security, any market
        go("SECF TOYOTA", "SECF · find any security on any exchange", 4.5),
        go("7203.T DES", "DES · Toyota in Tokyo: quote, range, every function one tap away", 4),
        go("NVDA GP", "GP · charts with indicators and trendlines", 4),
        go("AAPL FA", "FA · financial statements from SEC 10-K filings", 4.5),
        go("AAPL EVTS", "EVTS · SEC filings and corporate events", 3.5),
        go("TSLA CN", "CN · company news", 3.5),
        go("KO DVD", "DVD · ten years of dividends, yield and growth", 4.5),
        // Research
        go("NVDA BETA", "BETA · regression on any benchmark, with t-stats", 5),
        go("MSFT FACT", "FACT · Fama-French factor models (CAPM, FF3, Carhart, FF5)", 5),
        go("HD EVST", "EVST · earnings event study, including today's release", 6),
        go("SPY HP", "HP · price history with CSV export", 3.5),
        go("SPY BT", "BT · backtest strategies against buy-and-hold", 6),
        go("EQS", "EQS · screen ~5,700 US companies on 10-K data", 6.5),
        go("COMP", "COMP · total-return comparison of your watchlist", 5),
        go("MVO", "MVO · efficient frontier, min-variance and max-Sharpe weights", 6),
        go("CORR", "CORR · cross-asset correlation matrix", 6),
        go("ERN", "ERN · projected earnings calendar for your watchlist", 4.5),
        // Options
        go("BTC OMON", "OMON · option chain, greeks, volatility smile", 6),
        go("ETH OSA", "OSA · option strategy payoffs and breakevens", 6),
        // Markets & economy
        go("WEI", "WEI · world equity indices", 3.5),
        go("FX", "FX · G10, crosses and emerging-market currencies", 3.5),
        go("COMD", "COMD · energy, metals, crops, livestock, index and rate futures", 4),
        go("RATES", "RATES · US Treasury yields", 3),
        go("HMAP", "HMAP · heat map", 3.5),
        go("MOST", "MOST · top movers", 3),
        go("ECO", "ECO · US economy from BLS and the New York Fed", 4),
        go("ECST JAPAN", "ECST · World Bank statistics for 217 countries", 5),
        go("TOP", "TOP · market news with search and filters", 4),
        // Paper trading
        go("SOL BUY", "TRADE · paper orders: market, limit, stop, stop-limit", 4.5),
        go("PORT", "PORT · P&L and risk: beta, VaR, expected shortfall", 4),
        go("NVDA ALRT", "ALRT · price alerts, even with the app closed", 3.5),
        go("HELP", "HELP · every function in one directory", 4),
        // Finale
        Step(layout: .six, caption: "Up to six panels at once", hold: 0.2),
        Step(panel: 0, command: "BTC GP", hold: 0.1),
        Step(panel: 1, command: "W", hold: 0.1),
        Step(panel: 2, command: "BTC DEPTH", hold: 0.1),
        Step(panel: 3, command: "EQS", hold: 0.1),
        Step(panel: 4, command: "TOP", hold: 0.1),
        Step(panel: 5, command: "ECO", hold: 6),
        Step(caption: "Kestrel · iPad and Mac", hold: 3),
    ]

    #if DEBUG
    /// The walkthrough opens on the subscribe page: create the throwaway account straight away.
    static func signIn(_ auth: AuthService) async {
        do throws(AuthError) {
            try await auth.register(name: "Demo", email: "demo@kestrel.test", password: "graphite ledger kite", confirm: "graphite ledger kite")
        } catch { SnapshotTour.log("DEMO sign-up failed: \(error)") }
    }

    /// On the subscribe page: show the plans, then unlock (debug override).
    static func subscribeStep() async {
        try? await Task.sleep(for: .seconds(1.5))         // let the plans load before the caption
        Caption.shared.text = "Kestrel Pro · monthly, 6-month or annual · sign in, subscribe, then the terminal"
        try? await Task.sleep(for: .seconds(6))
        BackgroundAlerts.store?.tourOverride = true
    }
    #endif

    /// Runs the terminal part, typing each command at ~14 characters per second.
    static func run(_ ws: Workspace, type: @escaping (String) -> Void) async {
        try? await Task.sleep(for: .seconds(3))          // let feeds connect and first quotes land
        for step in script {
            if let c = step.caption { Caption.shared.text = c }
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
        Caption.shared.text = nil
        #if DEBUG
        SnapshotTour.log("DEMO DONE")
        #endif
    }
}

/// Bottom caption bar for the recorded walkthrough.
struct DemoCaptionBar: View {
    private let caption = DemoTour.Caption.shared

    var body: some View {
        if DemoTour.isEnabled, let t = caption.text {
            Text(t)
                .font(.ui(17, .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Theme.canvas.opacity(0.92), in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accentDim))
                .padding(.bottom, 64)
                .allowsHitTesting(false)
        }
    }
}
